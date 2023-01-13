param uamiName string
param principalId string
param roleDefinitionId string

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' existing = {
  name: uamiName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(uami.id, principalId, roleDefinitionId)
  scope: uami
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
