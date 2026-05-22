// ============================================================
// Role Assignments module
//
// Grants the Function App managed identity the minimum roles:
//
//  On cost-export storage account:
//    - Storage Blob Data Reader  (blob trigger + CSV read)
//
//  On function-internal storage account:
//    - Storage Blob Data Contributor  (webjobs leases)
//    - Storage Queue Data Contributor (webjobs queues)
//    - Storage Table Data Contributor (webjobs tables)
//
//  On Data Collection Rule:
//    - Monitoring Metrics Publisher   (Logs Ingestion API)
// ============================================================

@description('Object (principal) ID of the Function App system-assigned managed identity.')
param functionAppPrincipalId string

@description('Resource ID of the cost-export storage account.')
param costStorageAccountId string

@description('Resource ID of the function-internal storage account.')
param funcStorageAccountId string

@description('Resource ID of the Data Collection Rule.')
param dcrId string

// ---- Built-in role definition IDs ----------------------------

var storageBlobDataReader       = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var storageBlobDataContributor  = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var storageQueueDataContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var storageTableDataContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var monitoringMetricsPublisher  = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')

// ---- Cost-export storage -------------------------------------

resource roleBlobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(costStorageAccountId, functionAppPrincipalId, storageBlobDataReader)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: storageBlobDataReader
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    description: 'CostImporter Function App — read cost-export blobs'
  }
}

// ---- Function-internal storage: blob, queue, table -----------

resource roleFuncBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccountId, functionAppPrincipalId, storageBlobDataContributor)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: storageBlobDataContributor
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    description: 'CostImporter Function App — webjobs blob leases'
  }
}

resource roleFuncQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccountId, functionAppPrincipalId, storageQueueDataContributor)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: storageQueueDataContributor
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    description: 'CostImporter Function App — webjobs queues'
  }
}

resource roleFuncTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccountId, functionAppPrincipalId, storageTableDataContributor)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: storageTableDataContributor
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    description: 'CostImporter Function App — webjobs tables'
  }
}

// ---- Data Collection Rule ------------------------------------

resource roleMonitorPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcrId, functionAppPrincipalId, monitoringMetricsPublisher)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: monitoringMetricsPublisher
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    description: 'CostImporter Function App — Logs Ingestion API'
  }
}
