param location string
param namingStructure string
param workspaceName string
param deploymentNameStructure string
@minLength(3)
@maxLength(24)
param spokePrivateStorageAccountName string
@minLength(3)
@maxLength(24)
param publicStorageAccountName string

param researcherAadObjectId string

@description('The names of the ingest, exportApproved containers in the public storage account; and exportRequest in the private storage account.')
param containerNames object = {
  ingest: 'ingest'
  exportApproved: 'export-approved'
  exportRequest: 'export-request'
}

param approverEmail string
param roles object

param keyVaultName string
param keyVaultResourceGroupName string
param privateStorageAccountConnStringSecretName string

// LATER: This is superfluous; we can get the storage account name from the storage account ID
@minLength(3)
@maxLength(24)
param airlockStorageAccountName string
param airlockFileShareName string
param airlockStorageAccountId string
// LATER: This is superfluous; we can get the resource group name from the storage account ID
param airlockResourceGroupName string

param hubKeyVaultName string
param hubKeyVaultResourceGroupName string
param hubAirlockSubscriptionId string

param publicStorageAccountAllowedIPs array = []

param encryptionUamiId string
param storageAccountEncryptionKeyName string
param encryptionKeyVaultUri string
param adfEncryptionKeyName string

param tags object = {}
param subWorkloadName string = 'airlock'

param debugMode bool = false

resource hubKvRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: hubKeyVaultResourceGroupName
  scope: subscription(hubAirlockSubscriptionId)
}

resource hubKv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: hubKeyVaultName
  scope: hubKvRg
}

// Get a reference to the already existing private storage account for this spoke
resource privateStorageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' existing = {
  name: spokePrivateStorageAccountName
}

// User Assigned Managed Identity to be used for deployment scripts
module uamiModule '../security/uami.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'uami-al')
  params: {
    location: location
    uamiName: replace(replace(namingStructure, '{rtype}', 'uami'), '{subWorkloadName}', 'al')
    tags: tags
  }
}

// Assign UAMI a role to approve the airlock storage account's private endpoint in the hub
resource airlockRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  scope: subscription(hubAirlockSubscriptionId)
  name: airlockResourceGroupName
}

module uamiAirlockStorageRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'uami-airlock-role')
  scope: airlockRg
  params: {
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: roles['Storage Account Contributor']
    storageAccountName: airlockStorageAccountName
  }
}

// Assign UAMI a role to approve the project's storage account's private endpoint
module uamiProjectStorageRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'uami-airlock-role')
  params: {
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: roles['Storage Account Contributor']
    storageAccountName: privateStorageAccount.name
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

    privateStorageAccountConnStringSecretName: privateStorageAccountConnStringSecretName
    adfEncryptionKeyName: adfEncryptionKeyName
    encryptionUserAssignedIdentityId: encryptionUamiId
    encryptionKeyVaultUri: encryptionKeyVaultUri
  }
}

// Grant ADF managed identity access to hub and project KVs to retrieve secrets (#12)
module adfHubKvRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-kv.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-role-hubkv')
  scope: hubKvRg
  params: {
    kvName: hubKv.name
    principalId: adfModule.outputs.principalId
    // Can't use the roles object here because it retrieved roleDefinitionIds from the spoke subscription
    // Even though the hub role definition ID is the same, it leads to a conflict because the roleDefinitionId is the full resource ID, including subscription ID
    // Which means that it doesn't get detected correctly as already existing.
    roleDefinitionId: subscriptionResourceId(hubAirlockSubscriptionId, 'Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}

resource prjKvRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: keyVaultResourceGroupName
  scope: subscription()
}

module adfPrjKvRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-kv.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-role-prjkv')
  scope: prjKvRg
  params: {
    kvName: prjKeyVault.name
    principalId: adfModule.outputs.principalId
    roleDefinitionId: roles['Key Vault Secrets User']
  }
}

// Logic app for export review (moves file to airlock and sends approval email)
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
    prjPublicStorageAcctName: publicStorageAccountName
    hubCoreKeyVaultUri: hubKv.properties.vaultUri
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
module publicStorageAccountModule '../storage/storageAccount.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'st-pub')
  params: {
    storageAccountName: publicStorageAccountName
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

    allowedIpAddresses: publicStorageAccountAllowedIPs

    tags: union(tags, { 'hidden-title': 'Public Storage Account' })
  }
}

// Grant researchers access to public export-approved and ingest containers
module publicStContainerRbacModule '../../../module-library/roleAssignments/roleAssignment-st-container.bicep' = [for containerName in publicStorageAccountContainerNames: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'st-pub-ct-${containerName}-rbac'), 64)
  params: {
    containerName: containerName
    principalId: researcherAadObjectId
    roleDefinitionId: roles['Storage Blob Data Contributor']
    storageAccountName: publicStorageAccountModule.outputs.name
  }
}]

// Grant ADF identity Storage Blob Data Contributor role on public storage account adfModule.outputs.principalId
module adfPublicStorageAccountRbacModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-pub-role')
  params: {
    principalId: adfModule.outputs.principalId
    roleDefinitionId: roles['Storage Blob Data Contributor']
    storageAccountName: publicStorageAccountModule.outputs.name
  } }

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

// Setup System Event Grid Topic for private storage account. We only do this here to control the name of the event grid topic
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

resource kvRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: keyVaultResourceGroupName
  scope: subscription()
}

resource prjKeyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
  scope: kvRg
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
    sinkConnStringKvBaseUrl: prjKeyVault.properties.vaultUri
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
    storageAccountId: airlockStorageAccountId
    storageAccountDisplayName: airlockStorageAccountName
    // The airlock storage account only has a file share
    privateEndpointGroupIDs: [
      'file'
    ]
  }
}

// We can't approve any endpoints that weren't created by this deployment; this could be a security vulnerability, especially on the airlock storage account
// By collecting the private endpoints to approve, the script can ensure only those private endpoints will be approved
var privateEndpointIdsToApprove = join(concat(privateManagedPrivateEndpointModule.outputs.privateEndpointIds, airlockManagedPrivateEndpointModule.outputs.privateEndpointIds), '\',\'')

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

// UAMI which executes the deployment scripts must have permission to approve private endpoints, including in the hub - requires role assignment of Storage Account Contributor
module approvePrivateEndpointDeploymentScriptModule 'deploymentScript.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'dplscr-ApprovePep')
  params: {
    location: location
    subWorkloadName: 'ApprovePep'
    namingStructure: namingStructure
    arguments: '-PrivateLinkResourceIds @(\'${privateManagedPrivateEndpointModule.outputs.privateLinkResourceId}\', \'${airlockManagedPrivateEndpointModule.outputs.privateLinkResourceId}\') -PrivateEndpointIds @(\'${privateEndpointIdsToApprove}\') -SubscriptionId ${subscription().subscriptionId}'
    scriptContent: loadTextContent('./content/ApproveManagedPrivateEndpoint.ps1')
    userAssignedIdentityId: uamiModule.outputs.id
    tags: tags
    debugMode: debugMode
  }
}
