param storageAccountName string
param location string = resourceGroup().location
param tags object
@description('The user-assigned managed identity to access the customer-managed encryption key (CMK).')
param uamiId string
@description('Name of the customer-managed encryption key in Key Vault.')
param encryptionKeyName string
@description('URI of the Key Vault where the customer-managed encryption key is stored.')
param keyVaultUri string
param namingStructure string
param privateEndpointSubnetId string

@description('An array of objects with the following schema: { subResourceName: string, dnsZoneName: string, dnsZoneId: string }')
param privateEndpointInfo array
@description('An array of valid SMB file share names to create.')
param fileShareNames array
@description('An array of valid Blob container names to create.')
param containerNames array

@description('The type of identity to use for identity-based authentication for Azure Files. Valid values are: AADDS, or AADKERB. AD to follow later.')
@allowed([ 'AADDS', 'AADKERB', 'None' ])
param filesIdentityType string

param debugMode bool = false
param debugRemoteIp string = ''
param applyDeleteLock bool = !debugMode

param allowedIpAddresses array = []

// If debug mode is enabled, deploy an IP rule for the debug IP address; otherwise, just use the specified list
// This will automatically deduplicate
var actualAllowedIpAddresses = debugMode ? concat(allowedIpAddresses, array(debugRemoteIp)) : allowedIpAddresses

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_GRS'
  }
  kind: 'StorageV2'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    publicNetworkAccess: !debugMode && empty(actualAllowedIpAddresses) ? 'Disabled' : 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true

    networkAcls: {
      resourceAccessRules: []
      // TODO: Verify if this is needed / Replace with instance rules
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: [for allowedIp in actualAllowedIpAddresses: {
        value: allowedIp
        action: 'Allow'
      }]
      defaultAction: 'Deny'
    }

    // TODO: Allow for any of three authentication methods: Entra ID, AADDS, or AD DS
    azureFilesIdentityBasedAuthentication: (filesIdentityType == 'None') ? null : {
      directoryServiceOptions: filesIdentityType
      defaultSharePermission: 'None'
    }

    supportsHttpsTrafficOnly: true

    // TODO: Modify if CMK is not required
    encryption: {
      requireInfrastructureEncryption: true
      identity: {
        userAssignedIdentity: uamiId
      }
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyname: encryptionKeyName
        keyvaulturi: keyVaultUri
      }
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
resource fileShares 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = [for shareName in fileShareNames: {
  name: shareName
  parent: fileService
  properties: {
    enabledProtocols: 'SMB'
  }
}]

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = [for containerName in containerNames: {
  name: containerName
  parent: blobService
}]

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
resource privateEndpoints 'Microsoft.Network/privateEndpoints@2022-09-01' = [for pe in privateEndpointInfo: {
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
}]

// Register the private endpoint in the respective private DNS zone
@batchSize(1)
resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-09-01' = [for (pe, i) in privateEndpointInfo: {
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
}]

output id string = storageAccount.id
output name string = storageAccount.name
