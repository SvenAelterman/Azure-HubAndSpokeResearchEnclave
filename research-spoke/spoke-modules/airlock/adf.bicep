// Required parameters
param location string
param namingStructure string
param tags object
param deploymentNameStructure string
param subWorkloadName string
param privateStorageAcctName string
param userAssignedIdentityId string
param userAssignedIdentityPrincipalId string
param privateStorageAccountConnStringSecretName string

param roles object

param keyVaultName string
param keyVaultResourceGroupName string

param encryptionUserAssignedIdentityId string
param encryptionKeyVaultUri string

param adfEncryptionKeyName string

param pipelineNameAdls2Files string = 'pipe-data_move-adls_to_files'
param pipelineNameFilesToAdls string = 'pipe-data_move-files_to_adls'
param debugMode bool

var baseName = !empty(subWorkloadName) ? replace(namingStructure, '{subWorkloadName}', subWorkloadName) : replace(namingStructure, '-{subWorkloadName}', '')

var managedVnetName = 'default'
var autoResolveIntegrationRuntimeName = 'AutoResolveIntegrationRuntime'
var adlsGen2LinkedServiceName = 'ls_ADLSGen2_Generic'
var azFilesLinkedServiceName = 'ls_AzFiles_Generic'
var kvLinkedServiceName = 'ls_KeyVault'

resource privateStorageAcct 'Microsoft.Storage/storageAccounts@2021-08-01' existing = {
  name: privateStorageAcctName
}

// The Key Vault where ADF can get the connection string for the Azure File Share linked service
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroupName)
}

resource adf 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: replace(baseName, '{rtype}', 'adf')
  location: location
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${encryptionUserAssignedIdentityId}': {}
    }
  }
  properties: {
    encryption: {
      keyName: adfEncryptionKeyName
      vaultBaseUrl: encryptionKeyVaultUri
      identity: {
        userAssignedIdentity: encryptionUserAssignedIdentityId
      }
    }
  }
  tags: tags
}

// Assign roles to UAMI to enable making modifications to ADF (start, stop) and approve private endpoints
resource adfRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(adf.id, userAssignedIdentityPrincipalId, roles['Data Factory Contributor'])
  scope: adf
  properties: {
    roleDefinitionId: roles['Data Factory Contributor']
    principalId: userAssignedIdentityPrincipalId
  }
}

// Stop the ADF triggers, required to be able to make changes to the pipelines, etc.
module stopTriggersDeploymentScriptModule 'deploymentScript.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'dplscr-StopTriggers')
  params: {
    location: location
    subWorkloadName: 'StopTriggers'
    namingStructure: namingStructure
    arguments: '-ResourceGroupName ${resourceGroup().name} -AzureDataFactoryName ${adf.name} -SubscriptionId ${subscription().subscriptionId}'
    scriptContent: loadTextContent('./content/StopAdfTriggers.ps1')
    userAssignedIdentityId: userAssignedIdentityId
    tags: tags
    debugMode: debugMode
  }
}

resource managedVnet 'Microsoft.DataFactory/factories/managedVirtualNetworks@2018-06-01' = {
  name: managedVnetName
  parent: adf
  properties: {}
}

resource integrationRuntime 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  name: autoResolveIntegrationRuntimeName
  parent: adf
  dependsOn: [
    managedVnet
  ]
  properties: {
    type: 'Managed'
    managedVirtualNetwork: {
      type: 'ManagedVirtualNetworkReference'
      referenceName: managedVnetName
    }
    typeProperties: {
      computeProperties: {
        location: 'AutoResolve'
      }
    }
  }
}

// RBAC role assignment for ADF to Key Vault
module adfKeyVaultRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-kv-secret.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rbac-adf-kv-st'), 64)
  scope: resourceGroup(keyVaultResourceGroupName)
  params: {
    principalId: adf.identity.principalId
    roleDefinitionId: roles.KeyVaultSecretsUser
    kvName: keyVault.name
    secretName: privateStorageAccountConnStringSecretName
  }
}

// Linked service for Key Vault, used by File Share linked service to get connection string
resource keyVaultLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: kvLinkedServiceName
  parent: adf
  dependsOn: [
    adfKeyVaultRoleAssignmentModule
  ]
  properties: {
    type: 'AzureKeyVault'
    typeProperties: {
      baseUrl: '@{linkedService().baseUrl}'
    }
    parameters: {
      baseUrl: {
        type: 'String'
      }
    }
  }
}

resource genericLinkedServiceAdlsGen2 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: adlsGen2LinkedServiceName
  parent: adf
  dependsOn: [
    integrationRuntime
  ]
  properties: {
    type: 'AzureBlobFS'
    typeProperties: {
      url: '@{concat(\'https://\', linkedService().storageAccountName, \'.dfs.${environment().suffixes.storage}\')}'
    }
    connectVia: {
      referenceName: autoResolveIntegrationRuntimeName
      type: 'IntegrationRuntimeReference'
    }
    parameters: {
      storageAccountName: {
        type: 'String'
      }
    }
  }
}

resource genericLinkedServiceAzFiles 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: azFilesLinkedServiceName
  parent: adf
  dependsOn: [
    integrationRuntime
    adfKeyVaultRoleAssignmentModule
    keyVaultLinkedService
  ]
  properties: {
    type: 'AzureFileStorage'
    typeProperties: {
      fileShare: '@{linkedService().fileShareName}'
      connectionString: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: kvLinkedServiceName
          type: 'LinkedServiceReference'
          parameters: {
            baseUrl: {
              type: 'Expression'
              value: '@linkedService().kvBaseUrl'
            }
          }
        }
        secretName: {
          type: 'Expression'
          value: '@{concat(linkedService().storageAccountName, \'-connstring1\')}'
        }
      }
    }
    parameters: {
      storageAccountName: {
        type: 'String'
      }
      fileShareName: {
        type: 'String'
      }
      kvBaseUrl: {
        type: 'String'
      }
    }
    connectVia: {
      referenceName: autoResolveIntegrationRuntimeName
      type: 'IntegrationRuntimeReference'
    }
  }
}

// Create Azure Files dataset
resource AzFilesDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: 'AzFilesDataset'
  parent: adf
  properties: {
    linkedServiceName: {
      referenceName: genericLinkedServiceAzFiles.name
      type: 'LinkedServiceReference'
      parameters: {
        storageAccountName: {
          type: 'Expression'
          value: '@dataset().storageAccountName'
        }
        fileShareName: {
          type: 'Expression'
          value: '@dataset().fileShareName'
        }
        kvBaseUrl: {
          type: 'Expression'
          value: '@dataset().connStringKvBaseUrl'
        }
      }
    }
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'AzureFileStorageLocation'
        folderPath: {
          type: 'Expression'
          value: '@dataset().folderPath'
        }
        fileName: {
          type: 'Expression'
          value: '@dataset().fileName'
        }
      }
    }
    parameters: {
      fileName: {
        type: 'String'
      }
      storageAccountName: {
        type: 'String'
      }
      folderPath: {
        type: 'String'
      }
      fileShareName: {
        type: 'String'
      }
      connStringKvBaseUrl: {
        type: 'String'
      }
    }
  }
}

resource dfsDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: 'DfsDataset'
  parent: adf
  properties: {
    type: 'Binary'
    linkedServiceName: {
      referenceName: genericLinkedServiceAdlsGen2.name
      type: 'LinkedServiceReference'
      parameters: {
        storageAccountName: {
          value: '@dataset().storageAccountName'
          type: 'Expression'
        }
      }
    }
    parameters: {
      storageAccountName: {
        type: 'String'
      }
      folderPath: {
        type: 'String'
      }
      fileName: {
        type: 'String'
      }
    }
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileName: {
          value: '@dataset().fileName'
          type: 'Expression'
        }
        fileSystem: {
          value: '@dataset().folderPath'
          type: 'Expression'
        }
      }
    }
  }
}

resource pipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: pipelineNameAdls2Files
  parent: adf
  properties: {
    // The pipeline's activity definitions are stored in a JSON file to keep this file readable
    activities: loadJsonContent('./content/adfPipeline-Blob2Files.json')
    parameters: {
      sourceStorageAccountName: {
        type: 'String'
      }
      sinkStorageAccountName: {
        type: 'String'
      }
      sourceFolderPath: {
        type: 'String'
      }
      sinkFolderPath: {
        type: 'String'
      }
      fileName: {
        type: 'String'
      }
      sinkFileShareName: {
        type: 'String'
      }
      sinkConnStringKvBaseUrl: {
        type: 'String'
      }
    }
  }
  dependsOn: [
    dfsDataset
    AzFilesDataset
  ]
}

resource pipelineFilesToAdls 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: pipelineNameFilesToAdls
  parent: adf
  properties: {
    activities: loadJsonContent('./content/adfPipeline-Files2ADLS.json')
    parameters: {
      sourceStorageAccountName: {
        type: 'String'
      }
      sinkStorageAccountName: {
        type: 'String'
      }
      sourceFolderPath: {
        type: 'String'
      }
      sinkFolderPath: {
        type: 'String'
      }
      fileName: {
        type: 'String'
      }
      sourceFileShareName: {
        type: 'String'
      }
      sourceConnStringKvBaseUrl: {
        type: 'String'
      }
    }
  }
  dependsOn: [
    AzFilesDataset
    dfsDataset
  ]
}

// LATER: Abstract to storage-RoleAssignment module
var storageAccountRoleDefinitionId = roles.StorageBlobDataContributor

// Grant the ADF the Storage Blob Data Contributor role on the private storage account
resource adfPrivateStgRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // LATER: Fix name by combining object, subject, and role ID
  name: guid('${privateStorageAcct.name}-${adf.name}-StorageBlobDataContributor')
  scope: privateStorageAcct
  properties: {
    roleDefinitionId: storageAccountRoleDefinitionId
    principalId: adf.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output principalId string = adf.identity.principalId
output name string = adf.name
// LATER: Rename output pipeline name
output pipelineName string = pipelineNameAdls2Files
output pipelineNameFilesToAdls string = pipelineNameFilesToAdls
