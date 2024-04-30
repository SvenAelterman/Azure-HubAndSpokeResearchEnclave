/*
 * Handles the manipulation of the airlock review resources in the hub.
 */

param deploymentNameStructure string
param centralAirlockResources object
param spokeUamiPrincipalId string
param roles object
param spokeAdfPrincipalId string

/*
 * CREATE REFERENCES TO CENTRALIZED (HUB) RESOURCES
 */

var centralAirlockSubscriptionId = split(centralAirlockResources.storageAccountId, '/')[2]
var centralAirlockResourceGroupName = split(centralAirlockResources.storageAccountId, '/')[4]
var centralAirlockStorageAccountName = split(centralAirlockResources.storageAccountId, '/')[8]

var centralAirlockKeyVaultSubscriptionId = split(centralAirlockResources.keyVaultId, '/')[2]
var centralAirlockKeyVaultResourceGroupName = split(centralAirlockResources.keyVaultId, '/')[4]
var centralAirlockKeyVaultName = split(centralAirlockResources.keyVaultId, '/')[8]

resource centralAirlockKeyVaultRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: centralAirlockKeyVaultResourceGroupName
  scope: subscription(centralAirlockKeyVaultSubscriptionId)
}

resource centralAirlockKeyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: centralAirlockKeyVaultName
  scope: centralAirlockKeyVaultRg
}

resource centralAirlockRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: centralAirlockResourceGroupName
  scope: subscription(centralAirlockSubscriptionId)
}

// END CENTRALIZED RESOURCES

module uamiAirlockStorageRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami-hub-airlock-role'), 64)
  scope: centralAirlockRg
  params: {
    principalId: spokeUamiPrincipalId
    roleDefinitionId: roles.StorageAccountContributor
    storageAccountName: centralAirlockStorageAccountName
    principalType: 'ServicePrincipal'
  }
}

module adfHubKvRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-kv.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-role-hubkv')
  scope: centralAirlockKeyVaultRg
  params: {
    kvName: centralAirlockKeyVault.name
    principalId: spokeAdfPrincipalId
    // Can't use the roles object here because it retrieved roleDefinitionIds from the spoke subscription
    // Even though the hub role definition ID is the same, it leads to a conflict because the roleDefinitionId is the full resource ID, including subscription ID
    // Which means that it doesn't get detected correctly as already existing.
    // This role definition ID is for the Key Vault Secrets User role.
    roleDefinitionId: subscriptionResourceId(
      centralAirlockSubscriptionId,
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
    principalType: 'ServicePrincipal'
  }
}

output centralAirlockStorageAccountName string = centralAirlockStorageAccountName
output centralKeyVaultUri string = centralAirlockKeyVault.properties.vaultUri
