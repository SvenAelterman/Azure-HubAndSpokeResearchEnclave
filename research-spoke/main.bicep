targetScope = 'subscription'

//------------------------------ START PARAMETERS ------------------------------

@description('The Azure region where the spoke will be deployed.')
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
@description('The naming convention to use for Azure resource names. Can contain placeholders for {rtype}, {workloadName}, {location}, {env}, and {seq}. The only supported segment separator is \'-\'.')
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
param customDnsIps array = [hubFirewallIp]
@description('The Azure resource ID of the hub virtual network to peer with.')
param hubVNetResourceId string
@description('The resource ID of the resource group in the hub subscription where storage account-related private DNS zones live.')
param hubPrivateDnsZonesResourceGroupId string
@description('The definition of additional subnets that have been manually created.')
param additionalSubnets array = []
// TODO: Add parameter for custom private DNS zone for VM registration, if customDnsIps is empty

// AVD parameters
@description('Name of the Desktop application group shown to users in the AVD client.')
param desktopAppGroupFriendlyName string = 'N/A'
@description('Name of the Workspace shown to users in the AVD client.')
param workspaceFriendlyName string = 'N/A'
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
@allowed(['ad', 'entraID'])
param logonType string
@description('The username of a domain user or service account to use to join the Active Directory domain. Use UPN notation. Required if using AD join.')
@secure()
param domainJoinUsername string = ''
@description('The password of the domain user or service account to use to join the Active Directory domain. Required if using AD join.')
@secure()
param domainJoinPassword string = ''

@allowed(['AADKERB', 'AADDS', 'None'])
param filesIdentityType string

@description('The fully qualified DNS name of the Active Directory domain to join. Required if using AD join.')
param adDomainFqdn string = ''
@description('Optional. The OU path in LDAP notation to use when joining the session hosts.')
param adOuPath string = ''
@description('Optional. The OU Path in LDAP notation to use when joining the storage account. Defaults to the same OU as the session hosts.')
param storageAccountOuPath string = adOuPath
@description('Optional. The number of Azure Virtual Desktop session hosts to create in the pool. Defaults to 1.')
param sessionHostCount int = 1
@description('The prefix used for the computer names of the session host(s). Maximum 11 characters.')
@maxLength(11)
param sessionHostNamePrefix string = 'N/A'
@description('A valid Azure Virtual Machine size. Use `az vm list-sizes --location "<region>"` to retrieve a list for the selected location')
param sessionHostSize string = 'N/A'
@description('If true, will configure the deployment of AVD to make the AVD session hosts usable as research VMs. This will give full desktop access, flow the AVD traffic through the firewall, etc.')
param useSessionHostAsResearchVm bool = true
@description('Entra ID object ID of the user or group (researchers) to assign permissions to access the AVD application groups and storage.')
param researcherEntraIdObjectId string
@description('Entra ID object ID of the admin user or group to assign permissions to administer the AVD session hosts, storage, etc.')
param adminEntraIdObjectId string

// Airlock parameters
@description('If true, airlock reviews will take place centralized in the hub. If true, the hub* parameters must be specified also.')
param isAirlockReviewCentralized bool = false
@description('The email address of the reviewer for this project.')
param airlockApproverEmail string

// HUB AIRLOCK NAMES
@description('The full Azure resource ID of the hub\'s airlock review storage account.')
param centralAirlockStorageAccountId string
@description('The file share name for airlock reviews.')
param centralAirlockFileShareName string
@description('The name of the Key Vault in the research hub containing the airlock review storage account\'s connection string as a secret.')
param centralAirlockKeyVaultId string

@description('The list of allowed IP addresses or ranges for ingest and approved export pickup purposes.')
param publicStorageAccountAllowedIPs array = []

@description('The Azure built-in regulatory compliance framework to target. This will affect whether or not customer-managed keys, private endpoints, etc. are used. This will *not* deploy a policy assignment.')
@allowed([
  'NIST80053R5'
  'HIPAAHITRUST'
  'CMMC2L2'
  'NIST800171R2'
])
// Default to the strictest supported compliance framework
param complianceTarget string = 'NIST80053R5'

param hubManagementVmId string = ''
param hubManagementVmUamiPrincipalId string = ''
param hubManagementVmUamiClientId string = ''

param debugMode bool = false
param debugRemoteIp string = ''
param debugPrincipalId string = ''

//----------------------------- END PARAMETERS -----------------------------

//----------------------------- START VARIABLES ----------------------------

var sequenceFormatted = format('{0:00}', sequence)
// TODO: Use like hub
var defaultTags = {
  ID: '${workloadName}_${sequence}'
}

var complianceFeatureMap = loadJsonContent('../shared-modules/compliance/complianceFeatureMap.jsonc')

// Use private endpoints when targeting NIST 800-53 R5 or CMMC 2.0 Level 2
var usePrivateEndpoints = bool(complianceFeatureMap[complianceTarget].usePrivateEndpoints)
// Use customer-managed keys when targeting NIST 800-53 R5
var useCMK = bool(complianceFeatureMap[complianceTarget].useCMK)

var actualTags = union(defaultTags, tags)

var deploymentNameStructure = '${workloadName}-${sequenceFormatted}-{rtype}-${deploymentTime}'
// Naming structure only needs the resource type ({rtype}) and sub-workload name ({subWorkloadName}) replaced
var namingStructure = replace(
  replace(
    replace(replace(namingConvention, '{loc}', location), '{seq}', sequenceFormatted),
    '{workloadName}',
    workloadName
  ),
  '{env}',
  environment
)
// Naming structure for components that don't consider subWorkloadName
var namingStructureNoSub = replace(namingStructure, '-{subWorkloadName}', '')
// The naming structure of Resource Groups
var rgNamingStructure = replace(replace(namingStructure, '{rtype}', 'rg-{rgname}'), '-{subWorkloadName}', '')

//var hubAirlockSubscriptionId = split(hubAirlockStorageAccountId, '/')[2]

var containerNames = {
  // Always created in private storage account
  exportRequest: 'export-request'
  // Always created in public storage account
  ingest: 'ingest'
  exportApproved: 'export-approved'
}

var fileShareNames = {
  // Always created in private storage account
  userProfiles: 'userprofiles'
  shared: 'shared'
  // Created in airlock review storage account if not centralized review
  exportReview: 'export-review'
}

//------------------------------ END VARIABLES ------------------------------

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
    addressPrefix: cidrSubnet(networkAddressSpaces[0], 26, 0)
    // TODO: When not using research VMs as session hosts, allow RDP and SSH from hub
    // TODO: Allow RDP and SSH from BastionSubnet in hub (if present)
    securityRules: []
    routes: defaultRoutes
  }
  PrivateEndpointSubnet: {
    addressPrefix: cidrSubnet(networkAddressSpaces[0], 26, 1)
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
    customDnsIPs: customDnsIps
    // Peer with the research hub if specified
    remoteVNetResourceId: hubVNetResourceId

    vnetFriendlyName: 'hub'
    remoteVNetFriendlyName: 'spoke-${workloadName}-${sequenceFormatted}'
  }
}

var allPrivateLinkDnsZoneNames = loadJsonContent('../shared-modules/dns/allPrivateDnsZones.jsonc')['${az.environment().name}']

// Link the Private Link DNS zones in the hub to this virtual network, if not using custom DNS IPs.
// If using custom DNS IPs, then the implication is that the custom DNS server knows how to resolve the private DNS zones.
// This could be simplified (perhaps) by using a Azure Private DNS Resolver service in the research hub if not using custom DNS.
module privateLinkDnsZoneLinkModule '../shared-modules/dns/privateDnsZoneVNetLink.bicep' = [
  for (zoneName, i) in allPrivateLinkDnsZoneNames: if (length(customDnsIps) == 0) {
    name: take(replace(deploymentNameStructure, '{rtype}', 'dns-link-${i}'), 64)
    scope: hubDnsZoneResourceGroup
    params: {
      registrationEnabled: false
      dnsZoneName: zoneName

      vnetId: networkModule.outputs.vNetId
    }
  }
]

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
module keyVaultModule '../shared-modules/security/keyVault.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'keyVault'), 64)
  scope: securityRg
  params: {
    location: location
    keyVaultName: keyVaultNameModule.outputs.validName
    namingStructure: namingStructureNoSub
    // Only allow remote IP addresses in debug mode
    allowedIps: debugMode
      ? [
          debugRemoteIp
        ]
      : []
    keyVaultAdmins: debugMode ? [debugPrincipalId] : []
    roles: rolesModule.outputs.roles
    deploymentNameStructure: deploymentNameStructure
    tags: actualTags
    debugMode: debugMode

    // This parameter is passed to allow determining if a resource lock needs to be created
    useCMK: useCMK
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

var kvEncryptionKeys = useCMK ? reduce(encryptionKeysModule.outputs.keys, {}, (cur, next) => union(cur, next)) : null

module uamiModule '../shared-modules/security/uami.bicep' = {
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
    principalType: 'ServicePrincipal'
  }
}

// Create the disk encryption set with system-assigned MI and grant access to Key Vault
module diskEncryptionSetModule '../shared-modules/security/diskEncryptionSet.bicep' = if (useCMK) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'diskEnc'), 64)
  scope: securityRg
  params: {
    keyVaultId: keyVaultModule.outputs.id
    // TODO: Validate WithVersion is needed
    keyUrl: kvEncryptionKeys.diskEncryptionSet.keyUriWithVersion
    uamiId: uamiModule.outputs.id
    location: location
    name: replace(namingStructureNoSub, '{rtype}', 'des')
    tags: actualTags
    deploymentNameStructure: deploymentNameStructure
    kvRoleDefinitionId: rolesModule.outputs.roles.KeyVaultCryptoServiceEncryptionUser
  }

  dependsOn: [uamiKvRbacModule]
}

// TODO: Split once into var and re-use var
var hubManagementVmSubscriptionId = split(hubManagementVmId, '/')[2]
var hubManagementVmResourceGroupName = split(hubManagementVmId, '/')[4]
var hubManagementVmName = split(hubManagementVmId, '/')[8]

// Deploy the project's private storage account
module storageModule './spoke-modules/storage/main.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'storage'), 64)
  scope: storageRg
  params: {
    tags: union(actualTags, { 'hidden-title': 'Private Storage Account' })
    location: location
    deploymentNameStructure: deploymentNameStructure

    privateEndpointSubnetId: networkModule.outputs.createdSubnets.privateEndpointSubnet.id
    privateDnsZonesResourceGroupId: hubPrivateDnsZonesResourceGroupId

    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyVaultResourceGroupName: keyVaultModule.outputs.resourceGroupName
    keyVaultSubscriptionId: keyVaultModule.outputs.subscriptionId

    // LATER: Reconsider hardcoding the encryption key name
    storageAccountEncryptionKeyName: 'storage'
    namingConvention: namingConvention
    namingStructure: namingStructureNoSub
    sequence: sequence
    uamiId: uamiModule.outputs.id
    workloadName: workloadName
    environment: environment

    debugMode: debugMode
    debugRemoteIp: debugRemoteIp

    containerNames: [
      containerNames.exportRequest
    ]
    fileShareNames: [
      fileShareNames.shared
      // TODO: Only when research VMs are session hosts
      fileShareNames.userProfiles
    ]

    // TODO: This needs additional refinement: specifying the AD domain info for AADKERB (guid, name)
    filesIdentityType: filesIdentityType
    domainJoin: logonType == 'ad'
    domainJoinInfo: storageAccountDomainJoinInfo

    hubSubscriptionId: hubManagementVmSubscriptionId
    hubManagementRgName: hubManagementVmResourceGroupName
    hubManagementVmName: hubManagementVmName
    uamiPrincipalId: hubManagementVmUamiPrincipalId
    uamiClientId: hubManagementVmUamiClientId
    roles: rolesModule.outputs.roles
  }
}

var storageAccountDomainJoinInfo = {
  adDomainFqdn: adDomainFqdn
  adOuPath: storageAccountOuPath
  domainJoinUsername: domainJoinUsername
  domainJoinPassword: domainJoinPassword
}

// Set blob and SMB permissions for group on private storage
module privateStContainerRbacModule '../module-library/roleAssignments/roleAssignment-st-container.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-priv-ct-rbac'), 64)
  scope: storageRg
  params: {
    containerName: containerNames.exportRequest
    principalId: researcherEntraIdObjectId
    roleDefinitionId: rolesModule.outputs.roles.StorageBlobDataContributor
    storageAccountName: storageModule.outputs.storageAccountName
    // Do not specify principalType here because we don't know if researcherEntraIdObjectId is a user or a group
  }
}

module privateStFileShareRbacModule '../module-library/roleAssignments/roleAssignment-st-fileShare.bicep' = [
  for shareName in items(fileShareNames): {
    name: take(replace(deploymentNameStructure, '{rtype}', 'st-priv-fs-${shareName.key}-rbac'), 64)
    scope: storageRg
    params: {
      fileShareName: shareName.value
      principalId: researcherEntraIdObjectId
      roleDefinitionId: rolesModule.outputs.roles.StorageFileDataSMBShareContributor
      storageAccountName: storageModule.outputs.storageAccountName
      // Do not specify principalType here because we don't know if researcherEntraIdObjectId is a user or a group
    }
  }
]

module vdiModule '../shared-modules/virtualDesktop/main.bicep' = if (useSessionHostAsResearchVm) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'vdi'), 64)
  params: {
    resourceGroupName: replace(rgNamingStructure, '{rgname}', 'avd')
    tags: actualTags
    location: location

    usePrivateLinkForHostPool: usePrivateEndpoints
    privateEndpointSubnetId: usePrivateEndpoints ? networkModule.outputs.createdSubnets.privateEndpointSubnet.id : ''
    privateLinkDnsZoneId: usePrivateEndpoints ? avdConnectionPrivateDnsZone.id : ''

    adminObjectId: adminEntraIdObjectId
    deploymentNameStructure: deploymentNameStructure
    desktopAppGroupFriendlyName: desktopAppGroupFriendlyName
    logonType: logonType
    namingStructure: replace(namingStructure, '{subWorkloadName}', 'avd')
    roles: rolesModule.outputs.roles
    userObjectId: researcherEntraIdObjectId
    workspaceFriendlyName: workspaceFriendlyName

    computeSubnetId: networkModule.outputs.createdSubnets.computeSubnet.id

    sessionHostLocalAdminUsername: sessionHostLocalAdminUsername
    sessionHostLocalAdminPassword: sessionHostLocalAdminPassword
    useCMK: useCMK
    diskEncryptionSetId: diskEncryptionSetModule.outputs.id
    sessionHostCount: sessionHostCount

    backupPolicyName: recoveryServicesVaultModule.outputs.backupPolicyName
    recoveryServicesVaultId: recoveryServicesVaultModule.outputs.id

    // TODO: Use activeDirectoryDomainInfo type
    domainJoinPassword: domainJoinPassword
    domainJoinUsername: domainJoinUsername
    sessionHostNamePrefix: sessionHostNamePrefix
    sessionHostSize: sessionHostSize

    adDomainFqdn: adDomainFqdn
    adOuPath: adOuPath
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

// Deploy the spoke airlock components
// Depending on the value of isAirlockCentralized, the spoke will either use the hub's airlock review storage account and review VM or deploy its own
module airlockModule './spoke-modules/airlock/main.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'airlock'), 64)
  scope: storageRg
  params: {
    location: location
    tags: actualTags

    useCentralizedReview: isAirlockReviewCentralized
    // Airlock resources in the hub
    centralAirlockResources: isAirlockReviewCentralized
      ? {
          storageAccountId: centralAirlockStorageAccountId
          keyVaultId: centralAirlockKeyVaultId
        }
      : {}

    airlockFileShareName: isAirlockReviewCentralized ? centralAirlockFileShareName : fileShareNames.exportReview

    approverEmail: airlockApproverEmail

    deploymentNameStructure: deploymentNameStructure
    namingConvention: namingConvention
    environment: environment
    sequence: sequence
    workloadName: workloadName

    encryptionKeyVaultUri: useCMK ? keyVaultModule.outputs.uri : ''
    encryptionUamiId: useCMK ? uamiModule.outputs.id : ''
    // TODO: Do not hardcode encryption key names
    storageAccountEncryptionKeyName: useCMK ? 'storage' : ''
    adfEncryptionKeyName: useCMK ? 'adf' : ''

    // Key Vault will store the file share's connection information and the encryption key, if needed
    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyVaultResourceGroupName: securityRg.name

    namingStructure: namingStructure
    privateStorageAccountConnStringSecretName: privateStorageConnStringSecretModule.outputs.secretName
    spokePrivateStorageAccountName: storageModule.outputs.storageAccountName
    publicStorageAccountAllowedIPs: publicStorageAccountAllowedIPs

    roles: rolesModule.outputs.roles

    // TODO: Improve parameter name to clarify what workspace this refers to
    workspaceName: '${workloadName}${sequenceFormatted}'

    containerNames: containerNames

    researcherAadObjectId: researcherEntraIdObjectId

    // TODO: Only if usePrivateEndpoint is true
    privateDnsZonesResourceGroupId: hubPrivateDnsZonesResourceGroupId
    // If airlock review is centralized, then we don't need to create a private endpoint because we don't create a storage account
    privateEndpointSubnetId: !isAirlockReviewCentralized
      ? networkModule.outputs.createdSubnets.privateEndpointSubnet.id
      : ''

    debugMode: debugMode
    debugRemoteIp: debugRemoteIp

    filesIdentityType: filesIdentityType
    domainJoinSpokeAirlockStorageAccount: logonType == 'ad' && !isAirlockReviewCentralized
    domainJoinInfo: storageAccountDomainJoinInfo

    hubManagementVmName: hubManagementVmName
    hubManagementVmResourceGroupName: hubManagementVmResourceGroupName
    hubManagementVmSubscriptionId: hubManagementVmSubscriptionId
    hubManagementVmUamiClientId: hubManagementVmUamiClientId
    hubManagementVmUamiPrincipalId: hubManagementVmUamiPrincipalId
  }
}

// Create a Recovery Services Vault and default backup policy
module recoveryServicesVaultModule '../shared-modules/recovery/recoveryServicesVault.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'recovery'), 64)
  scope: backupRg
  params: {
    location: location
    tags: actualTags

    useCMK: useCMK
    encryptionKeyUri: useCMK ? kvEncryptionKeys.rsv.keyUri : ''

    environment: environment
    namingConvention: namingConvention
    sequenceFormatted: sequenceFormatted
    namingStructure: namingStructureNoSub
    workloadName: workloadName

    debugMode: debugMode
    deploymentNameStructure: deploymentNameStructure
    roles: rolesModule.outputs.roles
    keyVaultResourceGroupName: keyVaultModule.outputs.resourceGroupName
    keyVaultName: keyVaultModule.outputs.keyVaultName
  }
}

/*
 * HUB REFERENCES
 */

// TODO: Split once into var and re-use var
var hubDnsZoneSubscriptionId = split(hubPrivateDnsZonesResourceGroupId, '/')[2]
var hubDnsZoneResourceGroupName = split(hubPrivateDnsZonesResourceGroupId, '/')[4]
var hubDnsZoneResourceGroup = resourceGroup(hubDnsZoneSubscriptionId, hubDnsZoneResourceGroupName)

resource avdConnectionPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.wvd.microsoft.com'
  scope: hubDnsZoneResourceGroup
}

output recoveryServicesVaultId string = recoveryServicesVaultModule.outputs.id
output backupPolicyName string = recoveryServicesVaultModule.outputs.backupPolicyName
output diskEncryptionSetId string = diskEncryptionSetModule.outputs.id
output computeSubnetId string = networkModule.outputs.createdSubnets.computeSubnet.id
output computeResourceGroupName string = computeRg.name
