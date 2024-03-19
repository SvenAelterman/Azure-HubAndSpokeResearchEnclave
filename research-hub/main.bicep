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

@description('The naming convention for Azure resources. Supported placeholders: {workloadName}, {subWorkloadName}, {env}, {rtype}, {loc}, {seq}. Recommended separator is hyphen (\'-\'). If using a different separator, specify the namingConventionSeparator parameter.')
@minLength(1)
param namingConvention string = '{workloadName}-{subWorkloadName}-{env}-{rtype}-{loc}-{seq}'

param workloadName string = 'ResearchHub'

@description('The Azure built-in regulatory compliance framework to target. This will affect whether or not customer-managed keys, private endpoints, etc. are used. This will *not* deploy a policy assignment.')
@allowed([
  'NIST80053R5'
  'HIPAAHITRUST'
  'CMMC2L2'
  'NIST800171R2'
])
// Default to the strictest supported compliance framework
param complianceTarget string = 'NIST80053R5'

@description('Specifies if logons to virtual machines should use AD or Entra ID.')
@allowed([
  'ad'
  'entraID'
])
#disable-next-line no-unused-params // LATER: Future use
param logonType string

/*
 * Optional deployment elements for the Research Hub
 */

@description('If true, will deploy a Bastion host in the virtual network; otherwise, Bastion will not be deployed.')
param deployBastion bool = true

@description('If true, will deploy a GatewaySubnet and VPN gateway in the virtual network; otherwise, VPN infrastructure will not be deployed.')
param deployVpn bool = false

@description('If true, the research VMs will be AVD session hosts and AVD will be deployed in the spoke only for centralized airlock review purposes.')
param researchVmsAreSessionHosts bool = false

@description('The number of jump box session hosts to deploy in the research hub. Only used if researchVmsAreSessionHosts is true.')
@minValue(0)
param jumpBoxSessionHostCount int = 1

@description('The size of the jump box ession hosts to deploy in the research hub. Only used if researchVmsAreSessionHosts is true.')
param jumpBoxSessionHostVmSize string = 'Standard_D2as_v5'

// Required if !researchVmsAreSessionHosts
@description('The local administrator username for the session host VMs. Required if researchVmsAreSessionHosts is false.')
@secure()
param sessionHostLocalAdminUsername string = ''
@description('The local administrator password for the session host VMs. Required if researchVmsAreSessionHosts is false.')
@secure()
param sessionHostLocalAdminPassword string = ''

// Required if logonType == ad and !researchVmsAreSessionHosts
@description('The username of a domain user or service account to use to join the Active Directory domain. Required if using AD join.')
@secure()
param domainJoinUsername string = ''
@description('The password of the domain user or service account to use to join the Active Directory domain. Required if using AD join.')
@secure()
param domainJoinPassword string = ''
@description('The fully qualified DNS name of the Active Directory domain to join. Required if using AD join.')
param adDomainFqdn string = ''

@description('Optional. The OU path in LDAP notation to use when joining the session hosts.')
param adOuPath string = ''

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
 * Entra ID object IDs for role assignments
 */

@description('The Entra ID object ID of the system administrator security group. Optional when using spoke session hosts as research VMs.')
param systemAdminObjectId string = ''

@description('If true, airlock reviews will take place centralized in the hub.')
param isAirlockReviewCentralized bool = false

@description('The date and time seed for the expiration of the encryption keys.')
param encryptionKeyExpirySeed string = utcNow()

// TODO: If no custom DNS IPs are specified, create a private DNS zone for the virtual network for VM auto-registration

/*
 * Optional control parameters
 */

param tags object = {}
param deploymentTime string = utcNow()
param addAutoDateCreatedTag bool = false
param addDateModifiedTag bool = true
param autoDate string = utcNow('yyyy-MM-dd')

param debugMode bool = false
// param debugRemoteIp string = ''
// param debugPrincipalId string = ''

//------------------------------- END PARAMETERS -------------------------------

//-------------------------------- START TYPES ---------------------------------

import { remoteAppApplicationGroup } from '../shared-modules/virtualDesktop/main.bicep'

//------------------------------- START VARIABLES ------------------------------

var sequenceFormatted = format('{0:00}', sequence)
var resourceNamingStructure = replace(
  replace(
    replace(replace(namingConvention, '{workloadName}', workloadName), '{env}', environment),
    '{seq}',
    sequenceFormatted
  ),
  '{loc}',
  location
)
var resourceNamingStructureNoSub = replace(resourceNamingStructure, '-{subWorkloadName}', '')
var rgNamingStructure = replace(resourceNamingStructure, '{rtype}', 'rg')
var deploymentNameStructure = '${workloadName}-{rtype}-${deploymentTime}'

var dateCreatedTag = addAutoDateCreatedTag
  ? {
      'date-created': autoDate
    }
  : {}

var dateModifiedTag = addDateModifiedTag
  ? {
      'date-modified': autoDate
    }
  : {}

var actualTags = union(tags, dateCreatedTag, dateModifiedTag)

var complianceFeatureMap = loadJsonContent('../shared-modules/compliance/complianceFeatureMap.jsonc')

// Use private endpoints when targeting NIST 800-53 R5 or CMMC 2.0 Level 2
#disable-next-line no-unused-vars // LATER: Future use
var usePrivateEndpoints = complianceFeatureMap[complianceTarget].usePrivateEndpoints
// Use customer-managed keys when targeting NIST 800-53 R5
var useCMK = complianceFeatureMap[complianceTarget].useCMK

// TODO: Should not be necessary anymore using private endpoints
#disable-next-line no-unused-vars // LATER: Future use
var avdTrafficThroughFirewall = researchVmsAreSessionHosts

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
  // TODO: The need for this subnet depends on the Firewall SKU and forced tunneling
  AzureFirewallManagementSubnet: {
    serviceEndpoints: []
    routes: loadJsonContent('../shared-modules/networking/routes/AzureFirewall.json')
    //securityRules: [] Azure Firewall does not support NSGs on its subnets
    delegation: ''
    order: 3
    subnetCidr: 24
  }
  AirlockSubnet: {
    serviceEndpoints: []
    routes: [] // Routes through the firewall will be added later
    securityRules: [] // TODO: Allow RDP only from the AVD and Bastion subnets?
    delegation: ''
    order: 3 // The fourth /27-sized subnet
    subnetCidr: 27 // There will never be many airlock review virtual machines taking up addresses
  }
}

var AzureBastionSubnet = deployBastion
  ? {
      AzureBastionSubnet: {
        serviceEndpoints: []
        //routes: [] Bastion doesn't support routes
        securityRules: loadJsonContent('./hub-modules/networking/securityRules/bastion.jsonc')
        delegation: ''
        order: 0 // The first /26, in the first /24 block
        subnetCidr: 26 // Minimum for AzureBastionSubnet
      }
    }
  : {}

var GatewaySubnet = deployVpn
  ? {
      GatewaySubnet: {
        routes: []
        // securityRules: [] GatewaySubnet does not support NSGs
        delegation: ''
        order: 2 // There will already be a /26 for Bastion if enabled, so this becomes the third /27
        subnetCidr: 27 // Minimum recommended for GatewaySubnet
      }
    }
  : {}

var AvdSubnet = !researchVmsAreSessionHosts
  ? {
      AvdSubnet: {
        serviceEndpoints: []
        routes: [] // Routes through the firewall will be added later, but we create the route table here
        securityRules: []
        delegation: ''
        order: 2 // The third /24
        subnetCidr: 24
      }
    }
  : {}

// Combine all subnets into a single object
var subnets = union(requiredSubnets, AzureBastionSubnet, GatewaySubnet, AvdSubnet, additionalSubnets)

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

var remoteDesktopAppPath = 'C:\\Windows\\System32\\mstsc.exe'

// Define the Windows built-in Remote Desktop application group and its single application
var remoteDesktopAppGroupInfo = {
  name: 'RemoteDesktopAppGroup'
  friendlyName: 'Remote Desktop'
  applications: [
    {
      name: 'RemoteDesktop'
      applicationType: 'InBuilt'
      filePath: remoteDesktopAppPath
      friendlyName: 'Remote Desktop'
      iconIndex: 0
      iconPath: remoteDesktopAppPath
      commandLineSetting: 'DoNotAllow'
      showInPortal: true
    }
  ]
}

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
    namingStructure: resourceNamingStructureNoSub
    subnetDefs: actualSubnetObject
    vnetAddressPrefixes: [networkAddressSpace]

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

module bastionModule 'hub-modules/networking/bastion.bicep' =
  if (deployBastion) {
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

module vpnGatewayModule 'hub-modules/networking/vpnGateway.bicep' =
  if (deployVpn) {
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

var dnsZoneDeploymentNameStructure = '{rtype}-${deploymentTime}'

// LATER: Ignore this if peering to a hub virtual network, which should already have these
module allPrivateDnsZonesModule 'hub-modules/dns/allPrivateDnsZones.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zones'), 64)
  scope: networkRg
  params: {
    tags: actualTags
    deploymentNameStructure: dnsZoneDeploymentNameStructure
    vnetId: networkModule.outputs.vNetId
  }
}

/*
 * Deploy Security resources
 */

// Create the security resource group
resource securityRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  #disable-next-line BCP334
  name: take(replace(rgNamingStructure, '{subWorkloadName}', 'security'), 64)
  location: location
  tags: actualTags
}

module keyVaultNameModule '../module-library/createValidAzResourceName.bicep' = {
  scope: securityRg
  name: take(replace(deploymentNameStructure, '{rtype}', 'kvname'), 64)
  params: {
    environment: environment
    location: location
    namingConvention: namingConvention
    resourceType: 'kv'
    sequence: sequence
    workloadName: workloadName
  }
}

module keyVaultModule '../shared-modules/security/keyVault.bicep' = {
  scope: securityRg
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv'), 64)
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    keyVaultName: keyVaultNameModule.outputs.shortName
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'kv')
    tags: actualTags
    useCMK: useCMK
  }
}

module uamiModule '../shared-modules/security/uami.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami'), 64)
  scope: securityRg
  params: {
    tags: actualTags
    uamiName: replace(resourceNamingStructureNoSub, '{rtype}', 'uami')
    location: location
  }
}

module uamiKvRbacModule '../module-library/roleAssignments/roleAssignment-kv.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami-kv-rbac'), 64)
  scope: securityRg
  params: {
    kvName: keyVaultModule.outputs.keyVaultName
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: rolesModule.outputs.roles.KeyVaultCryptoServiceEncryptionUser
  }
}

// Create encryption keys in the Key Vault for data factory, storage accounts, disks, and recovery services vault
module encryptionKeysModule '../shared-modules/security/encryptionKeys.bicep' =
  if (useCMK) {
    name: take(replace(deploymentNameStructure, '{rtype}', 'keys'), 64)
    scope: securityRg
    params: {
      keyVaultName: keyVaultModule.outputs.keyVaultName
      keyExpirySeed: encryptionKeyExpirySeed
      debugMode: debugMode
    }
  }

var kvEncryptionKeys = reduce(encryptionKeysModule.outputs.keys, {}, (cur, next) => union(cur, next))

var deployingVMs = (!researchVmsAreSessionHosts && jumpBoxSessionHostCount > 0) || isAirlockReviewCentralized

// Create a Disk Encryption Set if we're deploying any VMs and we need to use CMK
module diskEncryptionSetModule '../shared-modules/security/diskEncryptionSet.bicep' =
  if (deployingVMs && useCMK) {
    name: take(replace(deploymentNameStructure, '{rtype}', 'des'), 64)
    scope: securityRg
    params: {
      location: location
      deploymentNameStructure: deploymentNameStructure
      tags: actualTags

      keyVaultId: keyVaultModule.outputs.id
      uamiId: uamiModule.outputs.id
      // TODO: Validate WithVersion is needed
      keyUrl: kvEncryptionKeys.diskEncryptionSet.keyUriWithVersion
      name: replace(resourceNamingStructureNoSub, '{rtype}', 'des')
      kvRoleDefinitionId: rolesModule.outputs.roles.KeyVaultCryptoServiceEncryptionUser
    }
  }

/*
 * Deploy Azure Virtual Desktop
 */

// Modify the AVD route table to route traffic through the Azure Firewall
module avdRouteTableModule '../shared-modules/networking/rt.bicep' =
  if (!researchVmsAreSessionHosts) {
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

resource avdRg 'Microsoft.Resources/resourceGroups@2022-09-01' =
  if (!researchVmsAreSessionHosts) {
    #disable-next-line BCP334
    name: take(replace(rgNamingStructure, '{subWorkloadName}', 'avd'), 64)
    location: location
    tags: actualTags
  }

// Deploy Azure Virtual Desktop resources if AVD is used as jump hosts into the spokes
module avdJumpBoxModule '../shared-modules/virtualDesktop/main.bicep' =
  if (!researchVmsAreSessionHosts) {
    scope: avdRg
    name: take(replace(deploymentNameStructure, '{rtype}', 'avd'), 64)
    params: {
      location: location
      deploymentNameStructure: deploymentNameStructure
      logonType: logonType
      namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'avd')
      privateEndpointSubnetId: networkModule.outputs.createdSubnets.DataSubnet.id
      privateLinkDnsZoneId: resourceId(
        subscription().subscriptionId,
        networkRg.name,
        'Microsoft.Network/privateDnsZones',
        'privatelink.wvd.microsoft.com'
      )
      roles: rolesModule.outputs.roles
      tags: actualTags

      adminObjectId: systemAdminObjectId

      workspaceFriendlyName: 'Secure Research Access (${workloadName}-${sequenceFormatted})'
      desktopAppGroupFriendlyName: ''
      deployDesktopAppGroup: false

      remoteAppApplicationGroupInfo: [remoteDesktopAppGroupInfo]
    }
  }

module avdJumpBoxSessionHostModule '../shared-modules/virtualDesktop/sessionHosts.bicep' =
  if (!researchVmsAreSessionHosts && jumpBoxSessionHostCount > 0) {
    scope: avdRg
    name: take(replace(deploymentNameStructure, '{rtype}', 'avd-sh'), 64)
    params: {
      location: location
      deploymentNameStructure: deploymentNameStructure
      tags: actualTags

      diskEncryptionSetId: diskEncryptionSetModule.outputs.id

      // TODO: Specify if required to backup
      backupPolicyName: ''
      recoveryServicesVaultId: ''

      hostPoolName: avdJumpBoxModule.outputs.hostPoolName
      hostPoolToken: avdJumpBoxModule.outputs.hostPoolRegistrationToken
      logonType: logonType
      namingStructure: resourceNamingStructure
      subnetId: networkModule.outputs.createdSubnets.AvdSubnet.id
      vmCount: jumpBoxSessionHostCount
      vmLocalAdminUsername: sessionHostLocalAdminUsername
      vmLocalAdminPassword: sessionHostLocalAdminPassword
      vmNamePrefix: 'sh-${workloadName}${sequence}'
      vmSize: jumpBoxSessionHostVmSize

      ADDomainInfo: logonType == 'ad'
        ? {
            domainJoinPassword: domainJoinPassword
            domainJoinUsername: domainJoinUsername
            adDomainFqdn: adDomainFqdn
            adOuPath: adOuPath
          }
        : null
    }
  }

module rolesModule '../module-library/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}

output hubFirewallIp string = azureFirewallModule.outputs.fwPrIp
output hubVnetResourceId string = networkModule.outputs.vNetId
output hubPrivateDnsZonesResourceGroupId string = networkRg.id
// TODO: Output the resource ID of the remote application group for the remote desktop application
// To be used in the spoke for setting permissions
//output remoteDesktopAppGroupResourceId string = virtualDesktopModule.outputs.remoteDesktopAppGroupResourceId
