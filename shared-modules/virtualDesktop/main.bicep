targetScope = 'subscription'

param resourceGroupName string

param adminObjectId string
param userObjectIds string[]
param deploymentNameStructure string
param desktopAppGroupFriendlyName string
param logonType string
param privateLinkDnsZoneId string = ''
param workspaceFriendlyName string
param namingStructure string
param usePrivateLinkForHostPool bool = true
param privateEndpointSubnetId string

param computeSubnetId string

param useSessionHostConfiguration bool = false // Defaults to false for backward compatibility.

param sessionHostCount int = 0
param sessionHostNamePrefix string
param sessionHostSize string

param adDomainJoinInfo activeDirectoryDomainInfo?

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

param enableAvmTelemetry bool

param sessionHostResourceGroupName string

// Session Host configuration only
param domainJoinCredentialKeyVaultSecretUris credentialKeyVaultSecretUrisType?
param localCredentialKeyVaultSecretUris credentialKeyVaultSecretUrisType?

import { credentialKeyVaultSecretUrisType } from '../types/credentialKeyVaultSecretUrisType.bicep'
import { activeDirectoryDomainInfo } from '../types/activeDirectoryDomainInfo.bicep'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

resource sessionHostResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = if (resourceGroupName != sessionHostResourceGroupName) {
  name: sessionHostResourceGroupName
  location: location
  tags: tags
}

module avdModule 'avd.bicep' = {
  scope: resourceGroup
  #disable-next-line BCP334
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
    userObjectIds: userObjectIds

    useSessionHostConfiguration: useSessionHostConfiguration
    sessionHostSize: sessionHostSize
    adDomainFqdn: adDomainJoinInfo.?adDomainFqdn
    adOuPath: adDomainJoinInfo.?adOuPath
    domainJoinCredentialKeyVaultSecretUris: domainJoinCredentialKeyVaultSecretUris
    localCredentialKeyVaultSecretUris: localCredentialKeyVaultSecretUris
    subnetId: computeSubnetId
    vmNamePrefix: sessionHostNamePrefix
    sessionHostCount: sessionHostCount

    sessionHostResourceGroupName: sessionHostResourceGroup.name // Creates an implicit dependency

    enableAvmTelemetry: enableAvmTelemetry
  }
}

var useADDomainInformation = (logonType == 'ad')

module sessionHostModule 'sessionHosts.bicep' = if (!useSessionHostConfiguration && sessionHostCount > 0) {
  scope: resourceGroup
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'avd-sh'), 64)
  params: {
    namingStructure: namingStructure
    subnetId: computeSubnetId
    tags: tags
    location: location
    diskEncryptionSetId: useCMK ? diskEncryptionSetId : ''

    hostPoolName: avdModule.outputs.hostPoolName
    hostPoolToken: avdModule.outputs.?hostPoolRegistrationToken

    vmLocalAdminPassword: sessionHostLocalAdminPassword
    vmLocalAdminUsername: sessionHostLocalAdminUsername

    vmCount: sessionHostCount
    vmNamePrefix: sessionHostNamePrefix
    vmSize: sessionHostSize

    logonType: logonType
    ADDomainInfo: useADDomainInformation ? adDomainJoinInfo : null

    deploymentNameStructure: deploymentNameStructure
    recoveryServicesVaultId: recoveryServicesVaultId
    backupPolicyName: backupPolicyName
  }
}
