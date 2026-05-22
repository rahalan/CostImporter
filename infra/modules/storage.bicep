// ============================================================
// Storage module
//   - stcost* : cost CSV exports (blob trigger source)
//   - stfunc* : Azure Functions internal (webjobs queues/blobs/tables)
//   - Event Grid system topic on stcost (for Event Grid blob trigger)
// ============================================================
@description('Storage account name for cost-export blobs.')
param costStorageAccountName string

@description('Storage account name for Function App internal use.')
param funcStorageAccountName string

@description('Azure region.')
param location string

@description('Blob container name for cost-export CSVs.')
param containerName string

// ---- Cost-export storage account ------------------------------

resource costStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: costStorageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource costBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: costStorage
  name: 'default'
}

resource costContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: costBlobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// ---- Function-internal storage account -----------------------

resource funcStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: funcStorageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// ---- Event Grid system topic ----------------------------------
// Required to use the Event Grid-sourced blob trigger.
// After deploying, create an event subscription pointing to the
// Function App webhook endpoint (see README post-deploy steps).

resource egTopic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: 'evgt-${costStorageAccountName}'
  location: location
  properties: {
    source: costStorage.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// ---- Outputs --------------------------------------------------

output costStorageAccountId   string = costStorage.id
output costStorageAccountName string = costStorage.name
output funcStorageAccountId   string = funcStorage.id
output funcStorageAccountName string = funcStorage.name
output eventGridTopicName     string = egTopic.name
