/******************************************************************************
*                                                                             *
* RESEARCH HUB MAIN TEMPLATE                                                  *
*                                                                             *
*******************************************************************************/

targetScope = 'subscription'

//------------------------------ START PARAMETERS ------------------------------

@description('The Azure region for the deployment of resources. Use the Name of the region (not the DisplayName) from the output of \'az account list-locations\'.')
param location string = deployment().location

@description('The deployment sequence. Each new sequence number will create a new deployment.')
param sequence int = 1

// TODO: "Environment" is going to be difficult to disambiguate. Public and Gov cloud are also called "environments." --> Rename to "purpose"?
@description('A maximum four-letter moniker for the environment type, such as \'dev\', \'test\', etc.')
@allowed([
  'dev'
  'test'
  'demo'
  'prod'
])
@maxLength(4)
param environment string = 'dev'

@description('The naming convention for Azure resources. Supported placeholders: {workloadName}, {subWorkloadName}, {environment}, {rtype}, {location}, {sequence}. Recommended separator is hyphen (\'-\'). If using a different separator, specify the namingConventionSeparator parameter.')
@minLength(1)
param namingConvention string = '{workloadName}-{subWorkloadName}-{environment}-{rtype}-{location}-{sequence}'

@description('The Azure built-in regulatory compliance framework to target. This will affect whether or not customer-managed keys, private endpoints, etc. are used. This will *not* deploy a policy assignment.')
@allowed([
  'NIST80053R5'
  'HIPAAHITRUST'
  'CMMC2L2'
  'NIST800171R2'
])
// Default to the strictest supported compliance framework
param complianceTarget string = 'NIST80053R5'

@description('Specifies if logons to virtual machines should use AD or AAD.')
@allowed([
  'ad'
  'aad'
])
#disable-next-line no-unused-params // LATER: Future use
param logonType string

@description('If true, will configure the deployment of AVD to make the AVD session hosts usable as research VMs. This will give full desktop access, flow the AVD traffic through the firewall, etc.')
param useSessionHostAsResearchVm bool = false

/*
 * Optional deployment elements for the Research Hub
 */

@description('If true, will deploy a Bastion host in the virtual network; otherwise, Bastion will not be deployed.')
param deployBastion bool = true

@description('If true, will deploy a GatewaySubnet and VPN gateway in the virtual network; otherwise, VPN will not be deployed.')
param deployVpn bool = false

@description('If true, the research VMs will be AVD session hosts and AVD will be deployed in the spoke only for centralized airlock review purposes.')
param researchVmsAreSessionHosts bool = false

/*
 * Network configuration parameters for the research hub
 */

@description('The virtual network\'s address space in CIDR notation, e.g. 10.0.0.0/16. The last octet must be 0. The maximum IPv4 CIDR length is 24. The IPv6 CIDR length should be 64.')
param networkAddressSpace string

@description('Any additional subnets for the hub virtual network.')
param additionalSubnets object = {}

@description('Custom IP addresses to be used for the virtual network.')
param customDnsIPs array = []

/*
 * Optional control parameters
 */

param tags object = {}
param deploymentTime string = utcNow()
param addAutoDateCreatedTag bool = false
param addDateModifiedTag bool = true
param autoDate string = utcNow('yyyy-MM-dd')

//------------------------------- END PARAMETERS -------------------------------

var workloadName = 'ResearchHub'
var sequenceFormatted = format('{0:00}', sequence)
var resourceNamingStructure = replace(replace(replace(replace(namingConvention, '{workloadName}', workloadName), '{environment}', environment), '{sequence}', sequenceFormatted), '{location}', location)
var rgNamingStructure = replace(resourceNamingStructure, '{rtype}', 'rg')
var deploymentNameStructure = '${workloadName}-{rtype}-${deploymentTime}'

var dateCreatedTag = addAutoDateCreatedTag ? {
  'date-created': autoDate
} : {}

var dateModifiedTag = addDateModifiedTag ? {
  'date-modified': autoDate
} : {}

var actualTags = union(tags, dateCreatedTag, dateModifiedTag)

var complianceFeatureMap = {
  NIST80053R5: {
    usePrivateEndpoints: true
    useCMK: true
  }
  NIST800171R2: {
    usePrivateEndpoints: true
    useCMK: true
  }
  HIPAAHITRUST: {
    usePrivateEndpoints: false
    useCMK: false
  }
  // TODO: Verify these
  CMMC2L2: {
    usePrivateEndpoints: true
    useCMK: false
  }
}

// Use private endpoints when targeting NIST 800-53 R5 or CMMC 2.0 Level 2
#disable-next-line no-unused-vars // LATER: Future use
var usePrivateEndpoints = complianceFeatureMap[complianceTarget].usePrivateEndpoints
// Use customer-managed keys when targeting NIST 800-53 R5
#disable-next-line no-unused-vars // LATER: Future use
var useCMK = complianceFeatureMap[complianceTarget].useCMK

// TODO: Should not be necessary anymore using private endpoints
#disable-next-line no-unused-vars // LATER: Future use
var avdTrafficThroughFirewall = useSessionHostAsResearchVm

/*
 * DEFINE THE RESEARCH HUB VIRTUAL NETWORK'S SUBNETS
 */

// Variable to hold the subnets that are always required, regardless of optional components
// TODO: Change subnet names to match the naming convention *Subnet: DataSubnet, AirlockSubnet, etc.
var requiredSubnets = {
  data: {
    serviceEndpoints: []
    routes: []
    securityRules: []
    delegation: ''
    // TODO: Update when redeploying entirely, make it smaller
    order: 5
    subnetCidr: 24
  }
  AzureFirewallSubnet: {
    serviceEndpoints: []
    routes: loadJsonContent('../shared-modules/networking/routes/AzureFirewall.json')
    //securityRules: [] Azure Firewall does not support NSGs on its subnets
    delegation: ''
    order: 4
    subnetCidr: 24
  }
  AzureFirewallManagementSubnet: {
    serviceEndpoints: []
    routes: loadJsonContent('../shared-modules/networking/routes/AzureFirewall.json')
    //securityRules: [] Azure Firewall does not support NSGs on its subnets
    delegation: ''
    order: 3
    subnetCidr: 24
  }
  airlock: {
    serviceEndpoints: []
    routes: [] // Routes through the firewall will be added later
    securityRules: [] // TODO: Allow RDP only from the AVD and Bastion subnets?
    delegation: ''
    order: 3 // The fourth /27-sized subnet
    subnetCidr: 27 // There will never be many airlock review virtual machines taking up addresses
  }
}

var AzureBastionSubnet = deployBastion ? {
  AzureBastionSubnet: {
    serviceEndpoints: []
    //routes: [] Bastion doesn't support routes
    securityRules: loadJsonContent('./hub-modules/networking/securityRules/bastion.jsonc')
    delegation: ''
    order: 0 // The first /26, in the first /24 block
    subnetCidr: 26 // Minimum for AzureBastionSubnet
  }
} : {}

var GatewaySubnet = deployVpn ? {
  GatewaySubnet: {
    routes: []
    // securityRules: [] Does not support NSGs
    delegation: ''
    order: 2 // There will already be a /26 for Bastion if enabled, so this becomes the third /27
    subnetCidr: 27 // Minimum recommended for GatewaySubnet
  }
} : {}

var AvdSubnet = !researchVmsAreSessionHosts ? {
  AvdSubnet: {
    serviceEndpoints: []
    routes: [] // Routes through the firewall will be added later, but we create the route table here
    securityRules: []
    delegation: ''
    order: 2 // The third /24
    subnetCidr: 24
  }
} : {}

// Combine all subnets into a single object
var subnets = union(requiredSubnets, AzureBastionSubnet, GatewaySubnet, AvdSubnet, additionalSubnets)

/*
 * Calculate the subnet addresses
 */

var actualSubnets = [for (subnet, i) in items(subnets): {
  // Add a new property addressPrefix to each subnet definition. If addressPrefix property was already defined, it will be respected.
  '${subnet.key}': union({
      // If the subnet specifies its own CIDR size, use it; otherwise, use the default
      addressPrefix: cidrSubnet(networkAddressSpace, subnet.value.subnetCidr, subnet.value.order)
    }, subnet.value)
}]

var actualSubnetObject = reduce(actualSubnets, {}, (cur, next) => union(cur, next))

//------------------------------- END VARIABLES --------------------------------

/*
 * CREATE THE RESEARCH HUB NETWORK RESOURCES
 */

// LATER: Collapse into a single main network module for the hub

// Create the network resource group
resource networkRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  #disable-next-line BCP334
  name: take(replace(rgNamingStructure, '{subWorkloadName}', 'networking'), 64)
  location: location
  tags: actualTags
}

// Create the route tables, network security groups, and virtual network
module networkModule '../shared-modules/networking/main.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'network')
  scope: networkRg
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    namingStructure: replace(resourceNamingStructure, '-{subWorkloadName}', '')
    subnetDefs: actualSubnetObject
    vnetAddressPrefixes: [ networkAddressSpace ]

    customDnsIPs: customDnsIPs

    tags: actualTags
  }
}

/*
 * Deploy the research hub firewall
 */

module azureFirewallModule 'hub-modules/azureFirewall.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'azfw'), 64)
  scope: networkRg
  params: {
    firewallManagementSubnetId: networkModule.outputs.createdSubnets.AzureFirewallManagementSubnet.id
    firewallSubnetId: networkModule.outputs.createdSubnets.AzureFirewallSubnet.id
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'firewall')
    tags: actualTags
    location: location
  }
}

/*
 * Optionally, deploy Azure Bastion
 */

module bastionModule 'hub-modules/networking/bastion.bicep' = if (deployBastion) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'bas'), 64)
  scope: networkRg
  params: {
    location: location
    bastionSubnetId: networkModule.outputs.createdSubnets.AzureBastionSubnet.id
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'bas')
    tags: actualTags
  }
}

/*
 * Optionally, deploy a VPN gateway
 */

module vpnGatewayModule 'hub-modules/networking/vpnGateway.bicep' = if (deployVpn) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'vpngw'), 64)
  scope: networkRg
  params: {
    location: location
    gatewaySubnetId: networkModule.outputs.createdSubnets.GatewaySubnet.id
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'vpn')
    tags: actualTags
  }
}

/*
 * Deploy all private DNS zones
 */

// LATER: Ignore this if peering to a hub virtual network, which should already have these
module allPrivateDnsZonesModule 'hub-modules/dns/allPrivateDnsZones.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zones'), 64)
  scope: networkRg
  params: {
    tags: actualTags
    deploymentNameStructure: deploymentNameStructure
  }
}

// TODO: Link all private DNS zones to the hub virtual network

/*
 * Deploy Azure Virtual Desktop
 */

// TODO: Move this to the AVD module because AVD in the hub might be optional
// Modify the AVD route table to route traffic through the Azure Firewall
module avdRouteTableModule '../shared-modules/networking/rt.bicep' = if (!researchVmsAreSessionHosts) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rt-avd-fw'), 64)
  scope: networkRg
  params: {
    location: location
    // TODO: Move routes to JSON file and replace tokens for FW IP
    routes: [
      {
        name: 'Internet_via_Firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azureFirewallModule.outputs.fwPrIp
        }
      }
      // TODO: Add routes to bypass FW for updates, Monitor, and conditionally AVD
    ]
    rtName: networkModule.outputs.createdSubnets.AvdSubnet.routeTableName
    tags: actualTags
  }
}

resource avdRg 'Microsoft.Resources/resourceGroups@2022-09-01' = if (!researchVmsAreSessionHosts) {
  #disable-next-line BCP334
  name: take(replace(rgNamingStructure, '{subWorkloadName}', 'avd'), 64)
  location: location
  tags: actualTags
}

// TODO: Customize AVD module to support full desktop for researchers, based on param value
// module avd 'hub-modules/avd/avd.bicep' = {
//   name: take(replace(deploymentNameStructure, '{rtype}', 'avd'), 64)
//   scope: avdRg

//   params: {
//     avdSubnetId: networkModule.outputs.createdSubnets.avd.id
//     avdVmHostNameStructure: 'rh-avd-vm'
//     deploymentNameStructure: deploymentNameStructure
//     namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'avd')
//     location: location
//     tags: actualTags
//   }

//   dependsOn: [
//     avdRouteTableModule
//     azureFirewallModule
//   ]
// }
