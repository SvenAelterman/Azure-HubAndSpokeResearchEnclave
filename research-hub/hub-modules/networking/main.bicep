/*
 * DEPLOYS HUB NETWORK RESOURCES
 */

param networkAddressSpace string
param customDnsIPs array

param deployAvdSubnet bool
param deployAirlockSubnet bool
param deployBastion bool
@description('Mutually exclusive with useRemoteGateway.')
param deployVpn bool
@description('Mutually exclusive with deployVpn.')
param useRemoteGateway bool

param deployManagementSubnet bool = false

param additionalSubnets array

param peeringRemoteVNetId string
param remoteVNetFriendlyName string = ''
param vnetFriendlyName string = ''
param privateDnsZonesResourceGroupId string = ''

param firewallForcedTunnel bool = false
@description('The IP address of the NVA to route traffic through when using forced tunneling.')
param firewallForcedTunnelNvaIP string = ''

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param firewallTier string = 'Basic'

param includeActiveDirectoryFirewallRules bool = false
param includeDnsFirewallRules bool = false
@description('The entire IP address pool for this research environment, including all (future) spokes. This is usually a supernet/summarized CIDR.')
param ipAddressPool array = []
param domainControllerIPAddresses array = []

param location string
param tags object
param deploymentTime string
param deploymentNameStructure string
param resourceNamingStructure string
@description('The resource naming structure to use for IP Group resources. For ease of use when creating firewall rules, it is useful to change the order of the segments. Optiona; defaults to resourceNamingStructure.')
param ipGroupNamingStructure string = resourceNamingStructure

/*
 * DEFINE THE RESEARCH HUB VIRTUAL NETWORK'S SUBNETS
 */

var createManagementIPConfiguration = (firewallTier == 'Basic' || firewallForcedTunnel)

// TODO: Replace the {{nvaIPAddress}} placeholder with the upstream NVA's IP address
var AzureFirewallSubnetRoutes = firewallForcedTunnel ? [] : loadJsonContent('./routes/AzureFirewallNormal.jsonc')

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
    routes: AzureFirewallSubnetRoutes
    //securityRules: [] Azure Firewall does not support NSGs on its subnets
    delegation: ''
    order: 0
    subnetCidr: 26
  }
}

var AzureFirewallManagementSubnet = createManagementIPConfiguration
  ? {
      AzureFirewallManagementSubnet: {
        serviceEndpoints: []
        // A default route to the Internet on the Management subnet is required for Azure Firewall to function.
        // Adding an explicit route table to "document" and demonstrate the requirement.
        routes: loadJsonContent('./routes/AzureFirewallNormal.jsonc')
        //securityRules: [] Azure Firewall does not support NSGs on its subnets
        delegation: ''
        order: 1
        subnetCidr: 26
      }
    }
  : {}

var AirlockSubnet = deployAirlockSubnet
  ? {
      AirlockSubnet: {
        serviceEndpoints: []
        // Route 
        routes: [] // Routes through the firewall will be added later
        securityRules: [] // TODO: Allow RDP only from the AVD and Bastion subnets?
        delegation: ''
        order: 5 // The fourth /27-sized subnet
        subnetCidr: 27 // There will never be many airlock review virtual machines taking up addresses
      }
    }
  : {}

var AzureBastionSubnet = deployBastion
  ? {
      AzureBastionSubnet: {
        serviceEndpoints: []
        //routes: [] Bastion doesn't support routes
        securityRules: loadJsonContent('./securityRules/bastion.jsonc')
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
        routes: [] // Routes through the firewall will be added later, but we create the route table resource here
        securityRules: []
        delegation: ''
        order: 9 // The tenth /27
        subnetCidr: 27
      }
    }
  : {}

var ManagementSubnet = deployManagementSubnet
  ? {
      ManagementSubnet: {
        serviceEndpoints: []
        routes: [] // Routes through the firewall will be added later, but we create the route table resource here
        securityRules: []
        order: 11 // The twelfth /27
        subnetCidr: 27
      }
    }
  : {}

// Combine all subnets into a single object
var subnets = union(
  requiredSubnets,
  AzureBastionSubnet,
  GatewaySubnet,
  AvdSubnet,
  AirlockSubnet,
  AzureFirewallManagementSubnet,
  ManagementSubnet
)

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

    additionalSubnets: additionalSubnets

    customDnsIPs: customDnsIPs

    tags: tags

    remoteVNetResourceId: peeringRemoteVNetId
    remoteVNetFriendlyName: remoteVNetFriendlyName
    vnetFriendlyName: vnetFriendlyName
  }
}

// TODO: Use AVM Module
// https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/ip-group
// Create IP Groups for certain IP ranges
module poolIPGroupModule '../../../shared-modules/networking/ipGroup.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'ipg-pool'), 64)
  params: {
    // TODO: Ensure name is limited to 80 characters
    name: replace(ipGroupNamingStructure, '{rtype}', 'ipg-Research_IP_Pool')
    location: location
    ipAddresses: ipAddressPool
    tags: tags
  }
}

module managementSubnetIPGroupModule '../../../shared-modules/networking/ipGroup.bicep' = if (deployManagementSubnet) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'ipg-mgmt'), 64)
  params: {
    name: replace(ipGroupNamingStructure, '{rtype}', 'ipg-Mgmt_Subnet')
    location: location
    ipAddresses: [networkModule.outputs.createdSubnets.ManagementSubnet.addressPrefix]
    tags: tags
  }
  // Cannot simultaneously deploy multiple IP Groups that are already in use by the same firewall
  dependsOn: [poolIPGroupModule]
}

// TODO: Additional IP Groups: Active Directory IPs, DNS IPs, AVD subnet range (if present)

/*
 * Deploy the research hub firewall
 */

module azureFirewallModule './azureFirewall.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'azfw'), 64)
  params: {
    firewallManagementSubnetId: networkModule.outputs.createdSubnets.AzureFirewallManagementSubnet.id
    firewallSubnetId: networkModule.outputs.createdSubnets.AzureFirewallSubnet.id
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'firewall')
    firewallTier: firewallTier
    tags: tags
    location: location
    forcedTunneling: firewallForcedTunnel

    includeActiveDirectoryRules: includeActiveDirectoryFirewallRules
    includeDnsRules: includeDnsFirewallRules
    ipAddressPoolIPGroupId: poolIPGroupModule.outputs.id
    dnsServerIPAddresses: customDnsIPs
    domainControllerIPAddresses: domainControllerIPAddresses
    includeManagementSubnetRules: deployManagementSubnet
    managementSubnetIPGroupId: deployManagementSubnet ? managementSubnetIPGroupModule.outputs.id : ''
    // TODO: AVD session host support in hub
    //includeAvdSubnetRules: deployAvdSubnet
  }
}

// When forced tunneling is enabled, add a route to the NVA on the FirewallSubnet
module firewallRouteTableModule '../../../shared-modules/networking/rt.bicep' = if (firewallForcedTunnel) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rt-fw-nva'), 64)
  params: {
    location: location

    routes: json(replace(
      loadTextContent('./routes/AzureFirewallForcedTunnel.jsonc'),
      '{{nvaIPAddress}}',
      firewallForcedTunnelNvaIP
    ))

    rtName: networkModule.outputs.createdSubnets.AzureFirewallSubnet.routeTableName
    tags: tags
  }
}

// Modify the AVD route table to route traffic through the Azure Firewall
module avdRouteTableModule '../../../shared-modules/networking/rt.bicep' = if (deployAvdSubnet) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rt-avd-fw'), 64)
  params: {
    location: location

    routes: json(replace(
      loadTextContent('../../../shared-modules/networking/routes/DefaultToNVA.jsonc'),
      '{{nvaIPAddress}}',
      azureFirewallModule.outputs.fwPrIp
    ))

    rtName: networkModule.outputs.createdSubnets.AvdSubnet.routeTableName
    tags: tags
  }
}

// Modify the AVD route table to route traffic through the Azure Firewall
module mgmtRouteTableModule '../../../shared-modules/networking/rt.bicep' = if (deployManagementSubnet) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rt-mgmt-fw'), 64)
  params: {
    location: location

    routes: json(replace(
      loadTextContent('../../../shared-modules/networking/routes/DefaultToNVA.jsonc'),
      '{{nvaIPAddress}}',
      azureFirewallModule.outputs.fwPrIp
    ))

    rtName: networkModule.outputs.createdSubnets.ManagementSubnet.routeTableName
    tags: tags
  }
}

// Modify the Airlock route table to route traffic through the Azure Firewall
module airlockRouteTableModule '../../../shared-modules/networking/rt.bicep' = if (deployAirlockSubnet) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rt-airlock-fw'), 64)
  params: {
    location: location

    routes: json(replace(
      loadTextContent('../../../shared-modules/networking/routes/DefaultToNVA.jsonc'),
      '{{nvaIPAddress}}',
      azureFirewallModule.outputs.fwPrIp
    ))

    rtName: networkModule.outputs.createdSubnets.AirlockSubnet.routeTableName
    tags: tags
  }
}

/*
 * Optionally, deploy Azure Bastion
 */

module bastionModule './bastion.bicep' = if (deployBastion) {
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

module vpnGatewayModule './vpnGateway.bicep' = if (deployVpn && !useRemoteGateway) {
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

module allPrivateDnsZonesModule '../dns/allPrivateDnsZones.bicep' =
  // Do not deploy Private Link's Private DNS zones if peering to a hub virtual network, which should already have these
  if (empty(privateDnsZonesResourceGroupId)) {
    name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zones'), 64)
    params: {
      tags: tags
      deploymentNameStructure: dnsZoneDeploymentNameStructure
      vnetId: networkModule.outputs.vNetId
    }
  }

// TODO: Fix the route tables when the firewall's IP address is known

output createdSubnets object = networkModule.outputs.createdSubnets
output vNetId string = networkModule.outputs.vNetId
output fwPrivateIPAddress string = azureFirewallModule.outputs.fwPrIp
