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

@description('Any additional subnets for the hub virtual network. Specify the properties using ARM syntax/naming.')
param additionalSubnets array = []

@description('Custom IP addresses to be used for the virtual network.')
param customDnsIPs array = []

@description('The Azure resource ID of the virtual network that is considered the main hub. Required when using Active Directory authentication to reach domain controllers.')
param mainHubVNetId string = ''

@description('If true, peering to the main hub will enable using the main hub\'s virtual network gateway for hybrid networking.')
param useMainHubGateway bool = true

@description('The Azure resource ID of the resource group where existing Private Link DNS zones are located. All required Private DNS Zones must already exist.')
param existingPrivateDnsZonesResourceGroupId string = ''

// Support for forced tunneling, including adding entries to route tables for routing to the main hub's address space via Az FW
@description('The IP address of the main hub\'s network virtual appliance (NVA).')
param mainHubNvaIp string = ''

@description('The pool of IP address space for the entire research environment, including this hub and all its spokes.')
param ipAddressPool array

@description('The IP addresses of the domain controllers in the Active Directory domain. Required if using AD join.')
param domainControllerIPAddresses array = []

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
param enableAvmTelemetry bool = true

param debugMode bool = false
// param debugRemoteIp string = ''
// param debugPrincipalId string = ''

//------------------------------- END PARAMETERS -------------------------------

//-------------------------------- START TYPES ---------------------------------

import { remoteAppApplicationGroup } from '../shared-modules/virtualDesktop/avd.bicep'

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
var deploymentNameStructure = '${workloadName}-${sequenceFormatted}-{rtype}-${deploymentTime}'

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

// Create the network resource group
resource networkRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  #disable-next-line BCP334
  name: take(replace(rgNamingStructure, '{subWorkloadName}', 'networking'), 64)
  location: location
  tags: actualTags
}

module networkModule 'hub-modules/networking/main.bicep' = {
  scope: networkRg
  name: take(replace(deploymentNameStructure, '{rtype}', 'networking'), 64)
  params: {
    deployAvdSubnet: !researchVmsAreSessionHosts
    deployAirlockSubnet: isAirlockReviewCentralized
    deployBastion: deployBastion
    deployVpn: deployVpn

    deploymentNameStructure: deploymentNameStructure
    deploymentTime: deploymentTime
    additionalSubnets: additionalSubnets
    location: location
    networkAddressSpace: networkAddressSpace
    tags: actualTags
    resourceNamingStructure: resourceNamingStructureNoSub
    customDnsIPs: customDnsIPs

    peeringRemoteVNetId: mainHubVNetId
    remoteVNetFriendlyName: 'MainHub'

    useRemoteGateway: useMainHubGateway

    privateDnsZonesResourceGroupId: existingPrivateDnsZonesResourceGroupId

    firewallForcedTunnel: !empty(mainHubNvaIp)
    firewallForcedTunnelNvaIP: mainHubNvaIp

    deployManagementSubnet: logonType == 'ad'

    includeActiveDirectoryFirewallRules: logonType == 'ad'
    domainControllerIPAddresses: domainControllerIPAddresses

    includeDnsFirewallRules: length(customDnsIPs) > 0
    ipAddressPool: ipAddressPool
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
    keyVaultName: keyVaultNameModule.outputs.validName
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
    principalType: 'ServicePrincipal'
  }
}

// Create encryption keys in the Key Vault for data factory, storage accounts, disks, and recovery services vault
module encryptionKeysModule '../shared-modules/security/encryptionKeys.bicep' = if (useCMK) {
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
module diskEncryptionSetModule '../shared-modules/security/diskEncryptionSet.bicep' = if (deployingVMs && useCMK) {
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

// If needed, create the AVD resource group
resource avdRg 'Microsoft.Resources/resourceGroups@2022-09-01' = if (!researchVmsAreSessionHosts) {
  #disable-next-line BCP334
  name: take(replace(rgNamingStructure, '{subWorkloadName}', 'avd'), 64)
  location: location
  tags: actualTags
}

// Create variables to reference the private link DNS zone for WVD
var privateLinkSubscriptionId = !empty(existingPrivateDnsZonesResourceGroupId)
  ? split(existingPrivateDnsZonesResourceGroupId, '/')[2]
  : subscription().subscriptionId
var privateLinkResourceGroupName = !empty(existingPrivateDnsZonesResourceGroupId)
  ? split(existingPrivateDnsZonesResourceGroupId, '/')[4]
  : networkRg.name
var wvdPrivateLinkDnsZoneName = 'privatelink.wvd.microsoft.com'
var wvdPrivateLinkDnsZoneId = resourceId(
  privateLinkSubscriptionId,
  privateLinkResourceGroupName,
  'Microsoft.Network/privateDnsZones',
  wvdPrivateLinkDnsZoneName
)

// Deploy Azure Virtual Desktop resources if AVD is used as jump hosts into the spokes
module avdJumpBoxModule '../shared-modules/virtualDesktop/avd.bicep' = if (!researchVmsAreSessionHosts) {
  scope: avdRg
  name: take(replace(deploymentNameStructure, '{rtype}', 'avd'), 64)
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    logonType: logonType
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'avd')
    privateEndpointSubnetId: networkModule.outputs.createdSubnets.DataSubnet.id
    privateLinkDnsZoneId: wvdPrivateLinkDnsZoneId
    roles: rolesModule.outputs.roles
    tags: actualTags

    adminObjectId: systemAdminObjectId

    workspaceFriendlyName: 'Secure Research Access (${workloadName}-${sequenceFormatted})'
    desktopAppGroupFriendlyName: ''
    deployDesktopAppGroup: false

    remoteAppApplicationGroupInfo: [remoteDesktopAppGroupInfo]
    usePrivateLinkForHostPool: usePrivateEndpoints
  }
}

module avdJumpBoxSessionHostModule '../shared-modules/virtualDesktop/sessionHosts.bicep' = if (!researchVmsAreSessionHosts && jumpBoxSessionHostCount > 0) {
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
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'avd')
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

    // Use a multi-session non-M365 apps default image for the jump box
    // All we need is mstsc.exe and the M365 images will pop up Teams notifications
    imageReference: {
      publisher: 'MicrosoftWindowsDesktop'
      offer: 'Windows-11'
      sku: 'win11-23h2-avd'
      version: 'latest'
    }
  }
}

resource imagingRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  #disable-next-line BCP334
  name: take(replace(rgNamingStructure, '{subWorkloadName}', 'imaging'), 64)
  location: location
  tags: actualTags
}

// Default image that will be used to create an Image Template
var sampleImageTemplateImageReference = {
  publisher: 'microsoftwindowsdesktop'
  offer: 'Windows-11'
  sku: 'win11-23h2-ent'
  version: 'latest'
}

module imagingModule 'hub-modules/imaging/main.bicep' = {
  scope: imagingRg
  name: take(replace(deploymentNameStructure, '{rtype}', 'imaging'), 64)
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    environment: environment
    namingConvention: namingConvention
    sequence: sequence
    tags: actualTags
    workloadName: workloadName
    enableAvmTelemetry: enableAvmTelemetry
    imageReference: sampleImageTemplateImageReference
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'imaging')
  }
}

// Deploy a management VM, for example, to domain join the storage accounts in the spokes to AD
resource managementRg 'Microsoft.Resources/resourceGroups@2022-09-01' = if (logonType == 'ad') {
  #disable-next-line BCP334
  name: take(replace(rgNamingStructure, '{subWorkloadName}', 'management'), 64)
  location: location
  tags: actualTags
}

module managementVmModule './hub-modules/management-vm/main.bicep' = if (logonType == 'ad') {
  name: take(replace(deploymentNameStructure, '{rtype}', 'vm-mgmt'), 64)
  scope: managementRg
  params: {
    location: location
    tags: actualTags
    namingStructure: replace(resourceNamingStructure, '{subWorkloadName}', 'mgmtvm')
    subnetId: networkModule.outputs.createdSubnets.ManagementSubnet.id

    vmLocalAdminUsername: sessionHostLocalAdminUsername
    vmLocalAdminPassword: sessionHostLocalAdminPassword

    // LATER: Adjust number of characters taken from the workloadName based on the length of the string value of the sequence number
    // LATER: Allow customization of the prefix mgmt-
    vmNamePrefix: 'mgmt-${take(workloadName,8)}${take(string(sequence),2)}'

    domainJoinInfo: logonType == 'ad'
      ? {
          adDomainFqdn: adDomainFqdn
          domainJoinPassword: domainJoinPassword
          domainJoinUsername: domainJoinUsername
          adOuPath: adOuPath
        }
      : null

    logonType: logonType
  }
}

module rolesModule '../module-library/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}

output hubFirewallIp string = networkModule.outputs.fwPrivateIPAddress
output hubVnetResourceId string = networkModule.outputs.vNetId
output hubPrivateDnsZonesResourceGroupId string = empty(existingPrivateDnsZonesResourceGroupId)
  ? networkRg.id
  : existingPrivateDnsZonesResourceGroupId

output managementVmId string = managementVmModule.outputs.vmId
output managementVmUamiPrincipalId string = managementVmModule.outputs.uamiPrincipalId
output managementVmUamiClientId string = managementVmModule.outputs.uamiClientId

// TODO: Output the resource ID of the remote application group for the remote desktop application
// To be used in the spoke for setting permissions
//output remoteDesktopAppGroupResourceId string = virtualDesktopModule.outputs.remoteDesktopAppGroupResourceId
