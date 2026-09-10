targetScope = 'subscription'

metadata description = 'Deploys a research spoke associated with a previously deployed research hub.'
metadata name = 'Research Spoke'

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

@description('Do not specify. Date and time will be used to create unique deployment names.')
param deploymentTime string = utcNow()

@description('The date and time seed for the expiration of the encryption keys.')
param encryptionKeyExpirySeed string = utcNow()

// Network parameters
@description('Format: `[ "192.168.0.0/24", "192.168.10.0/24" ]`')
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

@description('Experimental. If true, will create policy exemptions for resources and policy definitions that are not compliant due to issues with common Azure built-in compliance policy initiatives.')
param createPolicyExemptions bool = false
@description('Required if policy exemptions must be created.')
param policyAssignmentId string = ''

@description('The username for the local user account on the session hosts. Required if when deploying AVD session hosts in the hub (`useSessionHostAsResearchVm = false`).')
@secure()
param sessionHostLocalAdminUsername string = ''
@description('The password for the local user account on the session hosts. Required if when deploying AVD session hosts in the hub (`useSessionHostAsResearchVm = false`).')
@secure()
param sessionHostLocalAdminPassword string = ''
@description('Specifies if logons to virtual machines should use AD or Entra ID.')
@allowed(['ad', 'entraID'])
param logonType string
@description('The username of a domain user or service account to use to join the Active Directory domain. Use UPN notation. Required if using AD join.')
@secure()
param domainJoinUsername string = ''
@description('The password of the domain user or service account to use to join the Active Directory domain. Required if using AD join.')
@secure()
param domainJoinPassword string = ''

@description('The identity type to use for Azure Files. Use `AADKERB` for Entra ID Kerberos, `AADDS` for Entra Domain Services, or `None` for ADDS.')
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
@description('The prefix used for the computer names of the session host(s). Maximum 11 characters. If not specified, the default session host names will be used.')
@maxLength(11)
param customSessionHostNamePrefix string = ''
@description('A valid Azure Virtual Machine size. Use `az vm list-sizes --location "<region>"` to retrieve a list for the selected location')
param sessionHostSize string = 'N/A'
@description('If true, will configure the deployment of AVD to make the AVD session hosts usable as research VMs. This will give full desktop access, flow the AVD traffic through the firewall, etc.')
param useSessionHostAsResearchVm bool = true
@description('Entra ID object ID of the user or group (researchers) to assign permissions to access the AVD application groups and storage.')
param researcherEntraIdObjectId string
@description('Entra ID object ID of the user or group (honest brokers) to assign permissions to access the AVD application groups and storage.')
param honestBrokerEntraIdObjectId string
@description('Entra ID object ID of the admin user or group to assign permissions to administer the AVD session hosts, storage, etc.')
param adminEntraIdObjectId string

// Airlock parameters
@description('If true, airlock reviews will take place centralized in the hub. If true, the hub* parameters must be specified also.')
param isAirlockReviewCentralized bool = false
@description('The email address of the reviewer for this project.')
param airlockApproverEmail string
@description('The email address where process notifications (designed to be the principal investigator) will be sent.')
param airlockProcessNotificationEmail string
@description('The email address that will appear in the "From" field of emails sent by the airlock Logic App.')
param airlockFromEmail string
@description('The allowed file extensions for ingest.')
param allowedIngestFileExtensions array = []

// HUB AIRLOCK NAMES
@description('The full Azure resource ID of the hub\'s airlock review storage account.')
param centralAirlockStorageAccountId string
@description('The file share name for airlock reviews.')
param centralAirlockFileShareName string
@description('The name of the Key Vault in the research hub containing the airlock review storage account\'s connection string as a secret.')
param centralAirlockKeyVaultId string

@description('The list of allowed IP addresses or ranges for ingest and approved export pickup purposes.')
param publicStorageAccountAllowedIPs array = []

@description('The Azure built-in regulatory compliance framework to target. This will affect whether or not customer-managed keys, private endpoints, etc. are used. This will *not* deploy any policy assignments.')
@allowed([
  'NIST80053R5'
  'HIPAAHITRUST'
  'CMMC2L2'
  'NIST800171R2'
])
// Default to the strictest supported compliance framework
param complianceTarget string = 'NIST80053R5'

@description('The backup schedule policy for virtual machines. Defaults to every four hours starting at midnight each day. Refer to the type definitions at [https://learn.microsoft.com/azure/templates/microsoft.recoveryservices/vaults/backuppolicies?pivots=deployment-language-bicep#schedulepolicy-objects](https://learn.microsoft.com/azure/templates/microsoft.recoveryservices/vaults/backuppolicies?pivots=deployment-language-bicep#schedulepolicy-objects).')
param vmSchedulePolicy backupPolicyTypes.iaasSchedulePolicyType = {
  schedulePolicyType: 'SimpleSchedulePolicyV2'
  scheduleRunFrequency: 'Hourly'
  hourlySchedule: {
    interval: 4
    scheduleWindowStartTime: '00:00'
    scheduleWindowDuration: 23
  }
  dailySchedule: null
  weeklySchedule: null
}

@description('The backup schedule policy for Azure File Shares. Defaults to daily at the retention time. Refer to the type definitions at [https://learn.microsoft.com/azure/templates/microsoft.recoveryservices/vaults/backuppolicies?pivots=deployment-language-bicep#schedulepolicy-objects](https://learn.microsoft.com/azure/templates/microsoft.recoveryservices/vaults/backuppolicies?pivots=deployment-language-bicep#schedulepolicy-objects).')
param fileShareSchedulePolicy backupPolicyTypes.fileShareSchedulePolicyType = {
  schedulePolicyType: 'SimpleSchedulePolicy'
  scheduleRunFrequency: 'Daily'
  scheduleRunDays: null
  scheduleRunTimes: [retentionBackupTime]
}

@description('The retention policy for all backup policies. Defaults to 8 days of daily backups, 6 weeks of weekly backups, and 13 months of monthly backups.')
param backupRetentionPolicy backupPolicyTypes.retentionPolicyType = {
  retentionPolicyType: 'LongTermRetentionPolicy'

  dailySchedule: {
    retentionTimes: [retentionBackupTime]
    retentionDuration: {
      count: 8
      durationType: 'Days'
    }
  }

  weeklySchedule: {
    daysOfTheWeek: ['Sunday']
    retentionTimes: [retentionBackupTime]
    retentionDuration: {
      count: 6
      durationType: 'Weeks'
    }
  }

  monthlySchedule: {
    retentionScheduleFormatType: 'Daily'
    retentionScheduleDaily: {
      daysOfTheMonth: [
        {
          date: 1
          isLast: false
        }
      ]
    }
    retentionTimes: [retentionBackupTime]
    retentionDuration: {
      count: 13
      durationType: 'Months'
    }
    retentionScheduleWeekly: null
  }

  yearlySchedule: null
}

@description('The time zone to use for the backup schedule policy.')
param backupSchedulePolicyTimeZone string = 'UTC'

@description('In case of Hourly backup schedules, this retention time must be set to the time of one of the hourly backups.')
param retentionBackupTime string = '2023-12-31T08:00:00.000Z'

@description('The Azure resource ID of the management VM in the hub. Required if using AD join for Azure Files (`filesIdentityType = \'None\'`). This value is output by the hub deployment.')
param hubManagementVmId string = ''
@description('The Entra ID object ID of the user-assigned managed identity of the management VM. This will be given the necessary role assignment to perform a domain join on the storage account(s). Required if using AD join for Azure Files (`filesIdentityType = \'None\'`). This value is output by the hub deployment.')
param hubManagementVmUamiPrincipalId string = ''
@description('The client ID of the user-assigned managed identity of the management VM. Required if using AD join for Azure Files (`filesIdentityType = \'None\'`). This value is output by the hub deployment.')
param hubManagementVmUamiClientId string = ''

@description('Set to `true` to enable debug mode of the spoke. Debug mode will allow remote access to storage, etc. Should be not be used for production deployments.')
param debugMode bool = false
@description('Used when `debugMode = true`. The IP address to allow access to storage, Key Vault, etc.')
param debugRemoteIp string = ''
@description('The object ID of the user or group to assign permissions. Only used when `debugMode = true`.')
param debugPrincipalId string = az.deployer().objectId

//----------------------------- END PARAMETERS -----------------------------

//----------------------------- START TYPES --------------------------------

import * as backupPolicyTypes from '../shared-modules/types/backupPolicyTypes.bicep'
//import { roleAssignmentType } from '../shared-modules/types/roleAssignment.bicep'

//----------------------------- END TYPES ----------------------------------

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
var rgNamingStructure = replace(replace(namingStructure, '{rtype}', 'rg-{rgName}'), '-{subWorkloadName}', '')

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
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}

// Create the resource groups
resource securityRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgName}', 'security')
  location: location
  tags: actualTags
}

resource storageRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgName}', 'storage')
  location: location
  tags: actualTags
}

resource networkRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgName}', 'network')
  location: location
  tags: actualTags
}

resource backupRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgName}', 'backup')
  location: location
  tags: actualTags
}

// Create a resource group for additional compute resources (like shared VMs)
resource computeRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: replace(rgNamingStructure, '{rgName}', 'compute')
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
  #disable-next-line BCP334
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
    #disable-next-line BCP334
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
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'defenderplans'), 64)
}

module keyVaultNameModule '../module-library/createValidAzResourceName.bicep' = {
  #disable-next-line BCP334
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
  #disable-next-line BCP334
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
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'keys'), 64)
  scope: securityRg
  params: {
    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyExpirySeed: encryptionKeyExpirySeed
    debugMode: debugMode
  }
}

var kvEncryptionKeys = useCMK ? reduce(encryptionKeysModule.?outputs.keys!, {}, (cur, next) => union(cur, next)) : null

module uamiModule '../shared-modules/security/uami.bicep' = {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami'), 64)
  scope: securityRg
  params: {
    tags: actualTags
    uamiName: replace(namingStructureNoSub, '{rtype}', 'uami')
    location: location
  }
}

module uamiKvRbacModule '../module-library/roleAssignments/roleAssignment-kv.bicep' = {
  #disable-next-line BCP334
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
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'diskEnc'), 64)
  scope: securityRg
  params: {
    keyVaultId: keyVaultModule.outputs.id
    // TODO: Validate WithVersion is needed
    keyUrl: kvEncryptionKeys.?diskEncryptionSet.keyUriWithVersion
    uamiId: uamiModule.outputs.id
    location: location
    name: replace(namingStructureNoSub, '{rtype}', 'des')
    tags: actualTags
    deploymentNameStructure: deploymentNameStructure
    kvRoleDefinitionId: rolesModule.outputs.roles.KeyVaultCryptoServiceEncryptionUser
  }

  dependsOn: [uamiKvRbacModule]
}

var hubManagementVmSubscriptionId = !empty(hubManagementVmId) ? split(hubManagementVmId, '/')[2] : ''
var hubManagementVmResourceGroupName = !empty(hubManagementVmId) ? split(hubManagementVmId, '/')[4] : ''
var hubManagementVmName = !empty(hubManagementVmId) ? split(hubManagementVmId, '/')[8] : ''

// Create a role assignment representation for researchers to see the storage accounts
var storageAccountReaderRoleAssignmentForResearcherGroup = {
  roleDefinitionId: rolesModule.outputs.roles.Reader
  principalId: researcherEntraIdObjectId
  description: 'Read access to the storage account is required to use Azure Storage Explorer.'
}

// Deploy the project's private storage account
module storageModule './spoke-modules/storage/main.bicep' = {
  #disable-next-line BCP334
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

    // The private storage uses file shares via ADF, so access keys are used
    allowSharedKeyAccess: true

    createPolicyExemptions: createPolicyExemptions
    policyAssignmentId: policyAssignmentId

    storageAccountRoleAssignments: [
      storageAccountReaderRoleAssignmentForResearcherGroup
    ]
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
  #disable-next-line BCP334
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
    #disable-next-line BCP334
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

// Construct the session hosts' VM name prefix using the pattern "SH-{workloadName}-{sequence}",
// taking into account that the max length of the vmNamePrefix is 11 characters
var vmNamePrefixLead = 'sh-'
var vmNamePrefixWorkloadName = take(workloadName, 11 - length(string(sequence)) - length('sh-'))
var vmNamePrefix = empty(customSessionHostNamePrefix)
  ? '${vmNamePrefixLead}${vmNamePrefixWorkloadName}${sequence}'
  : customSessionHostNamePrefix

module vdiModule '../shared-modules/virtualDesktop/main.bicep' = if (useSessionHostAsResearchVm) {
  // This warning is incorrect
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'vdi'), 64)
  params: {
    resourceGroupName: replace(rgNamingStructure, '{rgName}', 'avd')
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
    userObjectIds: [
      researcherEntraIdObjectId
      honestBrokerEntraIdObjectId
    ]
    workspaceFriendlyName: workspaceFriendlyName

    computeSubnetId: networkModule.outputs.createdSubnets.computeSubnet.id

    sessionHostLocalAdminUsername: sessionHostLocalAdminUsername
    sessionHostLocalAdminPassword: sessionHostLocalAdminPassword
    useCMK: useCMK
    diskEncryptionSetId: useCMK ? diskEncryptionSetModule.?outputs.id! : ''
    sessionHostCount: sessionHostCount

    backupPolicyName: recoveryServicesVaultModule.outputs.vmBackupPolicyName
    recoveryServicesVaultId: recoveryServicesVaultModule.outputs.id

    // TODO: Use activeDirectoryDomainInfo type
    domainJoinPassword: domainJoinPassword
    domainJoinUsername: domainJoinUsername
    sessionHostNamePrefix: vmNamePrefix
    sessionHostSize: sessionHostSize

    adDomainFqdn: adDomainFqdn
    adOuPath: adOuPath
  }
}

// Store the file share connection string of the private storage account in Key Vault
module privateStorageConnStringSecretModule './spoke-modules/security/keyVault-StorageAccountConnString.bicep' = {
  #disable-next-line BCP334
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
  #disable-next-line BCP334
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

    // TODO: Refactor
    honestBrokerEntraObjectId: honestBrokerEntraIdObjectId
    honestBrokerRoleDefinitionId: rolesModule.outputs.roles.StorageFileDataSMBShareReader

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
    spokePrivateStorageAccountName: storageModule.outputs.storageAccountName
    spokePrivateFileShareName: fileShareNames.shared
    publicStorageAccountAllowedIPs: publicStorageAccountAllowedIPs

    roles: rolesModule.outputs.roles

    // TODO: Improve parameter name to clarify what workspace this refers to
    workspaceName: '${workloadName}${sequenceFormatted}'

    containerNames: containerNames

    researcherAadObjectId: researcherEntraIdObjectId

    privateDnsZonesResourceGroupId: usePrivateEndpoints ? hubPrivateDnsZonesResourceGroupId : ''
    // If airlock review is centralized, then we don't need to create a private endpoint because we don't create a storage account
    privateEndpointSubnetId: !isAirlockReviewCentralized && usePrivateEndpoints
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

    storageAccountRoleAssignments: [
      storageAccountReaderRoleAssignmentForResearcherGroup
    ]

    usePrivateEndpoints: usePrivateEndpoints

    allowedIngestFileExtensions: allowedIngestFileExtensions

    processNotificationEmail: airlockProcessNotificationEmail
    fromEmail: airlockFromEmail
  }
}

// Create a Recovery Services Vault and default backup policy
module recoveryServicesVaultModule '../shared-modules/recovery/recoveryServicesVault.bicep' = {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'recovery'), 64)
  scope: backupRg
  params: {
    location: location
    tags: actualTags

    useCMK: useCMK
    encryptionKeyUri: useCMK ? kvEncryptionKeys.?rsv.keyUri : ''

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

    timeZone: backupSchedulePolicyTimeZone

    protectedStorageAccountId: storageModule.outputs.storageAccountId
    protectedAzureFileShares: [
      fileShareNames.shared
    ]

    fileShareSchedulePolicy: fileShareSchedulePolicy
    vmSchedulePolicy: vmSchedulePolicy

    retentionPolicy: backupRetentionPolicy
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

@description('The Azure resource ID of the spoke\'s Recovery Services Vault. Used in service module templates to add additional resources to the vault.')
output recoveryServicesVaultId string = recoveryServicesVaultModule.outputs.id
@description('The name of the backup policy used for Azure VM backups in the spoke.')
output vmBackupPolicyName string = recoveryServicesVaultModule.outputs.vmBackupPolicyName
@description('The Azure resource ID of the disk encryption set used for customer-managed key encryption of managed disks in the spoke.')
output diskEncryptionSetId string = useCMK ? diskEncryptionSetModule.?outputs.id! : ''
@description('The Azure resource ID of the ComputeSubnet.')
output computeSubnetId string = networkModule.outputs.createdSubnets.computeSubnet.id
@description('The resource group name of the compute resource group.')
output computeResourceGroupName string = computeRg.name

// Double up the \ in the output so it can be pasted easily into a bicepparam file
@description('The UNC path to the \'shared\' file share in the spoke\'s private storage account.')
output shortcutTargetPath string = replace(
  '${storageModule.outputs.storageAccountFileShareBaseUncPath}${fileShareNames.shared}',
  '\\',
  '\\\\'
)
