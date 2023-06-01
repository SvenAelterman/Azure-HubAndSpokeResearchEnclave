/******************************************************************************
*                                                                             *
* MAIN NETWORK MODULE                                                         *
*                                                                             *
*******************************************************************************/

@description('Name of the virtual network to be created. If blank, the name will be generated from the namingStructure parameter.')
param vNetName string = ''
param location string

/*
  Object Schema
  subnet-name: {
    addressPrefix: string (required)
    serviceEndpoints: array (optional)
    securityRules: array (optional; if ommitted, no NSG will be created. If [], a default NSG will be created.)
    routes: array (optional; if ommitted, no route table will be created. If [], an empty route table will be created.)
    delegation: string (optional, can be ommitted or be empty string)
  } */
@description('A custom object defining the subnet properties of each subnet. { subnet-name: { addressPrefix: string, serviceEndpoints: [], securityRules: [], routes: [], delegation: string } }')
param subnetDefs object
@description('String representing the naming convention where \'{rtype}\' is a placeholder for vnet, rt, nsg, etc.')
param namingStructure string

@description('Provide a name for the deployment. Optionally, leave an \'{rtype}\' placeholder, which will be replaced with the common resource abbreviation for Virtual Network.')
param deploymentNameStructure string

@description('A IPv4 or IPv6 address space in CIDR notation.')
param vnetAddressPrefix string

@description('The Azure resource tags to apply to network security group, route table, and virtual network resources.')
param tags object = {}

@description('Custom DNS IP addresses to use for the virtual network. If empty (default), will use Azure DNS.')
param customDnsIPs array = []

@description('If peering with a hub network, specify the hub network\'s Azure resource ID. Leave empty (default) if no peering desired.')
param remoteVNetResourceId string = ''
@description('Optional even when peering. Only used when peering to create the name of the peering. If blank, the peering name will use the VNet name.')
param remoteVNetFriendlyName string = ''

@description('Optional even when peering. Only used when peering to create the name of the peering. If blank, the peering name will use the VNet name.')
param vnetFriendlyName string = ''

var virtualNetworkName = !empty(vNetName) ? vNetName : replace(namingStructure, '{rtype}', 'vnet')

// Create a network security group for each subnet that requires one
module networkSecurityModule 'networkSecurity.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'networkSecurity'), 64)
  params: {
    subnetDefs: subnetDefs
    deploymentNameStructure: deploymentNameStructure
    namingStructure: namingStructure
    location: location
    tags: tags
  }
}

var nsgIds = reduce(networkSecurityModule.outputs.networkSecurityGroups, {}, (cur, next) => union(cur, next))

// Create a route table for each subnet that requires one
module networkRoutingModule 'networkRouting.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'networkRouting'), 64)
  params: {
    deploymentNameStructure: deploymentNameStructure
    namingStructure: namingStructure
    subnetDefs: subnetDefs
    location: location
    tags: tags
  }
}

var routeTableIds = reduce(networkRoutingModule.outputs.routeTables, {}, (cur, next) => union(cur, next))

// This is the parent module to deploy a VNet with subnets and output the subnets with their IDs as a custom object
module vNetModule 'vnet.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'vnet'), 64)
  params: {
    location: location
    subnetDefs: subnetDefs
    vnetName: virtualNetworkName
    vnetAddressPrefix: vnetAddressPrefix
    networkSecurityGroups: nsgIds
    routeTables: routeTableIds
    customDnsIPs: customDnsIPs
    tags: tags
  }
}

// Create peering to hub, if specified
module peeringModule 'networkPeering.bicep' = if (!empty(remoteVNetResourceId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'peering'), 64)
  params: {
    deploymentNameStructure: deploymentNameStructure
    vnet1ResourceId: remoteVNetResourceId
    vnet2ResourceId: vNetModule.outputs.vNetId
    vnet1FriendlyName: vnetFriendlyName
    vnet2FriendlyName: remoteVNetFriendlyName
  }
}

@description('The properties of the subnets in the created virtual network.')
output createdSubnets object = reduce(vNetModule.outputs.actualSubnets, {}, (cur, next) => union(cur, next))
output vNetId string = vNetModule.outputs.vNetId

// For demonstration purposes only - this is not used (or usable, probably)
output vNetModuleSubnetsOutput array = vNetModule.outputs.actualSubnets
