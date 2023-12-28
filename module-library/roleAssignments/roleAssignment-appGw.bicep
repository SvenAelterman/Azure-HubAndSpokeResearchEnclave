param appGwName string
param principalId string
param roleDefinitionId string

resource appGw 'Microsoft.Network/applicationGateways@2022-05-01' existing = {
  name: appGwName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appGw.id, principalId, roleDefinitionId)
  scope: appGw
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
