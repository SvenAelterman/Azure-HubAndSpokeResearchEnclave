@maxLength(24)
param keyVaultName string
param secretName string
@secure()
param secretValue string

param valueDescription string = ''

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  name: secretName
  parent: keyVault
  properties: {
    value: secretValue
    // In Key Vault, the "content type" is a free-form string that can be used a description of the secret
    contentType: !empty(valueDescription) ? valueDescription : null
  }
}

output secretName string = secretName
