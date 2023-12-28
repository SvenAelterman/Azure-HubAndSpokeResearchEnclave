param kvName string
param principalId string
param roleDefinitionId string

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, principalId, roleDefinitionId)
  scope: kv
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
