param appSvcName string
param principalId string
param roleDefinitionId string

resource appSvc 'Microsoft.Web/sites@2022-03-01' existing = {
  name: appSvcName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(appSvc.id, principalId, roleDefinitionId)
  scope: appSvc
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
