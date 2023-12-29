param privateDnsZonesResourceGroupId string
param deploymentNameStructure string
param location string = resourceGroup().location
param tags object

// Reference to the Key Vault where encryption key is stored
param keyVaultName string
param keyVaultResourceGroupName string
param keyVaultSubscriptionId string

param namingConvention string
param sequence int
param workloadName string
param uamiId string
param privateEndpointSubnetId string
param namingStructure string

param storageAccountEncryptionKeyName string
@description('An array of valid SMB file share names to create.')
param fileShareNames array = [
  'userprofiles'
  'shared'
]
@description('An array of valid Blob container names to create.')
param containerNames array = []

param debugMode bool = false
param debugRemoteIp string = ''

param storageAccountPrivateEndpointGroups array = [
  'blob'
  'file'
]

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
    environment: ''
    namingConvention: namingConvention
    resourceType: 'st'
    sequence: sequence
    workloadName: workloadName
  }
}

// Create a storage account reachable over private endpoint only
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
    namingStructure: namingStructure
    fileShareNames: fileShareNames
    containerNames: containerNames
    privateEndpointSubnetId: privateEndpointSubnetId
  }
}

output storageAccountName string = storageAccountModule.outputs.name
