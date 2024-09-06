param location string
param workspaceName string

param namingStructure string
param workloadName string
param environment string
param sequence int
param deploymentNameStructure string
param namingConvention string
@minLength(3)
@maxLength(24)
param spokePrivateStorageAccountName string

@description('FUTURE: If true, the airlock will be configured to use the hub\'s airlock storage account for the egress review. If false, a new storage account will be created here.')
param useCentralizedReview bool

param researcherAadObjectId string

@description('The names of the ingest and exportApproved containers in the public storage account; and exportRequest in the private storage account.')
param containerNames object = {
  ingest: 'ingest'
  exportApproved: 'export-approved'
  exportRequest: 'export-request'
}

@description('The email address where export approval requests will be sent.')
param approverEmail string

param roles object

// TODO: Replace with keyVaultId
param keyVaultName string
param keyVaultResourceGroupName string

@description('The name of the file share used for Airlock export reviews. The same parameter is used regardless of whether the airlock review is centralized or not.')
param airlockFileShareName string

// LATER: Create custom type
@description('Schema: { storageAccountId: string, keyVaultId: string }')
param centralAirlockResources object = {}

param publicStorageAccountAllowedIPs array = []

@description('The resource ID of the user-assigned managed identity to be used to access the encryption keys in Key Vault.')
param encryptionUamiId string

param storageAccountEncryptionKeyName string
param encryptionKeyVaultUri string
param adfEncryptionKeyName string

param privateDnsZonesResourceGroupId string
param privateEndpointSubnetId string

param domainJoinSpokeAirlockStorageAccount bool
param domainJoinInfo activeDirectoryDomainInfo = {
  adDomainFqdn: ''
  domainJoinPassword: ''
  domainJoinUsername: ''
}

param hubManagementVmSubscriptionId string = ''
param hubManagementVmResourceGroupName string = ''
param hubManagementVmName string = ''
param hubManagementVmUamiPrincipalId string = ''
param hubManagementVmUamiClientId string = ''

param tags object = {}
param subWorkloadName string = 'airlock'

@allowed(['AADDS', 'AADKERB', 'None'])
param filesIdentityType string

@description('Role assignements to create on the storage account.')
param storageAccountRoleAssignments roleAssignmentType

import { roleAssignmentType } from '../../../shared-modules/types/roleAssignment.bicep'

param debugMode bool = false
param debugRemoteIp string = ''

// Types

import { activeDirectoryDomainInfo } from '../../../shared-modules/types/activeDirectoryDomainInfo.bicep'

// Get a reference to the already existing private storage account for this spoke
// Assumed in the same resource group
resource privateStorageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' existing = {
  name: spokePrivateStorageAccountName
}

// Get a reference to the already existing Key Vault resource group for this spoke
resource spokeKeyVaultRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: keyVaultResourceGroupName
  scope: subscription()
}

// User Assigned Managed Identity to be used for deployment scripts
module uamiModule '../../../shared-modules/security/uami.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'uami-al')
  params: {
    location: location
    uamiName: replace(replace(namingStructure, '{rtype}', 'uami'), '{subWorkloadName}', 'al')
    tags: tags
  }
}

module spokeAirlockStorageAccountModule '../storage/main.bicep' = if (!useCentralizedReview) {
  name: replace(deploymentNameStructure, '{rtype}', 'st-airlock')
  params: {
    location: location
    namingStructure: namingStructure
    // No need for any blob containers in this account
    containerNames: []
    fileShareNames: [airlockFileShareName]

    // Create private endpoint for file service on this storage account
    privateDnsZonesResourceGroupId: privateDnsZonesResourceGroupId
    privateEndpointSubnetId: privateEndpointSubnetId
    storageAccountPrivateEndpointGroups: ['file']

    deploymentNameStructure: deploymentNameStructure
    sequence: sequence
    namingConvention: namingConvention
    workloadName: workloadName
    subWorkloadName: subWorkloadName
    environment: environment

    debugMode: debugMode
    debugRemoteIp: debugRemoteIp

    keyVaultName: keyVaultName
    keyVaultResourceGroupName: keyVaultResourceGroupName

    uamiId: encryptionUamiId
    storageAccountEncryptionKeyName: storageAccountEncryptionKeyName

    tags: union(tags, { 'hidden-title': 'Airlock Review Storage Account' })

    filesIdentityType: filesIdentityType
    // Domain join if needed
    domainJoin: domainJoinSpokeAirlockStorageAccount
    domainJoinInfo: domainJoinInfo
    hubSubscriptionId: hubManagementVmSubscriptionId
    hubManagementRgName: hubManagementVmResourceGroupName
    hubManagementVmName: hubManagementVmName
    uamiPrincipalId: hubManagementVmUamiPrincipalId
    uamiClientId: hubManagementVmUamiClientId
    roles: roles

    // The airlock storage uses file shares via ADF, so access keys are used
    allowSharedKeyAccess: true
  }
}

// Create a connection string secret for the airlock storage account
module privateStorageConnStringSecretModule './../security/keyVault-StorageAccountConnString.bicep' = if (!useCentralizedReview) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-secret'), 64)
  scope: subscription()
  params: {
    keyVaultName: keyVaultName
    keyVaultResourceGroupName: keyVaultResourceGroupName
    storageAccountName: spokeAirlockStorageAccountModule.outputs.storageAccountName
    storageAccountResourceGroupName: resourceGroup().name
  }
}

/* Call the centralized module to
 * - Assign this UAMI a role to approve the airlock review storage account's private endpoint in the hub
 * - Grant ADF managed identity access to centralized Key Vault to retrieve secrets (#12)
*/
module centralizedModule 'centralized.bicep' = if (useCentralizedReview) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'airlock-cent'), 64)
  params: {
    centralAirlockResources: centralAirlockResources
    deploymentNameStructure: deploymentNameStructure
    roles: roles
    spokeAdfPrincipalId: adfModule.outputs.principalId
    spokeUamiPrincipalId: uamiModule.outputs.principalId
  }
}

// Assign UAMI a role to approve the project's storage account's private endpoint
module uamiProjectStorageRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'uami-airlock-role')
  params: {
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: roles.StorageAccountContributor
    storageAccountName: privateStorageAccount.name
    principalType: 'ServicePrincipal'
  }
}

// Assign UAMI a role to approve the airlock storage account's private endpoint (GitHub issue #95)
module uamiAirlockStorageRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = if (!useCentralizedReview) {
  name: replace(deploymentNameStructure, '{rtype}', 'uami-airlock-role2')
  params: {
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: roles.StorageAccountContributor
    storageAccountName: spokeAirlockStorageAccountModule.outputs.storageAccountName
    principalType: 'ServicePrincipal'
  }
}

// Azure Data Factory resource and contents
module adfModule 'adf.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf')
  params: {
    namingStructure: namingStructure
    subWorkloadName: subWorkloadName
    location: location
    deploymentNameStructure: deploymentNameStructure
    privateStorageAcctName: spokePrivateStorageAccountName
    userAssignedIdentityId: uamiModule.outputs.id
    userAssignedIdentityPrincipalId: uamiModule.outputs.principalId
    roles: roles
    tags: tags
    debugMode: debugMode

    // Key Vault to retrieve connection strings
    keyVaultName: keyVaultName
    keyVaultResourceGroupName: keyVaultResourceGroupName

    adfEncryptionKeyName: adfEncryptionKeyName
    encryptionUserAssignedIdentityId: encryptionUamiId
    encryptionKeyVaultUri: encryptionKeyVaultUri
  }
}

var airlockStorageAccountName = useCentralizedReview
  ? centralizedModule.outputs.centralAirlockStorageAccountName
  : spokeAirlockStorageAccountModule.outputs.storageAccountName
var airlocKeyVaultUri = useCentralizedReview
  ? centralizedModule.outputs.centralKeyVaultUri
  : keyVault.properties.vaultUri

// Logic app for export review (moves file to airlock review storage account and sends approval email)
module logicAppModule 'logicApp.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'logic')
  params: {
    namingStructure: namingStructure
    subWorkloadName: subWorkloadName
    location: location
    prjStorageAcctName: spokePrivateStorageAccountName
    airlockFileShareName: airlockFileShareName
    airlockStorageAcctName: airlockStorageAccountName
    adfName: adfModule.outputs.name
    approverEmail: approverEmail
    sinkFolderPath: spokePrivateStorageAccountName
    sourceFolderPath: containerNames.exportRequest
    prjPublicStorageAcctName: publicStorageAccountModule.outputs.name
    keyVaultUri: airlocKeyVaultUri
    deploymentNameStructure: deploymentNameStructure
    roles: roles
    tags: tags
  }
}

var publicStorageAccountContainerNames = [
  containerNames.ingest
  containerNames.exportApproved
]

// Add storage with a public endpoint enabled for ingest and export
module publicStorageAccountNameModule '../../../module-library/createValidAzResourceName.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'pubsaname'), 64)
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

module publicStorageAccountModule '../storage/storageAccount.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'st-pub')
  params: {
    storageAccountName: publicStorageAccountNameModule.outputs.validName
    location: location
    namingStructure: namingStructure
    containerNames: publicStorageAccountContainerNames
    // No file shares needed in this storage account
    fileShareNames: []

    // Do not create private endpoints on this storage account
    privateEndpointInfo: []
    privateEndpointSubnetId: ''

    uamiId: encryptionUamiId
    encryptionKeyName: storageAccountEncryptionKeyName
    keyVaultUri: encryptionKeyVaultUri

    // Do not apply a lock to this storage account that contains only transient data
    // This is also important for subsequent deployments to be able to stop the ADF blob trigger
    applyDeleteLock: false

    // TODO: Add debugIp if debugMode is true
    allowedIpAddresses: publicStorageAccountAllowedIPs

    tags: union(tags, { 'hidden-title': 'Public Storage Account' })

    // No identity-based authentication here; there are no file shares
    filesIdentityType: 'None'

    allowSharedKeyAccess: false

    storageAccountRoleAssignments: storageAccountRoleAssignments
  }
}

// Grant researchers access to public export-approved and ingest containers
module publicStContainerRbacModule '../../../module-library/roleAssignments/roleAssignment-st-container.bicep' = [
  for containerName in publicStorageAccountContainerNames: {
    name: take(replace(deploymentNameStructure, '{rtype}', 'st-pub-ct-${containerName}-rbac'), 64)
    params: {
      containerName: containerName
      principalId: researcherAadObjectId
      roleDefinitionId: roles.StorageBlobDataContributor
      storageAccountName: publicStorageAccountModule.outputs.name
      // Do not specify a principalType here because we don't know if researcherAadObjectId is a user or a group
    }
  }
]

// Grant ADF identity Storage Blob Data Contributor role on public storage account adfModule.outputs.principalId
module adfPublicStorageAccountRbacModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-pub-role')
  params: {
    principalId: adfModule.outputs.principalId
    roleDefinitionId: roles.StorageBlobDataContributor
    storageAccountName: publicStorageAccountModule.outputs.name
    principalType: 'ServicePrincipal'
  }
}

// Setup System Event Grid Topic for public storage account. We only do this here to control the name of the event grid topic
module eventGridForPublicModule 'eventGrid.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'evgt-public')
  params: {
    location: location
    namingStructure: namingStructure
    subWorkloadName: publicStorageAccountModule.outputs.name
    resourceId: publicStorageAccountModule.outputs.id
    topicName: 'Microsoft.Storage.StorageAccounts'
    tags: tags
  }
}

// Setup System Event Grid Topic for private storage account.
// We do this here to control the name of the event grid topic.
module eventGridForPrivateModule 'eventGrid.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'evgt-private')
  params: {
    location: location
    namingStructure: namingStructure
    subWorkloadName: spokePrivateStorageAccountName
    resourceId: privateStorageAccount.id
    topicName: 'Microsoft.Storage.StorageAccounts'
    tags: tags
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
  scope: spokeKeyVaultRg
}

// Trigger to move ingested blobs from the project's public storage account to the private storage account
module ingestTriggerModule 'adfTrigger.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-trigger-ingest')
  params: {
    adfName: adfModule.outputs.name
    workspaceName: workspaceName
    storageAccountId: publicStorageAccountModule.outputs.id
    storageAccountType: 'Public'
    ingestPipelineName: adfModule.outputs.pipelineName
    #disable-next-line BCP334 BCP335
    sourceStorageAccountName: publicStorageAccountModule.outputs.name
    sinkStorageAccountName: spokePrivateStorageAccountName
    containerName: containerNames.ingest
    additionalSinkFolderPath: 'incoming'
    // TODO: Do not hardcode file share name 'shared'
    sinkFileShareName: 'shared'
    // The URL of the project's Key Vault
    // The project's KV stores the connection string to the project's file share
    sinkConnStringKvBaseUrl: keyVault.properties.vaultUri
  }
}

// Create managed private endpoints for the private storage account's file and dfs endpoints
module privateManagedPrivateEndpointModule 'adfManagedPrivateEndpoint.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-pep-priv')
  params: {
    adfName: adfModule.outputs.name
    storageAccountId: privateStorageAccount.id
    storageAccountDisplayName: spokePrivateStorageAccountName
  }
}

// Create managed private endpoint for airlock storage account's file endpoint
module airlockManagedPrivateEndpointModule 'adfManagedPrivateEndpoint.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-pep-airlock')
  params: {
    adfName: adfModule.outputs.name
    storageAccountId: useCentralizedReview
      ? centralAirlockResources.storageAccountId
      : spokeAirlockStorageAccountModule.outputs.storageAccountId
    storageAccountDisplayName: airlockStorageAccountName
    // The airlock storage account only has a file share
    privateEndpointGroupIDs: [
      'file'
    ]
  }
}

// We can't approve any endpoints that weren't created by this deployment; this could be a security vulnerability, especially on the airlock review storage account
// By collecting the private endpoints to approve, the script can ensure only those private endpoints will be approved
var privateEndpointIdsToApprove = join(
  concat(
    privateManagedPrivateEndpointModule.outputs.privateEndpointIds,
    airlockManagedPrivateEndpointModule.outputs.privateEndpointIds
  ),
  '\',\''
)

var privateLinkResourceIds = join(
  [
    privateManagedPrivateEndpointModule.outputs.privateLinkResourceId
    airlockManagedPrivateEndpointModule.outputs.privateLinkResourceId
  ],
  '\',\''
)

// Start the triggers in the Data Factory
module startTriggerDeploymentScriptModule 'deploymentScript.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'dplscr-StartTriggers')
  params: {
    location: location
    subWorkloadName: 'StartTriggers'
    namingStructure: namingStructure
    arguments: '-ResourceGroupName ${resourceGroup().name} -AzureDataFactoryName ${adfModule.outputs.name} -SubscriptionId ${subscription().subscriptionId}'
    scriptContent: loadTextContent('./content/StartAdfTriggers.ps1')
    userAssignedIdentityId: uamiModule.outputs.id
    tags: tags
    debugMode: debugMode
  }
}

// UAMI which executes the deployment scripts must have permission to approve private endpoints, including in the hub 
// Requires role assignment of Storage Account Contributor, which was done earlier
module approvePrivateEndpointDeploymentScriptModule 'deploymentScript.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'dplscr-ApprovePep')
  params: {
    location: location
    subWorkloadName: 'ApprovePep'
    namingStructure: namingStructure
    arguments: '-PrivateLinkResourceIds @(\'${privateLinkResourceIds}\') -PrivateEndpointIds @(\'${privateEndpointIdsToApprove}\') -SubscriptionId ${subscription().subscriptionId}'
    scriptContent: loadTextContent('./content/ApproveManagedPrivateEndpoint.ps1')
    userAssignedIdentityId: uamiModule.outputs.id
    tags: tags
    debugMode: debugMode
  }

  dependsOn: [centralizedModule, uamiProjectStorageRoleAssignmentModule]
}

// TODO: Access controls on airlock review storage account, if not centralized, for reviewer object ID
