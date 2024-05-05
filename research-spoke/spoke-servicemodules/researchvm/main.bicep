param location string = resourceGroup().location
param namingStructure string
param tags object

@maxLength(13)
param vmNamePrefix string
@minValue(1)
param vmCount int = 1
param vmSize string

param diskEncryptionSetId string = ''
param subnetId string

@secure()
param vmLocalAdminUsername string
@secure()
param vmLocalAdminPassword string

@description('Schema: { domainJoinPassword: string, domainJoinUserName: string, adDomainFqdn: string, adOuPath: string }')
param ADDomainInfo activeDirectoryDomainInfo = {
  domainJoinPassword: ''
  domainJoinUsername: ''
  adDomainFqdn: ''
  adOuPath: ''
}

param imageReference imageReferenceType = {
  // No image resource ID specified; use a default image
  publisher: 'microsoftwindowsdesktop'
  offer: 'office-365'
  version: 'latest'
  sku: 'win11-23h2-avd-m365'
}

@allowed(['ad', 'entraID'])
param logonType string

@description('When using Entra ID join, specify whether to enroll in Intune also.')
param intuneEnrollment bool = false

param backupPolicyName string
param recoveryServicesVaultId string

param deploymentTime string = utcNow()

type activeDirectoryDomainInfo = {
  @secure()
  domainJoinPassword: string
  @secure()
  domainJoinUsername: string
  adDomainFqdn: string
  adOuPath: string?
}

type imageReferenceType = {
  publisher: string?
  offer: string?
  version: string?
  sku: string?
  id: string?
}

var intuneMdmId = '0000000a-0000-0000-c000-000000000000'
var deploymentNameStructure = 'researchvm-{rtype}-${deploymentTime}'

// Create a new availability set for the session hosts
resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-03-01' =
  if (vmCount > 1) {
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
resource virtualMachines 'Microsoft.Compute/virtualMachines@2023-03-01' = [
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
        // TODO: Only if osType == Windows
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
          // TODO: Make a parameter
          osType: 'Windows'
          managedDisk: {
            // TODO: Make a parameter
            storageAccountType: 'StandardSSD_LRS'
            diskEncryptionSet: !empty(diskEncryptionSetId)
              ? {
                  id: diskEncryptionSetId
                }
              : null
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
      availabilitySet: vmCount > 1
        ? {
            id: availabilitySet.id
          }
        : null
    }
    // Entra ID join requires a system-assigned identity for the VM
    identity: (logonType == 'entraID')
      ? {
          type: 'SystemAssigned'
        }
      : null
  }
]

// Entra ID join, if specified
resource entraIDJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for i in range(0, vmCount): if (logonType == 'entraID') {
    name: 'EntraIDJoin'
    parent: virtualMachines[i]
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
    parent: virtualMachines[i]
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
    parent: virtualMachines[i]
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
    parent: virtualMachines[i]
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
module backupItems '../../../shared-modules/recovery/rsvProtectedItem.bicep' = [
  for i in range(0, vmCount): if (!empty(backupPolicyName) && !empty(recoveryServicesVaultId)) {
    name: replace(deploymentNameStructure, '{rtype}', '${computerNames[i]}-backup')
    scope: resourceGroup(rsvRgName)
    params: {
      backupPolicyName: backupPolicyName
      recoveryServicesVaultId: recoveryServicesVaultId
      virtualMachineId: virtualMachines[i].id
    }
  }
]
