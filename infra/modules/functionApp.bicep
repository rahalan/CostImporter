// ============================================================
// Function App module
//   - Linux Consumption (Y1) plan
//   - PowerShell 7.4 Function App with system-assigned MI
//   - All required app settings (identity-based connections)
// ============================================================

@description('Function App name.')
param functionAppName string

@description('App Service Plan name.')
param planName string

@description('Azure region.')
param location string

@description('Storage account name for Function App internal use (webjobs). Identity-based.')
param funcStorageAccountName string

@description('Storage account name for cost-export blobs. Identity-based blob trigger.')
param costStorageAccountName string

@description('Blob container the trigger watches.')
param costBlobContainer string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Data Collection Endpoint ingestion URL.')
param dceEndpoint string

@description('DCR immutable ID.')
param dcrImmutableId string

@description('DCR stream name.')
param streamName string

// ---- Consumption plan (Linux) --------------------------------

resource plan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true   // Required for Linux
  }
}

// ---- Function App --------------------------------------------

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PowerShell|7.4'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        // Identity-based connection for function-internal storage (no key needed)
        { name: 'AzureWebJobsStorage__accountName',       value: funcStorageAccountName }
        { name: 'AzureWebJobsStorage__blobServiceUri',    value: 'https://${funcStorageAccountName}.blob.core.windows.net' }
        { name: 'AzureWebJobsStorage__queueServiceUri',   value: 'https://${funcStorageAccountName}.queue.core.windows.net' }
        { name: 'AzureWebJobsStorage__tableServiceUri',   value: 'https://${funcStorageAccountName}.table.core.windows.net' }
        // Runtime
        { name: 'FUNCTIONS_EXTENSION_VERSION',            value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME',               value: 'powershell' }
        { name: 'FUNCTIONS_WORKER_RUNTIME_VERSION',       value: '7.4' }
        // Observability
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING',  value: appInsightsConnectionString }
        { name: 'ApplicationInsightsAgent_EXTENSION_VERSION', value: '~3' }
        // Cost-export blob trigger (identity-based, no connection string)
        { name: 'CostStorage__blobServiceUri',            value: 'https://${costStorageAccountName}.blob.core.windows.net' }
        { name: 'CostBlobContainer',                      value: costBlobContainer }
        // Logs Ingestion API
        { name: 'DceIngestionEndpoint',                   value: dceEndpoint }
        { name: 'DcrImmutableId',                         value: dcrImmutableId }
        { name: 'DcrStreamName',                          value: streamName }
      ]
    }
  }
}

// ---- Outputs -------------------------------------------------

output functionAppName string = functionApp.name
output functionAppId   string = functionApp.id
output principalId     string = functionApp.identity.principalId
