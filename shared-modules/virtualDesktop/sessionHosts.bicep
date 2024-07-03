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

// TODO: Use virtualMachine.bicep shared module
// Create the session hosts
resource sessionHosts 'Microsoft.Compute/virtualMachines@2023-03-01' = [
  for i in range(0, vmCount): {
    name: replace(namingStructure, '{rtype}', computerNames[i])
    location: location
    tags: tags
    properties: {
      // TODO: Consider adding licenseType: 'Windows_Client' (when using default image)
      // LATER: Support for hibernation: additionalCapabilities: { hibernationEnabled: }
      hardwareProfile: {
        vmSize: vmSize
      }
      osProfile: {
        computerName: computerNames[i]
        adminUsername: vmLocalAdminUsername
        adminPassword: vmLocalAdminPassword
        windowsConfiguration: {
          // LATER: If leveraging Azure Update Manager, configure for compatibility
          enableAutomaticUpdates: true
        }
      }
      securityProfile: {
        encryptionAtHost: true
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          osType: 'Windows'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
            // TODO: Only when using CMK
            diskEncryptionSet: {
              id: diskEncryptionSetId
            }
          }
        }
        imageReference: imageReference
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: nics[i].id
          }
        ]
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: false
        }
      }
      availabilitySet: {
        id: availabilitySet.id
      }
    }
    // Entra ID join requires a system-assigned identity for the VM
    identity: (logonType == 'entraID')
      ? {
          type: 'SystemAssigned'
        }
      : null
  }
]

// Deploy the AVD agents to each session host
resource avdAgentDscExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): {
    name: 'AvdAgentDSC'
    parent: sessionHosts[i]
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
      domainJoinExtension[i]
      entraIDJoinExtension[i]
    ]
  }
]

// Entra ID join, if specified
resource entraIDJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): if (logonType == 'entraID') {
    name: 'EntraIDJoin'
    parent: sessionHosts[i]
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Azure.ActiveDirectory'
      type: 'AADLoginForWindows'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
      settings: intuneEnrollment
        ? {
            mdmId: intuneMdmId
          }
        : null
    }
    dependsOn: [windowsGuestAttestationExtension[i], windowsVMGuestConfigExtension[i]]
  }
]

// Domain join the session hosts to Active Directory, if specified
resource domainJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): if (logonType == 'ad' && !empty(ADDomainInfo)) {
    name: 'DomainJoin'
    parent: sessionHosts[i]
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Compute'
      type: 'JsonADDomainExtension'
      typeHandlerVersion: '1.3'
      autoUpgradeMinorVersion: true
      settings: {
        name: ADDomainInfo.adDomainFqdn
        ouPath: ADDomainInfo.adOuPath
        user: ADDomainInfo.domainJoinUsername
        restart: 'true'
        options: '3'
      }
      protectedSettings: {
        password: ADDomainInfo.domainJoinPassword
      }
    }
    dependsOn: [windowsGuestAttestationExtension[i], windowsVMGuestConfigExtension[i]]
  }
]

// Deploy Windows Attestation, for boot integrity monitoring
resource windowsGuestAttestationExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): {
    name: 'WindowsGuestAttestation'
    parent: sessionHosts[i]
    location: location
    tags: tags
    properties: {
      publisher: 'Microsoft.Azure.Security.WindowsAttestation'
      type: 'GuestAttestation'
      typeHandlerVersion: '1.0'
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
      settings: {
        AttestationConfig: {
          MaaSettings: {
            maaEndpoint: ''
            maaTenantName: 'GuestAttestation'
          }
          AscSettings: {
            ascReportingEndpoint: ''
            ascReportingFrequency: ''
          }
          useCustomToken: false
          disableAlerts: false
        }
      }
    }
  }
]

// Deploy the Windows VM Guest Configuration extension which is required for most regulatory compliance initiatives
resource windowsVMGuestConfigExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): {
    name: 'AzurePolicyforWindows'
    parent: sessionHosts[i]
    location: location
    properties: {
      publisher: 'Microsoft.GuestConfiguration'
      type: 'ConfigurationforWindows'
      typeHandlerVersion: '1.0'
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
      settings: {}
      protectedSettings: {}
    }
  }
]

// LATER: Deploy NVIDIA or AMD drivers if needed, based on vmSize

var rsvRgName = !empty(recoveryServicesVaultId) ? split(recoveryServicesVaultId, '/')[4] : ''

// Create a backup item for each session host
// This must be deployed in a separate module because it's in a different resource group
module backupItems '../recovery/rsvProtectedItem.bicep' = [
  for i in range(0, vmCount): if (!empty(backupPolicyName) && !empty(recoveryServicesVaultId)) {
    name: replace(deploymentNameStructure, '{rtype}', '${computerNames[i]}-backup')
    scope: resourceGroup(rsvRgName)
    params: {
      backupPolicyName: backupPolicyName
      recoveryServicesVaultId: recoveryServicesVaultId
      virtualMachineId: sessionHosts[i].id
    }
  }
]

// for Debug only
output artifactsLocation string = artifactsLocation
