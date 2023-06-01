param vnet1ResourceId string
param vnet2ResourceId string
param deploymentNameStructure string

param vnet1FriendlyName string = ''
param vnet2FriendlyName string = ''

// Extract components of the VNet resource IDs by splitting the resource IDs
// Resource ID format:
// /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/virtualNetworks/<vnetName>
var vnet1ResourceIdSplit = split(vnet1ResourceId, '/')
var vnet2ResourceIdSplit = split(vnet2ResourceId, '/')

var vnet1SubscriptionId = vnet1ResourceIdSplit[2]
var vnet2SubscriptionId = vnet2ResourceIdSplit[2]

var vnet1ResourceGroupName = vnet1ResourceIdSplit[4]
var vnet2ResourceGroupName = vnet2ResourceIdSplit[4]

var vnet1Name = vnet1ResourceIdSplit[8]
var vnet2Name = vnet2ResourceIdSplit[8]

module vnet1ToVNet2PeeringModule 'peering.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'peering-vnet1'), 64)
  scope: resourceGroup(vnet1SubscriptionId, vnet1ResourceGroupName)
  params: {
    localVNetFriendlyName: !empty(vnet1FriendlyName) ? vnet1FriendlyName : vnet1Name
    localVNetName: vnet1Name
    remoteVNetFriendlyName: !empty(vnet2FriendlyName) ? vnet2FriendlyName : vnet2Name
    remoteVNetId: vnet2ResourceId
  }
}

module vnet2ToVNet1PeeringModule 'peering.bicep' = {
  // Can only establish one peering at a time, must wait for VNet1-to-VNet2 peering to complete
  dependsOn: [
    vnet1ToVNet2PeeringModule
  ]
  name: take(replace(deploymentNameStructure, '{rtype}', 'peering-vnet2'), 64)
  scope: resourceGroup(vnet2SubscriptionId, vnet2ResourceGroupName)
  params: {
    localVNetFriendlyName: !empty(vnet2FriendlyName) ? vnet2FriendlyName : vnet2Name
    localVNetName: vnet2Name
    remoteVNetFriendlyName: !empty(vnet1FriendlyName) ? vnet1FriendlyName : vnet1Name
    remoteVNetId: vnet1ResourceId
  }
}
