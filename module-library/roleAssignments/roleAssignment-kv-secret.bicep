param kvName string
param principalId string
param roleDefinitionId string
param secretName string
param principalType string = ''

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' existing = {
  name: secretName
  parent: kv
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secret.id, principalId, roleDefinitionId)
  scope: secret
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: !empty(principalType) ? principalType : null
  }
}
