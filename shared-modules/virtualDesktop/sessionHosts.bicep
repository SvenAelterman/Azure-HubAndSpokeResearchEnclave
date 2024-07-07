param location string = resourceGroup().location
param namingStructure string
param tags object

@maxLength(11)
param vmNamePrefix string
param vmCount int
param vmSize string

param diskEncryptionSetId string
param subnetId string

@secure()
param vmLocalAdminUsername string
@secure()
param vmLocalAdminPassword string

@description('Schema: { domainJoinPassword: string, domainJoinUserName: string, adDomainFqdn: string, adOuPath: string }')
//@secure()
param ADDomainInfo activeDirectoryDomainInfo = {
  domainJoinPassword: ''
  domainJoinUsername: ''
  adDomainFqdn: ''
}

param hostPoolName string
@secure()
param hostPoolToken string

param imageReference imageReferenceType = {
  // No image resource ID specified; use a default image
  publisher: 'microsoftwindowsdesktop'
  offer: 'office-365'
  version: 'latest'
  sku: 'win11-23h2-avd-m365'
}

@allowed(['ad', 'entraID'])
param logonType string

param intuneEnrollment bool = false

param deploymentNameStructure string
param backupPolicyName string
param recoveryServicesVaultId string

import { activeDirectoryDomainInfo } from '../types/activeDirectoryDomainInfo.bicep'
import { imageReferenceType } from '../types/imageReferenceType.bicep'

// Nested templates location (not used here, just for reference)
// Commercial: https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/armtemplates/Hostpool_1.0.02544.255/nestedTemplates/
// Azure Gov:  https://wvdportalstorageblob.blob.core.usgovcloudapi.net/galleryartifacts/armtemplates/Hostpool_02-27-2023/nestedTemplates/

// Assumed to be the same between both cloud environments
// Latest as of 2023-12-29
var configurationFileName = 'Configuration_1.0.02544.255.zip'
var artifactsLocation = 'https://wvdportalstorageblob.blob.${az.environment().suffixes.storage}/galleryartifacts/${configurationFileName}'

var intuneMdmId = '0000000a-0000-0000-c000-000000000000'

// Create a new availability set for the session hosts
resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-03-01' = {
  name: replace(namingStructure, '{rtype}', 'avail')
  location: location
  tags: tags
  properties: {
    platformUpdateDomainCount: 5
    platformFaultDomainCount: 2
  }
  sku: {
    name: 'Aligned'
  }
}

// Create the NICs for each session host
resource nics 'Microsoft.Network/networkInterfaces@2022-11-01' = [
  for i in range(0, vmCount): {
    name: replace(namingStructure, '{rtype}', '${computerNames[i]}-nic') // '${vmNamePrefix}${i}-nic'
    location: location
    tags: tags
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig'
          properties: {
            privateIPAllocationMethod: 'Dynamic'
            subnet: {
              id: subnetId
            }
          }
        }
      ]
      // LATER: Some VM sizes don't support this => build a support matrix and use it
      enableAcceleratedNetworking: true
    }
  }
]

var computerNames = [for i in range(0, vmCount): '${vmNamePrefix}-${i}']
var vmNames = [for i in range(0, vmCount): replace(namingStructure, '{rtype}', computerNames[i])]

// Create the session hosts
module sessionHostsModule '../../shared-modules/compute/virtualMachine.bicep' = [
  for i in range(0, vmCount): {
    name: replace(deploymentNameStructure, '{rtype}', 'sh-${computerNames[i]}')
    params: {
      location: location

      tags: tags
      virtualMachineName: vmNames[i]

      vmSize: vmSize
      diskEncryptionSetId: diskEncryptionSetId
      nicId: nics[i].id
      vmLocalAdminUsername: vmLocalAdminUsername
      vmLocalAdminPassword: vmLocalAdminPassword
      domainJoinInfo: ADDomainInfo
      imageReference: imageReference
      logonType: logonType
      intuneEnrollment: intuneEnrollment
      deploymentNameStructure: deploymentNameStructure
      backupPolicyName: backupPolicyName
      recoveryServicesVaultId: recoveryServicesVaultId
      identityType: 'SystemAssigned'
      vmHostName: computerNames[i]
      availabilitySetId: availabilitySet.id
      // An AVD session host is always Windows
      osType: 'Windows'
    }
  }
]

// Deploy the AVD agents to each session host
resource avdAgentDscExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): {
    name: '${vmNames[i]}/AvdAgentDSC'
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Powershell'
      type: 'DSC'
      typeHandlerVersion: '2.73'
      autoUpgradeMinorVersion: true
      settings: {
        modulesUrl: artifactsLocation
        configurationFunction: 'Configuration.ps1\\AddSessionHost'
        properties: {
          hostPoolName: hostPoolName
          registrationInfoTokenCredential: {
            UserName: 'PLACEHOLDER_DO_NOT_USE'
            Password: 'PrivateSettingsRef:RegistrationInfoToken'
          }
          aadJoin: (logonType == 'entraID')
          mdmId: (logonType == 'entraID' && intuneEnrollment) ? intuneMdmId : ''
        }
      }
      protectedSettings: {
        Items: {
          RegistrationInfoToken: hostPoolToken
        }
      }
    }
    // Wait for domain join to complete before registering as a session host
    dependsOn: [
      sessionHostsModule[i]
    ]
  }
]

// for Debug only
output artifactsLocation string = artifactsLocation
