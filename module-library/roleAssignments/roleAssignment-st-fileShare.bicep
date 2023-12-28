param storageAccountName string
param principalId string
param roleDefinitionId string
param fileShareName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' existing = {
  name: 'default'
  parent: storageAccount
}

#disable-next-line BCP081
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/fileShares@2022-09-01' existing = {
  name: fileShareName
  parent: fileService
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(fileShare.id, principalId, roleDefinitionId)
  scope: fileShare
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
