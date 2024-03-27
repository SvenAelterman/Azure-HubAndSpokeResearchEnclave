/*
 * DEPLOYS HUB NETWORK RESOURCES
 */

param networkAddressSpace string
param customDnsIPs array

param deployAvdSubnet bool
param deployBastion bool
@description('Mutually exclusive with useRemoteGateway.')
param deployVpn bool
@description('Mutually exclusive with deployVpn.')
param useRemoteGateway bool

param additionalSubnets array

param peeringRemoteVNetId string
param remoteVNetFriendlyName string = ''
param vnetFriendlyName string = ''

param location string
param tags object
param deploymentTime string
param deploymentNameStructure string
param resourceNamingStructure string

/*
 * DEFINE THE RESEARCH HUB VIRTUAL NETWORK'S SUBNETS
 */

// Variable to hold the subnets that are always required, regardless of optional components
var requiredSubnets = {
  DataSubnet: {
    serviceEndpoints: []
    routes: []
    securityRules: []
    delegation: ''
    order: 4
    subnetCidr: 27
  }
  AzureFirewallSubnet: {
    serviceEndpoints: []
    routes: loadJsonContent('../../../shared-modules/networking/routes/AzureFirewall.json')
    //securityRules: [] Azure Firewall does not support NSGs on its subnets
    delegation: ''
    order: 0
    subnetCidr: 26
  }
  // TODO: The need for this subnet depends on the Firewall SKU and forced tunneling
  AzureFirewallManagementSubnet: {
    serviceEndpoints: []
    routes: loadJsonContent('../../../shared-modules/networking/routes/AzureFirewall.json')
    //securityRules: [] Azure Firewall does not support NSGs on its subnets
    delegation: ''
    order: 1
    subnetCidr: 26
  }
  AirlockSubnet: {
    serviceEndpoints: []
    routes: [] // Routes through the firewall will be added later
    securityRules: [] // TODO: Allow RDP only from the AVD and Bastion subnets?
    delegation: ''
    order: 5 // The fourth /27-sized subnet
    subnetCidr: 27 // There will never be many airlock review virtual machines taking up addresses
  }
}

var AzureBastionSubnet = deployBastion
  ? {
      AzureBastionSubnet: {
        serviceEndpoints: []
        //routes: [] Bastion doesn't support routes
        securityRules: loadJsonContent('../../hub-modules/networking/securityRules/bastion.jsonc')
        delegation: ''
        order: 3 // The first /26, in the first /24 block
        subnetCidr: 26 // Minimum for AzureBastionSubnet
      }
    }
  : {}

var GatewaySubnet = deployVpn && !useRemoteGateway
  ? {
      GatewaySubnet: {
        routes: []
        // securityRules: [] GatewaySubnet does not support NSGs
        delegation: ''
        order: 8 // There will already be a /26 for Bastion if enabled, so this becomes the third /27
        subnetCidr: 27 // Minimum recommended for GatewaySubnet
      }
    }
  : {}

var AvdSubnet = deployAvdSubnet
  ? {
      AvdSubnet: {
        serviceEndpoints: []
        routes: [] // Routes through the firewall will be added later, but we create the route table here
        securityRules: []
        delegation: ''
        order: 9 // The third /24
        subnetCidr: 27
      }
    }
  : {}

// Combine all subnets into a single object
var subnets = union(requiredSubnets, AzureBastionSubnet, GatewaySubnet, AvdSubnet)

/*
 * Calculate the subnet addresses
 */

var actualSubnets = [
  for (subnet, i) in items(subnets): {
    // Add a new property addressPrefix to each subnet definition. If addressPrefix property was already defined, it will be respected.
    '${subnet.key}': union(
      {
        // If the subnet specifies its own CIDR size, use it; otherwise, use the default
        addressPrefix: cidrSubnet(networkAddressSpace, subnet.value.subnetCidr, subnet.value.order)
      },
      subnet.value
    )
  }
]

var actualSubnetObject = reduce(actualSubnets, {}, (cur, next) => union(cur, next))

// Create the route tables, network security groups, and virtual network
module networkModule '../../../shared-modules/networking/main.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'network')
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    namingStructure: resourceNamingStructure
    subnetDefs: actualSubnetObject
    vnetAddressPrefixes: [networkAddressSpace]

    customDnsIPs: customDnsIPs

    tags: tags

    remoteVNetResourceId: peeringRemoteVNetId
    additionalSubnets: additionalSubnets
    remoteVNetFriendlyName: remoteVNetFriendlyName
    vnetFriendlyName: vnetFriendlyName
  }
}

/*
 * Deploy the research hub firewall
 */

module azureFirewallModule './azureFirewall.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'azfw'), 64)
  params: {
    firewallManagementSubnetId: networkModule.outputs.createdSubnets.AzureFirewallManagementSubnet.id
    firewallSubnetId: networkModule.outputs.createdSubnets.AzureFirewallSubnet.id
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'firewall')
    tags: tags
    location: location
  }
}

/*
 * Optionally, deploy Azure Bastion
 */

module bastionModule './bastion.bicep' =
  if (deployBastion) {
    name: take(replace(deploymentNameStructure, '{rtype}', 'bas'), 64)
    params: {
      location: location
      bastionSubnetId: networkModule.outputs.createdSubnets.AzureBastionSubnet.id
      namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'bas')
      tags: tags
    }
  }

/*
 * Optionally, deploy a VPN gateway
 */

module vpnGatewayModule './vpnGateway.bicep' =
  if (deployVpn && !useRemoteGateway) {
    name: take(replace(deploymentNameStructure, '{rtype}', 'vpngw'), 64)
    params: {
      location: location
      gatewaySubnetId: networkModule.outputs.createdSubnets.GatewaySubnet.id
      namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'vpn')
      tags: tags
    }
  }

/*
 * Deploy all private DNS zones
 */

var dnsZoneDeploymentNameStructure = '{rtype}-${deploymentTime}'

// LATER: Ignore this if peering to a hub virtual network, which should already have these
module allPrivateDnsZonesModule '../dns/allPrivateDnsZones.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zones'), 64)
  params: {
    tags: tags
    deploymentNameStructure: dnsZoneDeploymentNameStructure
    vnetId: networkModule.outputs.vNetId
  }
}

output createdSubnets object = networkModule.outputs.createdSubnets
output vNetId string = networkModule.outputs.vNetId
output fwPrivateIPAddress string = azureFirewallModule.outputs.fwPrIp
