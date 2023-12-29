targetScope = 'subscription'

@description('The Azure region where the spoke will be deployed.')
@allowed([
  'usgovvirginia'
  'eastus'
])
param location string
@description('The name of the research project for the spoke.')
param workloadName string

// Optional parameters
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
@description('Tags to apply to each deployed Azure resource.')
param tags object = {}
@description('The deployment sequence. Each new sequence number will create a new deployment.')
param sequence int = 1
@description('The naming convention to use for Azure resource names. Can contain placeholders for {rtype}, {workloadName}, {location}, {env}, and {seq}')
param namingConvention string = '{workloadName}-{subWorkloadName}-{env}-{rtype}-{loc}-{seq}'

param deploymentTime string = utcNow()
@description('The date and time seed for the expiration of the encryption keys.')
param encryptionKeyExpirySeed string = utcNow()

// Network parameters
@description('Format: [ "192.168.0.0/24", "192.168.10.0/24" ]')
@minLength(1)
param networkAddressSpaces array
@description('The private IP address of the hub firewall.')
param hubFirewallIp string
@description('The DNS IP addresses to use for the virtual network. Defaults to the hub firewall IP.')
param hubDnsIps array = [ hubFirewallIp ]
@description('The Azure resource ID of the hub virtual network to peer with.')
param hubVNetResourceId string
@description('The resource ID of the resource group in the hub subscription where storage account-related private DNS zones live.')
param hubPrivateDnsZonesResourceGroupId string
@description('The definition of additional subnets that have been manually created.')
param additionalSubnets array = []

// AVD parameters
@description('AAD object ID of the user or group (researchers) to assign permissions to access the AVD application groups and storage.')
param researcherAadObjectId string
@description('Name of the Desktop application group shown to users in the AVD client.')
param desktopAppGroupFriendlyName string
@description('Name of the Workspace shown to users in the AVD client.')
param workspaceFriendlyName string
// @description('The list of remote application groups and applications in each group to create. See sample parameters file for the syntax.')
// param remoteAppApplicationGroupInfo array

// TODO: Add support for custom images
// @description('The Azure resource ID of the standalone image to use for new session hosts. If blank, will use the Windows 11 23H2 O365 Gen 2 Marketplace image.')
// param sessionHostVmImageResourceId string = ''

@secure()
param sessionHostLocalAdminUsername string
@secure()
param sessionHostLocalAdminPassword string
@description('Specifies if logons to virtual machines should use AD or Entra ID.')
@allowed([
  'ad'
  'entraID'
])
param logonType string
@secure()
@description('The username of a domain user or service account to use to join the Active Directory domain. Required if using AD join.')
param domainJoinUsername string = ''
@secure()
@description('The password of the domain user or service account to use to join the Active Directory domain. Required if using AD join.')
param domainJoinPassword string = ''

@description('The fully qualified DNS name of the Active Directory domain to join. Required if using AD join.')
param adDomainFqdn string = ''
@description('Optional. The OU path in LDAP notation to use when joining the session hosts.')
param adOuPath string = ''
@description('Optional. The number of Azure Virtual Desktop session hosts to create in the pool. Defaults to 1.')
param sessionHostCount int = 1
@description('The prefix used for the computer names of the session host(s). Maximum 11 characters.')
@maxLength(11)
param sessionHostNamePrefix string
@description('A valid Azure Virtual Machine size. Use `az vm list-sizes --location "<region>"` to retrieve a list for the selected location')
param sessionHostSize string
@description('If true, will configure the deployment of AVD to make the AVD session hosts usable as research VMs. This will give full desktop access, flow the AVD traffic through the firewall, etc.')
param useSessionHostAsResearchVm bool = true

// @description('If true, airlock reviews will take place centralized in the hub. If true, the hub* parameters must be specified also.')
// param isAirlockCentralized bool = false
// @description('The email address of the reviewer for this project.')
// param airlockApproverEmail string

// HUB AIRLOCK NAMES
// @description('The full Azure resource ID of the hub\'s airlock storage account.')
// param hubAirlockStorageAccountId string
// @description('The file share name for airlock reviews.')
// param hubAirlockFileShareName string
// @description('The name of the Key Vault in the research hub containing the airlock storage account\'s connection string as a secret.')
// param hubKeyVaultId string

// @description('The list of allowed IP addresses or ranges for ingest and approved export pickup purposes.')
// param publicStorageAccountAllowedIPs array = []

@description('The Azure built-in regulatory compliance framework to target. This will affect whether or not customer-managed keys, private endpoints, etc. are used. This will *not* deploy a policy assignment.')
@allowed([
  'NIST80053R5'
  'HIPAAHITRUST'
  'CMMC2L2'
  'NIST800171R2'
])
// Default to the strictest supported compliance framework
param complianceTarget string = 'NIST80053R5'

param debugMode bool = false
param debugRemoteIp string = ''
param debugPrincipalId string = ''

// Variables
var sequenceFormatted = format('{0:00}', sequence)
// TODO: Use like hub
var defaultTags = {
  ID: '${workloadName}_${sequence}'
}

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
var usePrivateEndpoints = complianceFeatureMap[complianceTarget].usePrivateEndpoints
// Use customer-managed keys when targeting NIST 800-53 R5
var useCMK = complianceFeatureMap[complianceTarget].useCMK

var actualTags = union(defaultTags, tags)

var deploymentNameStructure = '${workloadName}-{rtype}-${deploymentTime}'
// Naming structure only needs the resource type ({rtype}) and sub-workload name ({subWorkloadName}) replaced
var namingStructure = replace(replace(replace(replace(namingConvention, '{loc}', location), '{seq}', sequenceFormatted), '{workloadName}', workloadName), '{env}', environment)
// Naming structure for components that don't consider subWorkloadName
var namingStructureNoSub = replace(namingStructure, '-{subWorkloadName}', '')
// The naming structure of Resource Groups
var rgNamingStructure = replace(replace(namingStructure, '{rtype}', 'rg-{rgname}'), '-{subWorkloadName}', '')

//var hubAirlockSubscriptionId = split(hubAirlockStorageAccountId, '/')[2]

// TODO: Additional container names required if local airlock (not centralized)
var containerNames = {
  exportRequest: 'export-request'
}

// Load RBAC roles
module rolesModule '../module-library/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}

// Create the resource groups
resource securityRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgname}', 'security')
  location: location
  tags: actualTags
}

resource avdRg 'Microsoft.Resources/resourceGroups@2023-07-01' = if (useSessionHostAsResearchVm) {
  name: replace(rgNamingStructure, '{rgname}', 'avd')
  location: location
  tags: actualTags
}

resource storageRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgname}', 'storage')
  location: location
  tags: actualTags
}

resource networkRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgname}', 'network')
  location: location
  tags: actualTags
}

resource backupRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgname}', 'backup')
  location: location
  tags: actualTags
}

// Create a resource group for additional compute resources (like shared VMs)
resource computeRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgname}', 'compute')
  location: location
  tags: actualTags
}

// Define networking resources: user-defined routes and NSGs
// TODO: Route to hub should go via FW (override default peering)
var defaultRoutes = json(replace(loadTextContent('./routes/defaultRouteTable.json'), '{{fwIp}}', hubFirewallIp))

var subnets = {
  ComputeSubnet: {
    addressPrefix: cidrSubnet(networkAddressSpaces[0], 25, 0) // '${replace(networkAddressSpaces[0], '{octet4}', '128')}/25'
    // TODO: When not using research VMs as session hosts, allow RDP and SSH from hub
    securityRules: []
    routes: defaultRoutes
  }
  PrivateEndpointSubnet: {
    addressPrefix: cidrSubnet(networkAddressSpaces[0], 26, 2) // '${replace(networkAddressSpaces[0], '{octet4}', '64')}/26'
    securityRules: []
    routes: defaultRoutes
  }
}

// Create networking resources
module networkModule '../shared-modules/networking/main.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'network'), 64)
  scope: networkRg
  params: {
    location: location
    namingStructure: namingStructureNoSub
    deploymentNameStructure: deploymentNameStructure
    subnetDefs: subnets
    additionalSubnets: additionalSubnets
    tags: actualTags
    vnetAddressPrefixes: networkAddressSpaces
    customDnsIPs: hubDnsIps
    // Peer with the research hub if specified
    remoteVNetResourceId: hubVNetResourceId

    vnetFriendlyName: 'hub'
    remoteVNetFriendlyName: 'spoke-${workloadName}-${sequenceFormatted}'
  }
}

// Enable Defender for Cloud and Workload Protection Plans
module defenderPlansModule './spoke-modules/security/defenderPlans.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'defenderplans'), 64)
}

module keyVaultNameModule '../module-library/createValidAzResourceName.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-name'), 64)
  scope: securityRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'kv'
    sequence: sequence
    workloadName: workloadName
  }
}

// Create a Key Vault for the customer-managed keys and more
module keyVaultModule './spoke-modules/security/keyVault.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv'), 64)
  scope: securityRg
  params: {
    location: location
    keyVaultName: keyVaultNameModule.outputs.shortName
    namingStructure: namingStructureNoSub
    // Only allow remote IP addresses in debug mode
    allowedIps: debugMode ? [
      debugRemoteIp
    ] : []
    keyVaultAdmins: debugMode ? [ debugPrincipalId ] : []
    roles: rolesModule.outputs.roles
    deploymentNameStructure: deploymentNameStructure
    tags: actualTags
  }
}

// Create encryption keys in the Key Vault for data factory, storage accounts, disks, and recovery services vault
module encryptionKeysModule './spoke-modules/security/encryptionKeys.bicep' = if (useCMK) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'keys'), 64)
  scope: securityRg
  params: {
    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyExpirySeed: encryptionKeyExpirySeed
    debugMode: debugMode
  }
}

var kvEncryptionKeys = reduce(encryptionKeysModule.outputs.keys, {}, (cur, next) => union(cur, next))

module uamiModule './spoke-modules/security/uami.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami'), 64)
  scope: securityRg
  params: {
    tags: actualTags
    uamiName: replace(namingStructureNoSub, '{rtype}', 'uami')
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

// Create the disk encryption set with system-assigned MI and grant access to Key Vault
module diskEncryptionSetModule './spoke-modules/security/diskEncryptionSet.bicep' = if (useCMK) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'des'), 64)
  scope: securityRg
  params: {
    keyVaultId: keyVaultModule.outputs.id
    keyUrl: kvEncryptionKeys.diskEncryptionSet.keyUriWithVersion
    uamiId: uamiModule.outputs.id
    location: location
    name: replace(namingStructureNoSub, '{rtype}', 'des')
    tags: actualTags
    deploymentNameStructure: deploymentNameStructure
    kvRoleDefinitionId: rolesModule.outputs.roles.KeyVaultCryptoServiceEncryptionUser
  }
  dependsOn: [ uamiKvRbacModule ]
}

var fileShareNames = {
  userProfiles: 'userprofiles'
  shared: 'shared'
}

// Deploy the project's private storage account
module storageModule './spoke-modules/storage/main.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'storage'), 64)
  scope: storageRg
  params: {
    tags: union(actualTags, { 'hidden-title': 'Private Storage Account' })
    location: location
    deploymentNameStructure: deploymentNameStructure

    privateDnsZonesResourceGroupId: hubPrivateDnsZonesResourceGroupId

    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyVaultResourceGroupName: keyVaultModule.outputs.resourceGroupName
    keyVaultSubscriptionId: keyVaultModule.outputs.subscriptionId

    // LATER: Reconsider hardcoding the encryption key name
    storageAccountEncryptionKeyName: 'storage'
    namingConvention: namingConvention
    namingStructure: namingStructureNoSub
    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpointSubnet.id
    sequence: sequence
    uamiId: uamiModule.outputs.id
    workloadName: workloadName
    debugMode: debugMode
    debugRemoteIp: debugRemoteIp
    containerNames: [
      containerNames.exportRequest
    ]
    fileShareNames: [
      fileShareNames.shared
      fileShareNames.userProfiles
    ]
  }
}

// Set blob and SMB permissions for group on private storage
module privateStContainerRbacModule '../module-library/roleAssignments/roleAssignment-st-container.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-priv-ct-rbac'), 64)
  scope: storageRg
  params: {
    containerName: containerNames.exportRequest
    principalId: researcherAadObjectId
    roleDefinitionId: rolesModule.outputs.roles['Storage Blob Data Contributor']
    storageAccountName: storageModule.outputs.storageAccountName
  }
}

module privateStFileShareRbacModule '../module-library/roleAssignments/roleAssignment-st-fileShare.bicep' = [for shareName in items(fileShareNames): {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-priv-fs-${shareName.key}-rbac'), 64)
  scope: storageRg
  params: {
    fileShareName: shareName.value
    principalId: researcherAadObjectId
    roleDefinitionId: rolesModule.outputs.roles['Storage File Data SMB Share Contributor']
    storageAccountName: storageModule.outputs.storageAccountName
  }
}]

module avdModule './spoke-modules/virtualDesktop/main.bicep' = if (useSessionHostAsResearchVm) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'avd'), 64)
  scope: avdRg
  params: {
    location: location
    tags: actualTags
    namingStructure: replace(namingStructure, '{subWorkloadName}', 'avd')
    deploymentNameStructure: deploymentNameStructure

    desktopAppGroupFriendlyName: desktopAppGroupFriendlyName
    workspaceFriendlyName: workspaceFriendlyName
    //remoteAppApplicationGroupInfo: remoteAppApplicationGroupInfo

    dvuRoleDefinitionId: rolesModule.outputs.roles.DesktopVirtualizationUser
    objectId: researcherAadObjectId

    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpointSubnet.id
    privateLinkDnsZoneId: avdConnectionPrivateDnsZone.id
    usePrivateLinkForHostPool: usePrivateEndpoints
  }
}

var useADDomainInformation = (logonType == 'ad')

module sessionHostModule './spoke-modules/virtualDesktop/sessionHosts.bicep' = if (useSessionHostAsResearchVm) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'avd-sh'), 64)
  scope: avdRg
  params: {
    namingStructure: namingStructureNoSub
    subnetId: networkModule.outputs.createdSubnets.computeSubnet.id
    tags: actualTags
    location: location
    diskEncryptionSetId: diskEncryptionSetModule.outputs.id

    hostPoolName: avdModule.outputs.hostPoolName
    hostPoolToken: avdModule.outputs.hostPoolRegistrationToken

    vmLocalAdminPassword: sessionHostLocalAdminPassword
    vmLocalAdminUsername: sessionHostLocalAdminUsername
    //vmImageResourceId: sessionHostVmImageResourceId
    vmCount: sessionHostCount
    vmNamePrefix: sessionHostNamePrefix
    vmSize: sessionHostSize

    logonType: logonType
    ADDomainInfo: useADDomainInformation ? {
      domainJoinPassword: domainJoinPassword
      domainJoinUsername: domainJoinUsername
      adDomainFqdn: adDomainFqdn
      adOuPath: adOuPath
    } : null
  }
}

module publicStorageAccountNameModule '../module-library/createValidAzResourceName.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'pubsaname'), 64)
  scope: storageRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'st'
    sequence: sequence
    workloadName: workloadName
    subWorkloadName: 'pub'
  }
}

// Store the file share connection string of the private storage account in Key Vault
module privateStorageConnStringSecretModule './spoke-modules/security/keyVault-StorageAccountConnString.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-secret'), 64)
  scope: subscription()
  params: {
    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyVaultResourceGroupName: securityRg.name
    storageAccountName: storageModule.outputs.storageAccountName
    storageAccountResourceGroupName: storageRg.name
  }
}

// module airlockModule './spoke-modules/airlock/main.bicep' = {
//   name: take(replace(deploymentNameStructure, '{rtype}', 'airlock'), 64)
//   scope: storageRg
//   params: {
//     location: location

//     useCentralizedReview: isAirlockCentralized
//     // Airlock resources in the hub
//     // airlockFileShareName: hubAirlockFileShareName
//     // airlockResourceGroupName: hubAirlockResourceGroupName
//     // airlockStorageAccountId: hubAirlockStorageAccountId
//     // airlockStorageAccountName: hubAirlockStorageAccountName

//     approverEmail: airlockApproverEmail
//     deploymentNameStructure: deploymentNameStructure
//     encryptionKeyVaultUri: keyVaultModule.outputs.uri
//     encryptionUamiId: uamiModule.outputs.id
//     //hubKeyVaultName: hubKeyVaultName
//     // hubKeyVaultResourceGroupName: hubKeyVaultResourceGroupName
//     // hubAirlockSubscriptionId: hubAirlockSubscriptionId
//     keyVaultName: keyVaultModule.outputs.keyVaultName
//     keyVaultResourceGroupName: securityRg.name
//     namingStructure: namingStructure
//     privateStorageAccountConnStringSecretName: privateStorageConnStringSecretModule.outputs.secretName
//     publicStorageAccountName: publicStorageAccountNameModule.outputs.shortName
//     roles: rolesModule.outputs.roles
//     spokePrivateStorageAccountName: storageModule.outputs.storageAccountName
//     workspaceName: '${workloadName}${sequenceFormatted}'

//     // TODO: Do not hardcode encryption key names
//     storageAccountEncryptionKeyName: 'storage'
//     adfEncryptionKeyName: 'adf'

//     researcherAadObjectId: researcherAadObjectId

//     publicStorageAccountAllowedIPs: publicStorageAccountAllowedIPs
//   }
// }

// Create a Recovery Services Vault
module recoveryServicesVaultModule './spoke-modules/recovery/recoveryServicesVault.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rsv'), 64)
  scope: backupRg
  params: {
    location: location
    tags: actualTags
    encryptionKeyUri: kvEncryptionKeys.rsv.keyUri
    namingConvention: namingStructureNoSub
    userAssignedIdentityId: uamiModule.outputs.id
    workloadName: workloadName
  }
}

/*
 * HUB REFERENCES
 */

var hubDnsZoneSubscriptionId = split(hubPrivateDnsZonesResourceGroupId, '/')[2]
var hubDnsZoneResourceGroupName = split(hubPrivateDnsZonesResourceGroupId, '/')[4]
var hubDnsZoneResourceGroup = resourceGroup(hubDnsZoneSubscriptionId, hubDnsZoneResourceGroupName)

resource avdConnectionPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.wvd.microsoft.com'
  scope: hubDnsZoneResourceGroup
}
