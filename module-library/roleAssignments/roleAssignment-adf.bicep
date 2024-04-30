param adfName string
param principalId string
param roleDefinitionId string
param principalType string = ''

resource adf 'Microsoft.DataFactory/factories@2018-06-01' existing = {
  name: adfName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(adf.id, principalId, roleDefinitionId)
  scope: adf
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: !empty(principalType) ? principalType : null
  }
}
