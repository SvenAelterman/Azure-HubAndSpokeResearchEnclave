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

@description('An array of valid SMB file share names to create.')
param fileShareNames array
@description('An array of valid Blob container names to create.')
param containerNames array

param debugMode bool = false
param debugRemoteIp string = ''

param storageAccountPrivateEndpointGroups array = [
  'blob'
  'file'
]

@description('The type of identity to use for identity-based authentication to the file share.')
@allowed([ 'AADDS', 'AADKERB', 'None' ])
param filesIdentityType string

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultSubscriptionId, keyVaultResourceGroupName)
}

var privateDnsZonesResourceGroupIdSplit = split(privateDnsZonesResourceGroupId, '/')

var privateDnsZonesSubscriptionId = privateDnsZonesResourceGroupIdSplit[2]
var privateDnsZonesResourceGroupName = privateDnsZonesResourceGroupIdSplit[4]

// Ensure the private DNS zones for storage exist and reference them
resource hubPrivateDnsZoneResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: privateDnsZonesResourceGroupName
  scope: subscription(privateDnsZonesSubscriptionId)
}

// Find the existing (in the hub) Private DNS Zones for storage account private endpoints
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' existing = [for subResource in storageAccountPrivateEndpointGroups: {
  name: 'privatelink.${subResource}.${az.environment().suffixes.storage}'
  scope: hubPrivateDnsZoneResourceGroup
}]

// Create an array of custom objects where each object represents a single private endpoint for the storage account
var storageAccountPrivateEndpointInfo = [for (subResource, i) in storageAccountPrivateEndpointGroups: {
  subResourceName: subResource
  dnsZoneId: privateDnsZones[i].id
  dnsZoneName: privateDnsZones[i].name
}]

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
    storageAccountName: storageAccountNameModule.outputs.shortName
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
  }
}

output storageAccountName string = storageAccountModule.outputs.name
output storageAccountId string = storageAccountModule.outputs.id
