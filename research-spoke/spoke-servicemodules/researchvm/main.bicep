param location string = resourceGroup().location
param namingStructure string
param tags object

@description('The prefix that will be used for the machine\'s host name.')
@maxLength(13)
param vmNamePrefix string
@minValue(1)
@maxValue(9)
param vmCount int = 1
param vmSize string

param diskEncryptionSetId string = ''
param subnetId string

@secure()
param vmLocalAdminUsername string
@secure()
param vmLocalAdminPassword string

@secure()
param domainJoinPassword string = ''
@secure()
param domainJoinUsername string = ''
param adDomainFqdn string = ''
param adOuPath string = ''

param imageReference imageReferenceType = {
  // No image resource ID specified; use a default image
  publisher: 'microsoftwindowsdesktop'
  offer: 'office-365'
  version: 'latest'
  sku: 'win11-23h2-avd-m365'
}

@allowed(['Windows', 'Linux'])
param osType string

@allowed(['ad', 'entraID'])
param logonType string

@description('When using Entra ID join, specify whether to enroll in Intune also.')
param intuneEnrollment bool = false

param backupPolicyName string
param recoveryServicesVaultId string

param deploymentTime string = utcNow()

param shortcutTargetPath string = ''

import { activeDirectoryDomainInfo } from '../../../shared-modules/types/activeDirectoryDomainInfo.bicep'
import { imageReferenceType } from '../../../shared-modules/types/imageReferenceType.bicep'

var deploymentNameStructure = 'researchvm-{rtype}-${deploymentTime}'

// Create a new availability set for the session hosts
resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-03-01' = if (vmCount > 1) {
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

var computerNames = [for i in range(0, vmCount): '${vmNamePrefix}-${i}']
var vmNames = [for i in range(0, vmCount): replace(namingStructure, '{rtype}', computerNames[i])]

// Create the NICs for each VM
resource nics 'Microsoft.Network/networkInterfaces@2022-11-01' = [
  for i in range(0, vmCount): {
    name: replace(namingStructure, '{rtype}', '${computerNames[i]}-nic')
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

// Create the virtual machines
module virtualMachinesModule '../../../shared-modules/compute/virtualMachine.bicep' = [
  for i in range(0, vmCount): {
    name: take(replace(deploymentNameStructure, '{rtype}', '${computerNames[i]}'), 64)
    params: {
      location: location
      vmHostName: computerNames[i]
      vmLocalAdminUsername: vmLocalAdminUsername
      vmLocalAdminPassword: vmLocalAdminPassword
      diskEncryptionSetId: diskEncryptionSetId
      imageReference: imageReference
      nicId: nics[i].id
      //identityType: logonType == 'entraID' ? 'SystemAssigned' : 'UserAssigned'
      identityType: 'SystemAssigned'
      availabilitySetId: vmCount > 1 ? availabilitySet.id : ''
      deploymentNameStructure: deploymentNameStructure
      domainJoinInfo: logonType == 'ad'
        ? {
            domainJoinPassword: domainJoinPassword
            domainJoinUsername: domainJoinUsername
            adDomainFqdn: adDomainFqdn
            adOuPath: adOuPath
          }
        : null
      logonType: logonType
      intuneEnrollment: intuneEnrollment
      backupPolicyName: backupPolicyName
      recoveryServicesVaultId: recoveryServicesVaultId
      tags: tags
      vmSize: vmSize
      virtualMachineName: vmNames[i]
      osType: osType
    }
  }
]

// Create a shortcut on the desktop to the research data file share
resource shortcutExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): if (!empty(shortcutTargetPath)) {
    name: '${vmNames[i]}/CustomScriptExtension'
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Compute'
      type: 'CustomScriptExtension'
      typeHandlerVersion: '1.10'
      autoUpgradeMinorVersion: true
      settings: {
        commandToExecute: 'powershell -ExecutionPolicy Unrestricted ${replace(loadTextContent('../../../scripts/PowerShell/Scripts/RVM/Windows/New-FileShareDesktopShortcut.ps1'), '$TargetPath', shortcutTargetPath)}'
      }
    }
    dependsOn: [
      virtualMachinesModule[i]
    ]
  }
]
