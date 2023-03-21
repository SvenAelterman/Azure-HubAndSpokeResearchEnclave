param namingStructure string
param deploymentNameStructure string
param avdVmHostNameStructure string
param avdSubnetId string
param tags object

@allowed([
  'aad'
  'ad'
])
param sessionHostJoinType string = 'aad'

// LATER: Future use
#disable-next-line no-unused-params
param useSessionHostAsResearchVm bool = false

param environment string = ''
param baseTime string = utcNow('u')
param deployVmsInSeparateRG bool = true
param location string = resourceGroup().location

var avdNamingStructure = replace(namingStructure, '{subwloadname}', 'avd')
var avdVmNamingStructure = replace(namingStructure, '{subwloadname}', deployVmsInSeparateRG ? 'avd-vm' : 'avd')

var defaultHostPoolCustomRdpProperties = 'drivestoredirect:s:0;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:0;redirectprinters:i:0;devicestoredirect:s:0;redirectcomports:i:0;redirectsmartcards:i:1;usbdevicestoredirect:s:0;enablecredsspsupport:i:1;use multimon:i:1;'
var aadJoinCustomRdpProperties = (sessionHostJoinType == 'aad') ? ';targetisaadjoined:i:1' : ''

var hostPoolCustomRdpProperties = '${defaultHostPoolCustomRdpProperties}${aadJoinCustomRdpProperties}'

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2019-12-10-preview' = {
  name: replace(avdNamingStructure, '{rtype}', 'hp')
  location: location
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: 'RailApplications'
    customRdpProperty: hostPoolCustomRdpProperties
    friendlyName: '${environment} Research Enclave Access'
    // LATER: startVMOnConnect requires role configuration
    #disable-next-line BCP037
    startVMOnConnect: true
    registrationInfo: {
      registrationTokenOperation: 'Update'
      // Expire the new registration token in two days
      expirationTime: dateTimeAdd(baseTime, 'P2D')
    }
  }
}

resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2022-04-01-preview' = {
  name: replace(avdNamingStructure, '{rtype}', 'appg')
  location: location
  properties: {
    hostPoolArmPath: hostPool.id
    applicationGroupType: 'RemoteApp'
  }
}

// LATER: Assign AAD groups to application group

resource app 'Microsoft.DesktopVirtualization/applicationGroups/applications@2022-04-01-preview' = {
  name: 'Remote Desktop'
  parent: applicationGroup
  properties: {
    commandLineSetting: 'DoNotAllow'
    applicationType: 'InBuilt'
    friendlyName: 'Remote Desktop'
    filePath: 'C:\\Windows\\System32\\mstsc.exe'
    iconPath: 'C:\\Windows\\System32\\mstsc.exe'
    iconIndex: 0
    showInPortal: true
  }
}

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2022-04-01-preview' = {
  name: replace(avdNamingStructure, '{rtype}', 'ws')
  location: location
  properties: {
    friendlyName: 'Research Enclave Access'
    applicationGroupReferences: [
      applicationGroup.id
    ]
  }
}

// Deploy Azure VMs and join them to the host pool
module avdVM 'avd-vmRG.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'avdvm')
  scope: subscription()
  params: {
    hostPoolRegistrationToken: hostPool.properties.registrationInfo.token
    hostPoolName: hostPool.name
    location: location
    tags: tags
    deploymentNameStructure: deploymentNameStructure
    namingStructure: avdVmNamingStructure
    avdVmHostNameStructure: avdVmHostNameStructure
    avdSubnetId: avdSubnetId
  }
}

// LATER: Create ASG for hosts?
