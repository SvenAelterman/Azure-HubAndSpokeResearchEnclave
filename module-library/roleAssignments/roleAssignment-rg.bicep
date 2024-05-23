param principalId string
param roleDefinitionId string
param principalType string = ''
param description string = ''

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: !empty(principalType) ? principalType : ''
    description: description
  }
}
