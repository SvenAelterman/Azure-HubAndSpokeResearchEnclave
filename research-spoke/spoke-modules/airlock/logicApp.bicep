param location string
param namingStructure string
param adfName string
@minLength(3)
@maxLength(24)
param prjStorageAcctName string
@minLength(3)
@maxLength(24)
param prjPublicStorageAcctName string
@minLength(3)
@maxLength(24)
param airlockStorageAcctName string
param airlockFileShareName string
param approverEmail string
param sourceFolderPath string
param sinkFolderPath string
param hubCoreKeyVaultUri string

param roles object
param deploymentNameStructure string

param subWorkloadName string
param tags object = {}

var baseName = !empty(subWorkloadName) ? replace(namingStructure, '{subWorkloadName}', subWorkloadName) : replace(namingStructure, '-{subWorkloadName}', '')

// Project's private storage account
resource prjStorageAcct 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: prjStorageAcctName
}

resource adf 'Microsoft.DataFactory/factories@2018-06-01' existing = {
  name: adfName
}

// As of 2022-10-23, Bicep does not have type info for this resource type
#disable-next-line BCP081
resource adfConnection 'Microsoft.Web/connections@2018-07-01-preview' = {
  name: 'api-${adfName}'
  location: location
  properties: {
    displayName: 'Data Factory'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuredatafactory')
    }
    parameterValueType: 'Alternative'
  }
  tags: tags
}

// As of 2022-10-23, Bicep does not have type info for this resource type
#disable-next-line BCP081
resource stgConnection 'Microsoft.Web/connections@2018-07-01-preview' = {
  name: 'api-${prjStorageAcctName}'
  location: location
  properties: {
    displayName: 'Project storage ${prjStorageAcctName}'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
    parameterValueSet: {
      name: 'managedIdentityAuth'
      value: {}
    }
  }
  tags: tags
}

var isAzureUSGov = (az.environment().name == 'AzureUSGovernment')

// As of 2022-10-23, Bicep does not have type info for this resource type
#disable-next-line BCP081
resource emailConnection 'Microsoft.Web/connections@2018-07-01-preview' = {
  name: 'api-office365'
  location: location
  properties: {
    displayName: 'Office 365${isAzureUSGov ? ' GCC-High' : ''}'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
    // This parameterValueSet is only supported when deploying to Azure Gov
    parameterValueSet: isAzureUSGov ? {
      // Per https://learn.microsoft.com/en-us/azure/backup/backup-reports-email?tabs=arm
      name: 'oauthGccHigh'
      values: {
        token: {
          value: 'https://logic-apis-${location}.consent.azure-apihub.us/redirect'
        }
      }
    } : null
  }
  tags: tags
}

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: replace(baseName, '{rtype}', 'logic')
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    definition: json(loadTextContent('./content/logicAppWorkflow.json'))
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            connectionId: stgConnection.id
            connectionName: 'azureblob'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
          }
          azuredatafactory: {
            connectionId: adfConnection.id
            connectionName: 'azuredatafactory'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuredatafactory')
          }
          office365: {
            connectionId: emailConnection.id
            connectionName: 'office365'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
      subscriptionId: {
        value: subscription().subscriptionId
      }
      dataFactoryRG: {
        value: resourceGroup().name
      }
      dataFactoryName: {
        value: adf.name
      }
      sourceStorageAccountName: {
        value: prjStorageAcctName
      }
      sourceFolderPath: {
        value: sourceFolderPath
      }
      sinkStorageAccountName: {
        value: airlockStorageAcctName
      }
      notificationEmail: {
        value: approverEmail
      }
      sinkFileShareName: {
        value: airlockFileShareName
      }
      sinkFolderPath: {
        value: sinkFolderPath
      }
      finalSinkStorageAccountName: {
        value: prjPublicStorageAcctName
      }
      // LATER: Add parameters for pipeline names
      airlockConnStringKvBaseUrl: {
        value: hubCoreKeyVaultUri
      }
      // TODO: Add parameter for source container name (for trigger value)
      exportApprovedContainerName: {
        // LATER: Do not hardcode container name
        value: 'export-approved'
      }
    }
  }
  tags: tags
}

// Set RBAC on ADF for Logic App
module logicAppAdfRbacModule '../../../module-library/roleAssignments/roleAssignment-adf.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'logic-rbac-adf'), 64)
  params: {
    adfName: adf.name
    principalId: logicApp.identity.principalId
    roleDefinitionId: roles.DataFactoryContributor
  }
}

// Set RBAC on project Storage Account for Logic App
module logicAppPrivateStRbacModule '../../../module-library/roleAssignments/roleAssignment-st.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'logic-rbac-st'), 64)
  params: {
    principalId: logicApp.identity.principalId
    roleDefinitionId: roles.StorageBlobDataContributor
    storageAccountName: prjStorageAcct.name
  }
}
