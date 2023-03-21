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
param namingConvention string = '{workloadName}-{subWorkloadName}-{environment}-{rtype}-{location}-{sequence}'

@description('The Azure built-in regulatory compliance framework to target. This will affect whether or not customer-managed keys, private endpoints, etc. are used.')
@allowed([
  'NIST80053R5'
  'HIPAAHITRUST'
  'CMMC2L2'
])
#disable-next-line no-unused-params // LATER: Future use
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

/*
 * Network configuration parameters for the research hub
 */

@description('The virtual network\'s address space in CIDR notation, e.g. 10.0.0.0/16. Supports IPv4 only. The last octet must be 0. The maximum CIDR length is 24.')
param networkAddressSpace string = '10.40.0.0/16'

// HACK: Setting to fixed value of 24 until Bicep's native cidr() function is available
@maxValue(24)
@minValue(24)
param subnetCidr int = 24

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

// Use private endpoints when targeting NIST 800-53 R5 or CMMC 2.0 Level 2
#disable-next-line no-unused-vars // LATER: Future use
var usePrivateEndpoints = (complianceTarget == 'NIST80053R5' || complianceTarget == 'CMMC2L2') ? true : false
// Use customer-managed keys when targeting NIST 800-53 R5
#disable-next-line no-unused-vars // LATER: Future use
var useCMK = (complianceTarget == 'NIST80053R5') ? true : false

#disable-next-line no-unused-vars // LATER: Future use
var avdTrafficThroughFirewall = useSessionHostAsResearchVm

/*
 * DEFINE THE RESEARCH HUB VIRTUAL NETWORK'S SUBNETS
 * 
 * No need to define address space, it is dynamically added based on calculations later
 */

// Variable to hold the subnets that are always required, regardless of optional components
var requiredSubnets = {
  data: {
    serviceEndpoints: []
    routes: []
    securityRules: []
    delegation: ''
  }
  AzureFirewallSubnet: {
    serviceEndpoints: []
    routes: loadJsonContent('../shared-modules/networking/routes/AzureFirewall.json')
    //securityRules: [] Azure Firewall does not support NSGs on its subnet
    delegation: ''
  }
  AzureFirewallManagementSubnet: {
    serviceEndpoints: []
    routes: loadJsonContent('../shared-modules/networking/routes/AzureFirewall.json')
    //securityRules: [] Azure Firewall does not support NSGs on its subnet
    delegation: ''
  }
  avd: {
    serviceEndpoints: []
    routes: [] // Routes through the firewall will be added later
    securityRules: []
    delegation: ''
  }
  airlock: {
    serviceEndpoints: []
    routes: [] // Routes through the firewall will be added later
    securityRules: [] // TODO: Allow RDP only from the AVD and Bastion subnets?
    delegation: ''
  }
}

// TODO: Consider fixing the addressPrefix (or value of octet3/4 offset) of optional subnets so upon reconfiguration, there won't be changing address ranges
var AzureBastionSubnet = deployBastion ? {
  AzureBastionSubnet: {
    serviceEndpoints: []
    //routes: [] Bastion doesn't support routes
    securityRules: loadJsonContent('../shared-modules/networking/securityRules/bastion.json')
    delegation: ''
  }
} : {}

var subnets = union(requiredSubnets, AzureBastionSubnet)

/*
 * Calculate the subnet addresses
 * // TODO: Extract into a separate module?
 */

// Split the network address into usable elements
var networkAddressSplit = split(networkAddressSpace, '/')
var networkAddress = networkAddressSplit[0]
var networkAddressOctets = split(networkAddress, '.')

// Create a structure for the subnets' address spaces with placeholders for octet3 and/or octet4 // HACK: Will be removed with availability of Bicep cidr() function
var subnetAddressBase = '${networkAddressOctets[0]}.${networkAddressOctets[1]}.${subnetCidr <= 26 ? '{octet3}' : networkAddressOctets[3]}.${subnetCidr > 26 ? '{octet4}' : '0'}/${subnetCidr}'

var actualSubnets = [for (subnet, i) in items(subnets): {
  // Add a new property addressPrefix to each subnet definition. If addressPrefix property was already defined, it will be respected.
  '${subnet.key}': union({
      addressPrefix: replace(replace(subnetAddressBase, '{octet4}', string(i)), '{octet3}', string(i))
    }, subnet.value)
}]

var actualSubnetObject = reduce(actualSubnets, {}, (cur, next) => union(cur, next))

//------------------------------- END VARIABLES --------------------------------

/*
 * CREATE THE RESEARCH HUB VIRTUAL NETWORK
 */

resource networkRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: replace(rgNamingStructure, '{subWorkloadName}', 'networking')
  location: location
  tags: actualTags
}

module networkModule '../shared-modules/networking/network.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'network')
  scope: networkRg
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    namingStructure: replace(resourceNamingStructure, '-{subWorkloadName}', '')
    subnetDefs: actualSubnetObject
    vnetAddressPrefix: networkAddressSpace

    tags: actualTags
  }
}

/*
 * Deploy the research hub firewall
 */

module azureFirewallModule 'hub-modules/azureFirewall.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'azfw')
  scope: networkRg
  params: {
    firewallManagementSubnetId: networkModule.outputs.createdSubnets.AzureFirewallManagementSubnet.id
    firewallSubnetId: networkModule.outputs.createdSubnets.AzureFirewallSubnet.id
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'firewall')
    tags: tags
    location: location
  }
}

/*
 * Deploy Azure Virtual Desktop
 */

// TODO: Move this to the AVD module?
// Modify the AVD route table to route traffic through the Azure Firewall
module avdRouteTableModule '../shared-modules/networking/rt.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'rt-avd-fw')
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
    rtName: networkModule.outputs.createdSubnets.avd.routeTableName
  }
}

resource avdRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: replace(rgNamingStructure, '{subWorkloadName}', 'avd')
  location: location
}

// TODO: Customize AVD module to support full desktop for researchers, based on param value
// module avd 'hub-modules/avd/avd.bicep' = {
//   name: replace(deploymentNameStructure, '{rtype}', 'avd')
//   scope: avdRg

//   params: {
//     avdSubnetId: networkModule.outputs.createdSubnets.avd.id
//     avdVmHostNameStructure: 'rh-avd-vm'
//     deploymentNameStructure: deploymentNameStructure
//     namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'avd')
//     location: location
//     tags: tags
//   }

//   dependsOn: [
//     avdRouteTableModule
//     azureFirewallModule
//   ]
// }
