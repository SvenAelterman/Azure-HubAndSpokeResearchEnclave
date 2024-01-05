param location string = resourceGroup().location
param namingStructure string
param keyVaultName string

@description('In debug mode, the debug remote IP address(es) should already be included in this array.')
param allowedIps array = []
param keyVaultAdmins array = []
param roles object = {}

param debugMode bool = false
param applyDeleteLock bool = !debugMode

param deploymentNameStructure string
param tags object

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'premium'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true

    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: true

    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90

    publicNetworkAccess: empty(allowedIps) ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: [for ip in allowedIps: {
        value: ip
      }]
    }
  }
  tags: tags
}

resource keyVaultLock 'Microsoft.Authorization/locks@2020-05-01' = if (applyDeleteLock) {
  scope: keyVault
  name: replace(namingStructure, '{rtype}', 'kv-lock')
  properties: {
    level: 'CanNotDelete'
    notes: 'Deleting this Key Vault will delete the encryption keys used for storage accounts and managed disks in this spoke. Deleting encryption keys will make this resources inaccessible.'
  }
}

module keyVaultAdminRbac '../../../module-library/roleAssignments/roleAssignment-kv.bicep' = [for (admin, i) in keyVaultAdmins: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-rbac-${i}'), 64)
  params: {
    kvName: keyVault.name
    principalId: admin
    roleDefinitionId: roles.KeyVaultAdministrator
  }
}]

// LATER: Private Endpoint

output keyVaultName string = keyVault.name
output id string = keyVault.id
output uri string = keyVault.properties.vaultUri
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().subscriptionId
