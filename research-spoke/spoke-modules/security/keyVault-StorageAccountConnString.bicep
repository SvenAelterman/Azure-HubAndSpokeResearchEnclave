targetScope = 'subscription'

param storageAccountResourceGroupName string
param storageAccountName string

param keyVaultResourceGroupName string
@maxLength(24)
param keyVaultName string

param whichKey int = 1

resource storageAccountResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: storageAccountResourceGroupName
}

resource keyVaultResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: keyVaultResourceGroupName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageAccountName
  scope: storageAccountResourceGroup
}

// The secret is the storage account's connection string, including the access key
var accessKey = storageAccount.listKeys().keys[(whichKey - 1)].value
var secretValue = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${accessKey};EndpointSuffix=${environment().suffixes.storage}'

module keyVaultSecretModule 'keyVault-Secret.bicep' = {
  name: '${storageAccountName}-kv-secret-${whichKey}'
  scope: keyVaultResourceGroup
  params: {
    keyVaultName: keyVaultName
    secretName: '${storageAccountName}-connstring${whichKey}'
    secretValue: secretValue
    valueDescription: '${storageAccountName} Access Key ${whichKey}'
  }
}

output secretName string = keyVaultSecretModule.outputs.secretName
