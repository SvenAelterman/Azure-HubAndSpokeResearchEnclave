param location string = resourceGroup().location
param namingStructure string
param tags object

@description('The prefix that will be used for the machine\'s host name.')
@maxLength(15)
param vmNamePrefix string
param vmSize string = 'Standard_B2ats_v2'

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
  publisher: 'MicrosoftWindowsDesktop'
  offer: 'Windows-11'
  sku: 'win11-23h2-avd'
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

// Create the NICs for each VM
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

// Create the virtual machines
resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: replace(namingStructure, '{rtype}', vmNamePrefix)
  location: location
  tags: tags
  properties: {
    // TODO: Consider adding licenseType: 'Windows_Client' (when using default image)
    // LATER: Support for hibernation: additionalCapabilities: { hibernationEnabled: }
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmNamePrefix
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
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
  // Entra ID join requires a system-assigned identity for the VM
  identity: (logonType == 'entraID')
    ? {
        type: 'SystemAssigned'
      }
    : null
}

// Entra ID join, if specified
resource entraIDJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (logonType == 'entraID') {
  name: 'EntraIDJoin'
  parent: virtualMachine
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
  dependsOn: [windowsGuestAttestationExtension, windowsVMGuestConfigExtension]
}

// Domain join the session hosts to Active Directory, if specified
resource domainJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (logonType == 'ad') {
  name: 'DomainJoin'
  parent: virtualMachine
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      name: adDomainFqdn
      ouPath: adOuPath
      user: domainJoinUsername
      restart: 'true'
      options: '3'
    }
    protectedSettings: {
      password: domainJoinPassword
    }
  }
  dependsOn: [windowsGuestAttestationExtension, windowsVMGuestConfigExtension]
}

// Deploy Windows Attestation, for boot integrity monitoring
resource windowsGuestAttestationExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: 'WindowsGuestAttestation'
  parent: virtualMachine
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

// Deploy the Windows VM Guest Configuration extension which is required for most regulatory compliance initiatives
resource windowsVMGuestConfigExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: 'AzurePolicyforWindows'
  parent: virtualMachine
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

var rsvRgName = !empty(recoveryServicesVaultId) ? split(recoveryServicesVaultId, '/')[4] : ''

// Create a backup item for each session host
// This must be deployed in a separate module because it's in a different resource group
module backupItems '../../../shared-modules/recovery/rsvProtectedItem.bicep' = if (!empty(backupPolicyName) && !empty(recoveryServicesVaultId)) {
  name: replace(deploymentNameStructure, '{rtype}', '${vmNamePrefix}-backup')
  scope: resourceGroup(rsvRgName)
  params: {
    backupPolicyName: backupPolicyName
    recoveryServicesVaultId: recoveryServicesVaultId
    virtualMachineId: virtualMachine.id
  }
}
