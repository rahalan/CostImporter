# Azure Functions profile.ps1 — runs once per PowerShell worker on cold start.
# Keep this minimal so cold starts stay fast.

if ($env:MSI_SECRET -or $env:IDENTITY_ENDPOINT) {
    try {
        Disable-AzContextAutosave -Scope Process | Out-Null
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        Write-Host "Connected to Azure using managed identity."
    }
    catch {
        Write-Warning "Failed to connect with managed identity: $($_.Exception.Message)"
    }
}
else {
    Write-Warning "No managed identity detected. Logs Ingestion calls will fail unless running locally with az login."
    try { Disable-AzContextAutosave -Scope Process | Out-Null } catch { }
}
