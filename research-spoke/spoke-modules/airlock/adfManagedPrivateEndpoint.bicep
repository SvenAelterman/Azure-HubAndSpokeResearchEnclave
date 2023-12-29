param adfName string
param storageAccountId string
param storageAccountDisplayName string

// By default, create a private endpoint for ADLS Gen2 and file share endpoints
param privateEndpointGroupIDs array = [
  'dfs'
  'file'
]

// LATER: Hardcoded managed VNet name ('default')
resource privateEndpoint 'Microsoft.DataFactory/factories/managedVirtualNetworks/managedPrivateEndpoints@2018-06-01' = [for groupId in privateEndpointGroupIDs: {
  name: '${adfName}/default/pe-${storageAccountDisplayName}-${groupId}'
  properties: {
    privateLinkResourceId: storageAccountId
    groupId: groupId
  }
}]

// Only need to output a single private link resource because they all refer to the same storage account
output privateLinkResourceId string = privateEndpoint[0].properties.privateLinkResourceId
// Output all the private endpoint IDs: one per group
output privateEndpointIds array = [for i in range(0, length(privateEndpointGroupIDs)): privateEndpoint[i].properties.resourceId]
