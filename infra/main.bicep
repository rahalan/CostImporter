// ============================================================
// CostImporter — main deployment
// ============================================================
// Deploys:
//   - Two storage accounts (cost exports + function internal)
//   - Log Analytics workspace + custom table
//   - Application Insights
//   - Data Collection Endpoint + Data Collection Rule
//   - Event Grid system topic (subscription created post-deploy)
//   - Linux Consumption Function App (PowerShell 7.4)
//   - All required RBAC role assignments
// ============================================================
targetScope = 'resourceGroup'

// ---- Parameters -----------------------------------------------

@description('Short base name used to derive all resource names (lowercase letters and digits only).')
@minLength(2)
@maxLength(10)
param baseName string

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Name of the blob container the cost-exporter job writes CSVs into.')
param costBlobContainer string = 'cost-exports'

@description('Log Analytics custom-table / DCR stream name.')
param streamName string = 'Custom-AzureCosts_CL'

@description('Log Analytics data retention in days (7–730).')
@minValue(7)
@maxValue(730)
param retentionDays int = 90

// ---- Locals ---------------------------------------------------

var suffix = take(uniqueString(resourceGroup().id, baseName), 8)

var costStorageName = 'stcost${suffix}'    // cost-export blobs
var funcStorageName = 'stfunc${suffix}'    // function-internal (webjobs)
var workspaceName   = 'law-${baseName}-${suffix}'
var appInsightsName = 'ai-${baseName}-${suffix}'
var dceName         = 'dce-${baseName}-${suffix}'
var dcrName         = 'dcr-${baseName}-${suffix}'
var planName        = 'plan-${baseName}-${suffix}'
var functionAppName = 'func-${baseName}-${suffix}'

// ---- Modules --------------------------------------------------

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    costStorageAccountName: costStorageName
    funcStorageAccountName: funcStorageName
    location: location
    containerName: costBlobContainer
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    workspaceName: workspaceName
    appInsightsName: appInsightsName
    dceName: dceName
    dcrName: dcrName
    location: location
    streamName: streamName
    retentionDays: retentionDays
  }
}

module functionApp 'modules/functionApp.bicep' = {
  name: 'functionApp'
  params: {
    functionAppName: functionAppName
    planName: planName
    location: location
    funcStorageAccountName: funcStorageName
    costStorageAccountName: costStorageName
    costBlobContainer: costBlobContainer
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    dceEndpoint: monitoring.outputs.dceEndpoint
    dcrImmutableId: monitoring.outputs.dcrImmutableId
    streamName: streamName
  }
}

module workbook 'modules/workbook.bicep' = {
  name: 'workbook'
  params: {
    workspaceId: monitoring.outputs.workspaceId
    location: location
  }
}

module roles 'modules/roleAssignments.bicep' = {
  name: 'roleAssignments'
  params: {
    functionAppPrincipalId: functionApp.outputs.principalId
    costStorageAccountId: storage.outputs.costStorageAccountId
    funcStorageAccountId: storage.outputs.funcStorageAccountId
    dcrId: monitoring.outputs.dcrId
  }
}

// ---- Outputs --------------------------------------------------

@description('Function App name — use with: func azure functionapp publish <name>')
output functionAppName string = functionApp.outputs.functionAppName

@description('Cost-export storage account name.')
output costStorageAccountName string = storage.outputs.costStorageAccountName

@description('Log Analytics workspace name.')
output workspaceName string = workspaceName
output workspaceId   string = monitoring.outputs.workspaceId

@description('Event Grid system topic name (create the blob subscription after deploying the Function App).')
output eventGridTopicName string = storage.outputs.eventGridTopicName

@description('DCR immutable ID — stored automatically in the Function App settings.')
output dcrImmutableId string = monitoring.outputs.dcrImmutableId
