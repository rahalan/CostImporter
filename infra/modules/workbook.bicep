// ============================================================
// Workbook module — Top 10 RGs by cost increase
// ============================================================
@description('Log Analytics workspace resource ID (bound to the workbook).')
param workspaceId string

@description('Azure region.')
param location string

@description('Workbook display name.')
param displayName string = 'CostImporter — Top 10 Resource Groups by Cost Increase'

// Inline the workbook serialized content.
// Keep in sync with top10-costincrease.workbook.json.
var workbookContent = loadTextContent('../workbooks/top10-costincrease.workbook.json')

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(workspaceId, displayName)
  location: location
  kind: 'shared'
  properties: {
    displayName: displayName
    serializedData: workbookContent
    sourceId: workspaceId
    category: 'workbook'
  }
}

output workbookId   string = workbook.id
output workbookName string = workbook.name
