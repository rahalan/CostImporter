#Requires -Version 7.4
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Blob-triggered Azure Function that imports an Azure cost CSV into a Log Analytics
    custom table via the Logs Ingestion API (DCR-based).

.DESCRIPTION
    Triggered when the daily cost-exporter job drops a CSV in the configured container.
    The CSV is streamed, parsed in batches, and posted to a Data Collection Endpoint
    (DCE) which routes to a Data Collection Rule (DCR) and finally into a custom
    table in a Log Analytics workspace.

    Auth: The Function App's managed identity must have:
        - "Storage Blob Data Reader" on the source storage account
        - "Monitoring Metrics Publisher" on the DCR

.REQUIRED APP SETTINGS
    CostStorage__blobServiceUri  -> https://<account>.blob.core.windows.net (identity-based)
    CostBlobContainer            -> Container the blob trigger watches (e.g. "cost-exports")
    DceIngestionEndpoint         -> https://<dce>-<id>.<region>.ingest.monitor.azure.com
    DcrImmutableId               -> dcr-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    DcrStreamName                -> Custom-AzureCosts_CL  (must match DCR stream name)
    IngestionBatchSize           -> optional, default 1000
#>

param(
    [Parameter(Mandatory = $true)] $InputBlob,
    [Parameter(Mandatory = $true)] $TriggerMetadata
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$blobName     = $TriggerMetadata.Name
$invocationId = $TriggerMetadata.InvocationId
Write-Host "[$invocationId] Processing blob '$blobName'."

# ---------- Validate configuration ----------
$dceEndpoint    = $env:DceIngestionEndpoint
$dcrImmutableId = $env:DcrImmutableId
$streamName     = $env:DcrStreamName

foreach ($pair in @(
        @{ Name = 'DceIngestionEndpoint'; Value = $dceEndpoint },
        @{ Name = 'DcrImmutableId';       Value = $dcrImmutableId },
        @{ Name = 'DcrStreamName';        Value = $streamName }
    )) {
    if ([string]::IsNullOrWhiteSpace($pair.Value)) {
        throw "Required app setting '$($pair.Name)' is not configured."
    }
}

# Logs Ingestion API limit: 1 MB uncompressed per request. Keep batches below that.
$BatchSize  = [int]($env:IngestionBatchSize ?? 1000)
$MaxRetries = 5

function Get-IngestionToken {
    $resource = 'https://monitor.azure.com/'
    try {
        $token = (Get-AzAccessToken -ResourceUrl $resource -ErrorAction Stop).Token
        if (-not $token) { throw "Empty token returned." }
        return $token
    }
    catch {
        throw "Failed to acquire AAD token for $resource. Ensure the Function App has a managed identity. Inner: $($_.Exception.Message)"
    }
}

function Read-CostCsvRecords {
    param(
        [Parameter(Mandatory)] [System.IO.Stream] $Stream,
        [Parameter(Mandatory)] [string]           $SourceBlob
    )

    $reader = [System.IO.StreamReader]::new($Stream)
    try {
        $csv = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    $rows = $csv | ConvertFrom-Csv
    $nowIso = (Get-Date).ToUniversalTime().ToString('o')

    foreach ($row in $rows) {
        $record = [ordered]@{
            TimeGenerated = $nowIso
            SourceBlob    = $SourceBlob
        }
        foreach ($prop in $row.PSObject.Properties) {
            if ([string]::IsNullOrWhiteSpace($prop.Name)) { continue }
            $record[$prop.Name] = $prop.Value
        }
        [pscustomobject]$record
    }
}

function Send-LogBatch {
    param(
        [Parameter(Mandatory)] [array]  $Batch,
        [Parameter(Mandatory)] [string] $Token
    )

    $uri = "$dceEndpoint/dataCollectionRules/$dcrImmutableId/streams/$streamName" + '?api-version=2023-01-01'
    $body = ConvertTo-Json -InputObject $Batch -Depth 10 -Compress
    $headers = @{
        Authorization  = "Bearer $Token"
        'Content-Type' = 'application/json'
    }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 60 | Out-Null
            return
        }
        catch {
            $status = $null
            try { $status = $_.Exception.Response.StatusCode.value__ } catch { }

            $retryable = (-not $status) -or ($status -in 408, 429, 500, 502, 503, 504)
            if (-not $retryable -or $attempt -eq $MaxRetries) {
                throw "Logs Ingestion POST failed (status=$status, attempt=$attempt): $($_.Exception.Message)"
            }

            $delay = [math]::Min(30, [math]::Pow(2, $attempt)) + (Get-Random -Minimum 0.0 -Maximum 1.0)
            Write-Warning "Ingestion attempt $attempt failed (status=$status). Retrying in $([math]::Round($delay,1))s."
            Start-Sleep -Seconds $delay
        }
    }
}

try {
    $token = Get-IngestionToken

    if ($InputBlob -isnot [System.IO.Stream]) {
        $InputBlob = [System.IO.MemoryStream]::new([byte[]]$InputBlob)
    }

    $batch = [System.Collections.Generic.List[object]]::new()
    $total = 0

    foreach ($record in (Read-CostCsvRecords -Stream $InputBlob -SourceBlob $blobName)) {
        $batch.Add($record) | Out-Null
        if ($batch.Count -ge $BatchSize) {
            Send-LogBatch -Batch $batch.ToArray() -Token $token
            $total += $batch.Count
            $batch.Clear()
        }
    }

    if ($batch.Count -gt 0) {
        Send-LogBatch -Batch $batch.ToArray() -Token $token
        $total += $batch.Count
    }

    Write-Host "[$invocationId] Ingested $total records from '$blobName' into stream '$streamName'."
}
catch {
    Write-Error "[$invocationId] Failed to import '$blobName': $($_.Exception.Message)"
    throw
}
