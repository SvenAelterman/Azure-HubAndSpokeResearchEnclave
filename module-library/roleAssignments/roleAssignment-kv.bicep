param kvName string
param principalId string
param roleDefinitionId string

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(kv.id, principalId, roleDefinitionId)
  scope: kv
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
