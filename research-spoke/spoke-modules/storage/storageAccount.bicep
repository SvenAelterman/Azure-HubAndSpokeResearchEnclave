@description('The name of the storage account to be created or updated.')
param storageAccountName string
param location string = resourceGroup().location
param tags object
@description('The user-assigned managed identity to access the customer-managed encryption key (CMK).')
param uamiId string
@description('Name of the customer-managed encryption key in Key Vault.')
param encryptionKeyName string
@description('URI of the Key Vault where the customer-managed encryption key is stored.')
param keyVaultUri string
@description('The structure to use to generate resource names, such as private endpoints. etc.')
param namingStructure string
@description('The Azure resource ID of the subnet where the private endpoint will be created.')
param privateEndpointSubnetId string

@description('An array of objects with the following schema: { subResourceName: string, dnsZoneName: string, dnsZoneId: string }')
param privateEndpointInfo array
@description('An array of valid SMB file share names to create.')
param fileShareNames array
@description('An array of valid Blob container names to create.')
param containerNames array
@description('Determines if the storage account will allow access using the access keys.')
param allowSharedKeyAccess bool

param createPolicyExemptions bool = false
param policyAssignmentId string = ''

// TODO: Update AADDS to EDS (Entra Domain Services)
@description('The type of identity to use for identity-based authentication for Azure Files. Valid values are: AADDS, AADKERB, and AD.')
@allowed(['AADDS', 'AADKERB', 'None'])
param filesIdentityType string

param debugMode bool = false
param debugRemoteIp string = ''
param applyDeleteLock bool = !debugMode

param allowedIpAddresses array = []

// If debug mode is enabled, deploy an IP rule for the debug IP address; otherwise, just use the specified list
// This will automatically deduplicate
var actualAllowedIpAddresses = debugMode ? concat(allowedIpAddresses, array(debugRemoteIp)) : allowedIpAddresses

var useCMK = !empty(uamiId) && !empty(encryptionKeyName) && !empty(keyVaultUri)

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    // TODO: the external facing account might not need to be GRS
    name: 'Standard_GRS'
  }
  kind: 'StorageV2'
  // Assign a user-assigned managed identity to the storage account for CMK access, if provided
  identity: !empty(uamiId)
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${uamiId}': {}
        }
      }
    : null

  properties: {
    // Note: Bypass and Resource Access Rules still take priority over this
    publicNetworkAccess: !debugMode && empty(actualAllowedIpAddresses) ? 'Disabled' : 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    // Required for ADF access to file shares (no support for managed identity yet)
    allowSharedKeyAccess: allowSharedKeyAccess

    networkAcls: {
      // TODO: Add resource access rules for export approval Logic App
      resourceAccessRules: []
      // 2024-02-26: This appears to be necessary for starting the ADF trigger
      // Logic App trigger can access the storage account with resource access rules even when bypass = 'None'
      // Only the external-facing storage account needs to allow this Bypass to allow the ADF trigger to start
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: [
        for allowedIp in actualAllowedIpAddresses: {
          value: allowedIp
          action: 'Allow'
        }
      ]

      // Note: Bypass and Resource Access Rules still take priority over this
      defaultAction: 'Deny'
    }

    // Allow for any of three authentication methods: Entra ID, Entra Domain Services, or AD DS
    azureFilesIdentityBasedAuthentication: (filesIdentityType == 'None')
      ? null
      : {
          directoryServiceOptions: filesIdentityType
          defaultSharePermission: 'None'
          // TODO: When filesIdentityType == AADDS, specify activeDirectoryProperties
          /*
          activeDirectoryProperties: (filesIdentityType == 'AADDS') ? {
                domainGuid: identityDomainGuid
                domainName: identityDomainName
            } : {}
          */
        }

    supportsHttpsTrafficOnly: true

    // TODO: Modify if CMK is not required
    encryption: {
      requireInfrastructureEncryption: true

      identity: useCMK
        ? {
            userAssignedIdentity: uamiId
          }
        : null
      keySource: useCMK ? 'Microsoft.Keyvault' : ''
      keyvaultproperties: useCMK
        ? {
            keyname: encryptionKeyName
            keyvaulturi: keyVaultUri
          }
        : null
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        table: {
          keyType: 'Account'
          enabled: true
        }
        queue: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
    }
    accessTier: 'Hot'
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

@batchSize(1)
resource fileShares 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = [
  for shareName in fileShareNames: {
    name: shareName
    parent: fileService
    properties: {
      enabledProtocols: 'SMB'
    }
  }
]

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = [
  for containerName in containerNames: {
    name: containerName
    parent: blobService
  }
]

resource storageAccountLock 'Microsoft.Authorization/locks@2020-05-01' = if (applyDeleteLock) {
  name: replace(namingStructure, '{rtype}', 'st-lock')
  scope: storageAccount
  properties: {
    level: 'CanNotDelete'
    notes: 'This storage account potentially contains research data. Delete this lock to delete the storage account after validating that the research data is not subject to retention requirements.'
  }
}

// Create one private endpoint per specified sub resource (group)
@batchSize(1)
resource privateEndpoints 'Microsoft.Network/privateEndpoints@2022-09-01' = [
  for pe in privateEndpointInfo: {
    name: replace(namingStructure, '{rtype}', 'st-pe-${pe.subResourceName}')
    location: location
    tags: tags
    properties: {
      subnet: {
        id: privateEndpointSubnetId
      }
      privateLinkServiceConnections: [
        {
          name: replace(namingStructure, '{rtype}', 'st-pe-${pe.subResourceName}')
          properties: {
            privateLinkServiceId: storageAccount.id
            groupIds: [
              pe.subResourceName
            ]
          }
        }
      ]
    }
  }
]

// Register each private endpoint in the respective private DNS zone
@batchSize(1)
resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-09-01' = [
  for (pe, i) in privateEndpointInfo: {
    name: 'default'
    parent: privateEndpoints[i]
    properties: {
      privateDnsZoneConfigs: [
        {
          // Replace . with - because the config name doesn't suppport .
          name: replace(pe.dnsZoneName, '.', '-')
          properties: {
            privateDnsZoneId: pe.dnsZoneId
          }
        }
      ]
    }
  }
]

resource policyExemption 'Microsoft.Authorization/policyExemptions@2022-07-01-preview' = if (createPolicyExemptions && !empty(policyAssignmentId)) {
  name: '${storageAccount.name}-exemption'
  scope: storageAccount
  properties: {
    assignmentScopeValidation: 'Default'
    description: 'This storage account has the public endpoint disabled.'
    displayName: 'Storage Account virtual network service endpoint exemption - ${storageAccount.name}'
    exemptionCategory: 'Mitigated'
    //expiresOn: 'string'
    policyAssignmentId: policyAssignmentId
    policyDefinitionReferenceIds: ['storageAccountsShouldUseAVirtualNetworkServiceEndpoint']
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
output primaryFileEndpoint string = storageAccount.properties.primaryEndpoints.file
// LATER: This will not work with DNS zone based storage accounts
output primaryFileFqdn string = '${storageAccount.name}.file.${az.environment().suffixes.storage}'
