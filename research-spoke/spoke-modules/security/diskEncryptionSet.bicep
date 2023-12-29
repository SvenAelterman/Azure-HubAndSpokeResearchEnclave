param keyVaultId string
param keyUrl string
param location string
param name string
param tags object
param deploymentNameStructure string
param kvRoleDefinitionId string
param uamiId string = ''

// Azure US Government doesn't support user-assigned managed identities for
// Disk Encryption Sets to retrieve keys from Key Vault
var isAzureUSGov = az.environment().name == 'AzureUSGovernment'
var useSystemAssignedManagedIdentityOnly = isAzureUSGov

resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2023-04-02' = {
  name: name
  location: location
  identity: {
    type: useSystemAssignedManagedIdentityOnly ? 'SystemAssigned' : 'SystemAssigned, UserAssigned'
    userAssignedIdentities: useSystemAssignedManagedIdentityOnly ? null : {
      '${uamiId}': {}
    }
  }
  properties: {
    activeKey: {
      sourceVault: {
        id: keyVaultId
      }
      keyUrl: keyUrl
    }
    encryptionType: 'EncryptionAtRestWithPlatformAndCustomerKeys'
    rotationToLatestKeyVersionEnabled: true
  }
  tags: tags
}

var kvIdSplit = split(keyVaultId, '/')
var kvSubscriptionId = kvIdSplit[2]
var kvResourceGroupName = kvIdSplit[4]
var keyVaultName = kvIdSplit[8]

// Added here because we can't assume that the Key Vault is in the same resource group as the Disk Encryption Set
resource kvRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: kvResourceGroupName
  scope: subscription(kvSubscriptionId)
}

// Grant a role to the Disk Encryption Set on the Key Vault if using system-assigned identity
module kvRbacModule '../../../module-library/roleAssignments/roleAssignment-kv.bicep' = if (useSystemAssignedManagedIdentityOnly) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-des-rbac'), 64)
  scope: kvRg
  params: {
    kvName: keyVaultName
    principalId: diskEncryptionSet.identity.principalId
    roleDefinitionId: kvRoleDefinitionId
  }
}

output id string = diskEncryptionSet.id
