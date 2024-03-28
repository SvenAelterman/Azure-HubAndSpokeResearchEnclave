targetScope = 'subscription'

param resourceGroupName string

param adminObjectId string
param userObjectId string
param deploymentNameStructure string
param desktopAppGroupFriendlyName string
param logonType string
param privateLinkDnsZoneId string = ''
param workspaceFriendlyName string
param namingStructure string
param usePrivateLinkForHostPool bool = true
param privateEndpointSubnetId string

param computeSubnetId string

param sessionHostCount int = 0
param sessionHostNamePrefix string
param sessionHostSize string

param adOuPath string = ''
param adDomainFqdn string = ''

@secure()
param domainJoinUsername string
@secure()
param domainJoinPassword string

@secure()
param sessionHostLocalAdminUsername string
@secure()
param sessionHostLocalAdminPassword string

@description('Required when using CMK.')
param diskEncryptionSetId string = ''

param useCMK bool

param recoveryServicesVaultId string
param backupPolicyName string

param roles object
param location string
param tags object

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module avdModule 'avd.bicep' = {
  scope: resourceGroup
  name: take(replace(deploymentNameStructure, '{rtype}', 'avd'), 64)
  params: {
    location: location
    adminObjectId: adminObjectId
    deploymentNameStructure: deploymentNameStructure
    desktopAppGroupFriendlyName: desktopAppGroupFriendlyName
    logonType: logonType
    namingStructure: namingStructure
    privateEndpointSubnetId: privateEndpointSubnetId
    privateLinkDnsZoneId: privateLinkDnsZoneId
    roles: roles
    tags: tags
    workspaceFriendlyName: workspaceFriendlyName
    usePrivateLinkForHostPool: usePrivateLinkForHostPool
    userObjectId: userObjectId
  }
}

var useADDomainInformation = (logonType == 'ad')

module sessionHostModule 'sessionHosts.bicep' =
  if (sessionHostCount > 0) {
    scope: resourceGroup
    name: take(replace(deploymentNameStructure, '{rtype}', 'avd-sh'), 64)
    params: {
      namingStructure: namingStructure
      subnetId: computeSubnetId
      tags: tags
      location: location
      diskEncryptionSetId: useCMK ? diskEncryptionSetId : ''

      hostPoolName: avdModule.outputs.hostPoolName
      hostPoolToken: avdModule.outputs.hostPoolRegistrationToken

      vmLocalAdminPassword: sessionHostLocalAdminPassword
      vmLocalAdminUsername: sessionHostLocalAdminUsername

      vmCount: sessionHostCount
      vmNamePrefix: sessionHostNamePrefix
      vmSize: sessionHostSize

      logonType: logonType
      ADDomainInfo: useADDomainInformation
        ? {
            domainJoinPassword: domainJoinPassword
            domainJoinUsername: domainJoinUsername
            adDomainFqdn: adDomainFqdn
            adOuPath: adOuPath
          }
        : null

      deploymentNameStructure: deploymentNameStructure
      recoveryServicesVaultId: recoveryServicesVaultId
      backupPolicyName: backupPolicyName
    }
  }
