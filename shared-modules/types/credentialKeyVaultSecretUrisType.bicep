@description('The type representing the URIs of Key Vault secrets for credentials.')
@export()
type credentialKeyVaultSecretUrisType = {
  @description('The URI of the Key Vault secret storing the username.')
  username: string
  @description('The URI of the Key Vault secret storing the password.')
  password: string

  @description('The subscription ID of the Key Vault.')
  keyVaultSubscriptionId: string
  @description('The resource group name of the Key Vault.')
  keyVaultResourceGroupName: string
  @description('The name of the Key Vault.')
  keyVaultName: string
}
