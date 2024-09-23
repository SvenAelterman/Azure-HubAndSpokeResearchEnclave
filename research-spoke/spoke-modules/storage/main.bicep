param privateDnsZonesResourceGroupId string
param deploymentNameStructure string
param location string = resourceGroup().location
param tags object

// Reference to the Key Vault where encryption key is stored
param keyVaultName string
param keyVaultResourceGroupName string
param keyVaultSubscriptionId string = subscription().subscriptionId
param storageAccountEncryptionKeyName string

param namingConvention string
param sequence int
param workloadName string
param subWorkloadName string = ''
param uamiId string
param privateEndpointSubnetId string
param namingStructure string
param environment string
@description('Determines if the storage account will allow access using the access keys.')
param allowSharedKeyAccess bool

@description('An array of valid SMB file share names to create.')
param fileShareNames array
@description('An array of valid Blob container names to create.')
param containerNames array

param createPolicyExemptions bool = false
param policyAssignmentId string = ''

param debugMode bool = false
param debugRemoteIp string = ''

param storageAccountPrivateEndpointGroups array = [
  'blob'
  'file'
]

@description('Role assignements to create on the storage account.')
param storageAccountRoleAssignments roleAssignmentType

import { roleAssignmentType } from '../../../shared-modules/types/roleAssignment.bicep'

@description('The type of identity to use for identity-based authentication to the file share. When using AD DS, set to None.')
@allowed(['AADDS', 'AADKERB', 'None'])
param filesIdentityType string

// Required for AD join
param domainJoin bool = false
param domainJoinInfo activeDirectoryDomainInfo = {
  adDomainFqdn: ''
  domainJoinPassword: ''
  domainJoinUsername: ''
}
param hubSubscriptionId string = ''
param hubManagementRgName string = ''
param hubManagementVmName string = ''
param uamiPrincipalId string = ''
param uamiClientId string = ''
param roles object = {}
// End required for AD join

// Types
import { activeDirectoryDomainInfo } from '../../../shared-modules/types/activeDirectoryDomainInfo.bicep'

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultSubscriptionId, keyVaultResourceGroupName)
}

var privateDnsZonesResourceGroupIdSplit = split(privateDnsZonesResourceGroupId, '/')

var privateDnsZonesSubscriptionId = privateDnsZonesResourceGroupIdSplit[2]
var privateDnsZonesResourceGroupName = privateDnsZonesResourceGroupIdSplit[4]

// var storageAccountContributorRoleDefinitionId = contains(roles, 'StorageAccountContributor')
//   ? roles.StorageAccountContributor
//   : ''

module uamiRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-rg.bicep' = if (domainJoin && length(fileShareNames) > 0) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami-rg-rbac'), 64)
  params: {
    principalId: uamiPrincipalId
    roleDefinitionId: roles.StorageAccountContributor
    principalType: 'ServicePrincipal'
    description: 'Role assignment for hub management VM to domain join storage account'
  }
}

// Ensure the private DNS zones for storage exist and reference them
resource hubPrivateDnsZoneResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: privateDnsZonesResourceGroupName
  scope: subscription(privateDnsZonesSubscriptionId)
}

// Find the existing (in the hub) Private DNS Zones for storage account private endpoints
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' existing = [
  for subResource in storageAccountPrivateEndpointGroups: {
    name: 'privatelink.${subResource}.${az.environment().suffixes.storage}'
    scope: hubPrivateDnsZoneResourceGroup
  }
]

// Create an array of custom objects where each object represents a single private endpoint for the storage account
var storageAccountPrivateEndpointInfo = [
  for (subResource, i) in storageAccountPrivateEndpointGroups: {
    subResourceName: subResource
    dnsZoneId: privateDnsZones[i].id
    dnsZoneName: privateDnsZones[i].name
  }
]

module storageAccountNameModule '../../../module-library/createValidAzResourceName.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'saname'), 64)
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'st'
    sequence: sequence
    workloadName: workloadName
    subWorkloadName: subWorkloadName
  }
}

// Create a storage account reachable over private endpoint only. S
module storageAccountModule 'storageAccount.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st'), 64)
  params: {
    location: location
    tags: tags
    encryptionKeyName: storageAccountEncryptionKeyName
    keyVaultUri: keyVault.properties.vaultUri
    storageAccountName: storageAccountNameModule.outputs.validName
    uamiId: uamiId
    privateEndpointInfo: storageAccountPrivateEndpointInfo

    debugMode: debugMode
    debugRemoteIp: debugRemoteIp

    // HACK: Need to account for empty subWorkloadName in which case the name might have two consecutive segment separators
    namingStructure: replace(namingStructure, '{subWorkloadName}', subWorkloadName)
    fileShareNames: fileShareNames
    containerNames: containerNames
    privateEndpointSubnetId: privateEndpointSubnetId

    filesIdentityType: filesIdentityType

    allowSharedKeyAccess: allowSharedKeyAccess

    createPolicyExemptions: createPolicyExemptions
    policyAssignmentId: policyAssignmentId

    storageAccountRoleAssignments: storageAccountRoleAssignments
  }
}

resource hubManagementRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: hubManagementRgName
  scope: subscription(hubSubscriptionId)
}

// Domain join to AD DS if needed, using the management VM in the hub
module domainJoinModule 'domainJoin.bicep' = if (domainJoin && length(fileShareNames) > 0) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-adjoin'), 64)
  scope: hubManagementRg
  params: {
    fileShareName: fileShareNames[0]
    identityDomainName: domainJoinInfo.adDomainFqdn
    identityServiceProvider: 'ADDS'
    managedIdentityClientId: uamiClientId
    ouStgPath: domainJoinInfo.adOuPath
    storageAccountFqdn: storageAccountModule.outputs.primaryFileFqdn
    storageAccountName: storageAccountModule.outputs.name
    storageObjectsRgName: resourceGroup().name
    storagePurpose: 'fslogix'
    adminUserName: domainJoinInfo.domainJoinUsername
    securityPrincipalName: 'none'
    workloadSubsId: subscription().subscriptionId
    hubManagementVmName: hubManagementVmName
    adminUserPassword: domainJoinInfo.domainJoinPassword
  }
}

output storageAccountName string = storageAccountModule.outputs.name
output storageAccountId string = storageAccountModule.outputs.id
output storageAccountFileShareBaseUncPath string = '\\\\${storageAccountModule.outputs.primaryFileFqdn}\\'
