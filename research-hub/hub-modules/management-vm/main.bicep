param location string = resourceGroup().location
param namingStructure string
param tags object

@description('The prefix that will be used for the machine\'s host name.')
@maxLength(15)
param vmNamePrefix string
param vmSize string = 'Standard_B2as_v2'

param diskEncryptionSetId string = ''
param subnetId string

@secure()
param vmLocalAdminUsername string
@secure()
param vmLocalAdminPassword string

param domainJoinInfo activeDirectoryDomainInfo = {
  adDomainFqdn: ''
  domainJoinPassword: ''
  domainJoinUsername: ''
  adOuPath: ''
}

param imageReference imageReferenceType = {
  // No image resource ID specified; use a default image
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter-smalldisk-g2'
  version: 'latest'
}

// A management VM is primarily intended to support automation of AD join
@allowed(['ad', 'entraID'])
param logonType string = 'ad'

@description('When using Entra ID join, specify whether to enroll in Intune also.')
param intuneEnrollment bool = false

// Do not backup by default
param backupPolicyName string = ''
param recoveryServicesVaultId string = ''

param deploymentTime string = utcNow()

import { activeDirectoryDomainInfo } from '../../../shared-modules/types/activeDirectoryDomainInfo.bicep'

type imageReferenceType = {
  publisher: string?
  offer: string?
  version: string?
  sku: string?
  id: string?
}

var deploymentNameStructure = 'managementvm-{rtype}-${deploymentTime}'

// Entra ID join requires a system-assigned identity for the VM
// Always need UserAssigned for AD domain join
var identityType = logonType == 'entraID' ? 'SystemAssigned, UserAssigned' : 'UserAssigned'

// Create a user-assigned managed identity for the VM
// This identity will be granted Storage Account Contributor in the spokes to support AD domain join of spoke storage accounts
module uamiModule '../../../shared-modules/security/uami.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami'), 64)
  params: {
    uamiName: replace(namingStructure, '{rtype}', 'uami')
    location: location
    tags: tags
  }
}

// Create the NIC
resource nic 'Microsoft.Network/networkInterfaces@2022-11-01' = {
  name: replace(namingStructure, '{rtype}', '${vmNamePrefix}-nic')
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

// Create the virtual machine
module virtualMachineModule '../../../shared-modules/compute/virtualMachine.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'vm'), 64)
  params: {
    virtualMachineName: replace(namingStructure, '{rtype}', vmNamePrefix)
    location: location
    vmComputerNamePrefix: vmNamePrefix
    vmSize: vmSize
    vmLocalAdminUsername: vmLocalAdminUsername
    vmLocalAdminPassword: vmLocalAdminPassword
    uamiId: uamiModule.outputs.id
    identityType: identityType
    imageReference: imageReference
    nicId: nic.id
    diskEncryptionSetId: diskEncryptionSetId
    intuneEnrollment: intuneEnrollment
    logonType: logonType
    deploymentNameStructure: deploymentNameStructure
    backupPolicyName: backupPolicyName
    recoveryServicesVaultId: recoveryServicesVaultId

    domainJoinInfo: domainJoinInfo

    tags: tags
  }
}

output uamiId string = uamiModule.outputs.id
output uamiPrincipalId string = uamiModule.outputs.principalId
output uamiClientId string = uamiModule.outputs.clientId
