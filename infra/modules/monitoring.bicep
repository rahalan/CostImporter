// ============================================================
// Monitoring module
//   - Log Analytics workspace
//   - AzureCosts_CL custom table
//   - Application Insights
//   - Data Collection Endpoint (DCE)
//   - Data Collection Rule (DCR)  → AzureCosts_CL
// ============================================================

// NOTE: Update the column list to match your cost-export CSV
// headers. The schema here covers the standard Azure Cost
// Management "ActualCost" export format.

@description('Log Analytics workspace name.')
param workspaceName string

@description('Application Insights resource name.')
param appInsightsName string

@description('Data Collection Endpoint name.')
param dceName string

@description('Data Collection Rule name.')
param dcrName string

@description('Azure region.')
param location string

@description('DCR stream name — must start with "Custom-" and end with "_CL".')
param streamName string

@description('Data retention in days.')
param retentionDays int

// ---- Log Analytics workspace ----------------------------------

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionDays
    features: {
      disableLocalAuth: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ---- Custom table ---------------------------------------------
// Table name = stream name with the leading "Custom-" stripped.

var tableName = replace(streamName, 'Custom-', '')

// Standard Azure Cost Management ActualCost export columns.
// Add/remove columns here AND in the DCR streamDeclarations below.
var tableColumns = [
  { name: 'TimeGenerated',          type: 'dateTime' }
  { name: 'SourceBlob',             type: 'string' }
  { name: 'BillingAccountId',       type: 'string' }
  { name: 'BillingAccountName',     type: 'string' }
  { name: 'BillingPeriodStartDate', type: 'dateTime' }
  { name: 'BillingPeriodEndDate',   type: 'dateTime' }
  { name: 'SubscriptionId',         type: 'string' }
  { name: 'SubscriptionName',       type: 'string' }
  { name: 'ResourceGroupName',      type: 'string' }
  { name: 'ResourceLocation',       type: 'string' }
  { name: 'ProductName',            type: 'string' }
  { name: 'MeterCategory',          type: 'string' }
  { name: 'MeterSubcategory',       type: 'string' }
  { name: 'MeterName',              type: 'string' }
  { name: 'UnitOfMeasure',          type: 'string' }
  { name: 'Quantity',               type: 'real' }
  { name: 'EffectivePrice',         type: 'real' }
  { name: 'CostInBillingCurrency',  type: 'real' }
  { name: 'Currency',               type: 'string' }
  { name: 'ConsumedService',        type: 'string' }
  { name: 'ResourceId',             type: 'string' }
  { name: 'ChargeType',             type: 'string' }
  { name: 'PublisherType',          type: 'string' }
  { name: 'ServiceFamily',          type: 'string' }
  { name: 'Tags',                   type: 'string' }
]

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      columns: tableColumns
    }
    retentionInDays: retentionDays
    totalRetentionInDays: retentionDays
  }
}

// ---- Application Insights ------------------------------------

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    DisableLocalAuth: true
  }
}

// ---- Data Collection Endpoint --------------------------------

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: dceName
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ---- Data Collection Rule ------------------------------------
// streamDeclarations must mirror the tableColumns above.
// Adjust both together whenever the schema changes.

resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrName
  location: location
  dependsOn: [customTable]
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      '${streamName}': {
        columns: tableColumns
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspace.id
          name: 'law-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [streamName]
        destinations: ['law-destination']
        outputStream: streamName
        transformKql: 'source'
      }
    ]
  }
}

// ---- Outputs -------------------------------------------------

output workspaceName                string = workspace.name
output workspaceId                  string = workspace.id
output appInsightsConnectionString  string = appInsights.properties.ConnectionString
output dceEndpoint                  string = dce.properties.logsIngestion.endpoint
output dcrImmutableId               string = dcr.properties.immutableId
output dcrId                        string = dcr.id
