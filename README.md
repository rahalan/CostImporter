# CostImporter

PowerShell Azure Function that imports daily Azure cost-export CSVs from Blob
Storage into a Log Analytics **custom table** via the Logs Ingestion API
(Data Collection Endpoint + Data Collection Rule).

## Architecture

```
Cost Exporter job ──> Storage Account (blob container)
                              │  (Event Grid blob created event)
                              ▼
                  Azure Function (PowerShell 7.4)
                     ImportCostCsv (blob trigger)
                              │  HTTPS, AAD token
                              ▼
        Data Collection Endpoint ──> Data Collection Rule
                              │
                              ▼
              Log Analytics workspace (Custom-AzureCosts_CL)
```

## Project layout

```
src/
  host.json                 Functions host config + extension bundle v4
  profile.ps1               Cold-start: connect with managed identity
  requirements.psd1         Managed dependencies (Az.Accounts)
  local.settings.json.sample
  ImportCostCsv/
    function.json           Blob trigger (Event Grid source)
    run.ps1                 CSV parse + Logs Ingestion API push
```

## Best practices applied

- **Identity-based connections**: `CostStorage__blobServiceUri` (no connection
  strings). Function App MI needs *Storage Blob Data Reader* on the account.
- **Event Grid blob trigger** (`"source": "EventGrid"`) — sub-second latency
  and scales beyond the legacy polling trigger.
- **Logs Ingestion API + DCR**, not the deprecated HTTP Data Collector API.
  Function App MI needs *Monitoring Metrics Publisher* on the DCR.
- **Streaming + batching** (`dataType: stream`, configurable `IngestionBatchSize`)
  to stay under the 1 MB request limit and bound memory for large exports.
- **Exponential backoff with jitter** on 408/429/5xx responses.
- **`Set-StrictMode -Version Latest`** and `$ErrorActionPreference = 'Stop'`.
- **PowerShell managed dependencies** pinned to a major version.
- **Application Insights** sampling enabled via `host.json`.

## Required app settings

| Setting | Description |
| --- | --- |
| `CostStorage__blobServiceUri` | `https://<account>.blob.core.windows.net` |
| `CostBlobContainer` | Container watched by the trigger (e.g. `cost-exports`) |
| `DceIngestionEndpoint` | DCE ingestion URL |
| `DcrImmutableId` | DCR immutable id (`dcr-…`) |
| `DcrStreamName` | Stream name in the DCR (e.g. `Custom-AzureCosts_CL`) |
| `IngestionBatchSize` | Optional, default `1000` |

## Infrastructure (Bicep)

Everything is provisioned by the Bicep templates in `infra/`:

```
infra/
  main.bicep             Orchestration — all modules wired together
  main.bicepparam        Sample parameters (edit before deploying)
  modules/
    storage.bicep        Cost-export + function-internal storage accounts
                         + Event Grid system topic
    monitoring.bicep     Log Analytics workspace, AzureCosts_CL custom table,
                         Application Insights, DCE, DCR
    functionApp.bicep    Linux Consumption plan + PowerShell 7.4 Function App
    roleAssignments.bicep  All RBAC assignments (least-privilege)
```

### Deploy infrastructure

```powershell
# 1. Edit the parameters file
notepad infra/main.bicepparam

# 2. Create a resource group
az group create --name rg-costimporter --location westeurope

# 3. Deploy
az deployment group create `
  --resource-group rg-costimporter `
  --template-file infra/main.bicep `
  --parameters infra/main.bicepparam
```

### Post-deploy: wire up the Event Grid blob subscription

The Function App uses an Event Grid-sourced blob trigger for sub-second latency.
After both the storage account and Function App are deployed, create the
subscription (replace placeholders with the `az deployment` outputs):

```powershell
$rg          = 'rg-costimporter'
$topicName   = '<eventGridTopicName output>'   # e.g. evgt-stcostxxxxxxxx
$funcApp     = '<functionAppName output>'
$subId       = (az account show --query id -o tsv)
$funcId      = (az functionapp show -g $rg -n $funcApp --query id -o tsv)
$systemKey   = (az functionapp keys list -g $rg -n $funcApp --query systemKeys.blobs -o tsv)
$endpoint    = "https://$funcApp.azurewebsites.net/runtime/webhooks/blobs?functionName=ImportCostCsv&code=$systemKey"

az eventgrid system-topic event-subscription create `
  --name "blob-to-importcostcsv" `
  --resource-group $rg `
  --system-topic-name $topicName `
  --endpoint-type webhook `
  --endpoint $endpoint `
  --included-event-types Microsoft.Storage.BlobCreated `
  --subject-begins-with '/blobServices/default/containers/cost-exports/'
```

### Deploy function code

```powershell
cd src
func azure functionapp publish <functionAppName>
```

## Local development

```powershell
cd src
Copy-Item local.settings.json.sample local.settings.json
# Fill in values, then:
func start
```
