param storageAccountName string
param principalId string
param roleDefinitionId string
param containerName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' existing = {
  name: 'default'
  parent: storageAccount
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' existing = {
  name: containerName
  parent: blobService
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(container.id, principalId, roleDefinitionId)
  scope: container
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
