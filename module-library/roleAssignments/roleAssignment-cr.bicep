param crName string
param principalId string
// Default: AcrPull
param roleDefinitionId string = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource cr 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' existing = {
  name: crName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(cr.id, principalId, roleDefinitionId)
  scope: cr
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
