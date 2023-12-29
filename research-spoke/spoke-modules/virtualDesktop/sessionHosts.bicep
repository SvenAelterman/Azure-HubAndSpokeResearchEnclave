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
@secure()
param domainJoinUsername string
@secure()
param domainJoinPassword string

param adDomainFqdn string
param adOuPath string

param hostPoolName string
@secure()
param hostPoolToken string

param vmImageResourceId string = ''

// Nested templates location (not used here, just for reference)
// https://wvdportalstorageblob.blob.core.usgovcloudapi.net/galleryartifacts/armtemplates/Hostpool_02-27-2023/nestedTemplates/

// Assumed to be the same between both cloud environments
// Latest as of 2023-05-10
var configurationFileName = 'Configuration_01-19-2023.zip'

var artifactsLocation = 'https://wvdportalstorageblob.blob.${az.environment().suffixes.storage}/galleryartifacts/${configurationFileName}'

// Create a new availability set for these virtual machines
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

resource nics 'Microsoft.Network/networkInterfaces@2022-11-01' = [for i in range(0, vmCount): {
  name: '${vmNamePrefix}${i}-nic'
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
    // HACK: Change from original
    enableAcceleratedNetworking: true
  }
}]

resource sessionHosts 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, vmCount): {
  name: '${vmNamePrefix}${i}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${vmNamePrefix}${i}'
      adminUsername: vmLocalAdminUsername
      adminPassword: vmLocalAdminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        // patchSettings: {
        //   assessmentMode: 'AutomaticByPlatform'
        //   automaticByPlatformSettings: {
        //     rebootSetting: 'Always'
        //   }
        //}
        // HACK: Ommitting timezone; should be set with AVD group policy setting
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
          // HACK: Changed from PremiumSSD_LRS
          storageAccountType: 'StandardSSD_LRS'
          diskEncryptionSet: {
            id: diskEncryptionSetId
          }
        }
      }
      imageReference: !empty(vmImageResourceId) ? {
        id: vmImageResourceId
      } : {
        // No image resource ID specified; use a default image
        publisher: 'microsoftwindowsdesktop'
        offer: 'office-365'
        version: 'latest'
        sku: 'win10-22h2-avd-m365-g2'
      }
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
        // HACK: change from original (bootDiag off)
        enabled: false
      }
    }
    availabilitySet: {
      id: availabilitySet.id
    }
  }
}]

// Deploy the AVD agents to each session host
resource avdAgentDscExtension 'Microsoft.Compute/virtualMachines/extensions@2018-10-01' = [for i in range(0, vmCount): {
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
        registrationInfoToken: hostPoolToken
        aadJoin: false
      }
    }
  }
}]

resource domainJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2018-10-01' = [for i in range(0, vmCount): {
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
  dependsOn: [
    avdAgentDscExtension[i]
  ]
}]

resource windowsVMGuestConfigExtension 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = [for i in range(0, vmCount): {
  parent: sessionHosts[i]
  name: 'AzurePolicyforWindows'
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
}]

// LATER: Deploy NVIDIA or AMD drivers if needed, based on vmSize

// for Debug only
output artifactsLocation string = artifactsLocation
