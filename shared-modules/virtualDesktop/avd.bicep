param namingStructure string
param location string = resourceGroup().location
param tags object
param desktopAppGroupFriendlyName string
param workspaceFriendlyName string
param remoteAppApplicationGroupInfo remoteAppApplicationGroup[] = []

param sessionHostResourceGroupName string = resourceGroup().name

@description('Entra ID object ID of the user or group to be assigned to the Desktop Virtualization User (dvu) role.')
param userObjectIds string[] = []

@description('Entra ID object ID of the user or group to be assigned to the Virtual Machine Administrator Login (vmal) role, if using Entra ID join.')
param adminObjectId string

@description('RBAC role definitions. Must contain the following roles: DesktopVirtualizationUser, VirtualMachineUserLogin, VirtualMachineAdministratorLogin.')
param roles roleDefinitions

param useSessionHostConfiguration bool = false // Defaults to false for backward compatibility.

param usePrivateLinkForHostPool bool
param privateEndpointSubnetId string
@description('The Azure resource ID of the private DNS zone for privatelink.wvd.microsoft.com.')
param privateLinkDnsZoneId string

param deploymentNameStructure string
param deploymentTime string = utcNow()

param deployDesktopAppGroup bool = true

@allowed(['ad', 'entraID'])
param logonType string

param useResourceTypeAbbreviations 'new' | 'old' = 'old'

// Parameters for Session Host Configuration Support
param sessionHostSize string = 'Standard_D4as_v6'
param adOuPath string?
param adDomainFqdn string?
param intuneEnrollment bool = false
param imageReference imageReferenceType = {
  publisher: 'microsoftwindowsdesktop'
  offer: 'office-365'
  sku: 'win11-25h2-avd-m365'
  // Version must be explicit for Session Host Configuration
  // 'latest' is not supported
  version: '26200.9168.260811'
}
param subnetId string?
param domainJoinCredentialKeyVaultSecretUris credentialKeyVaultSecretUrisType?
param localCredentialKeyVaultSecretUris credentialKeyVaultSecretUrisType?
@maxLength(9)
param vmNamePrefix string?

param sessionHostCount int?

param enableAvmTelemetry bool

/*
 * TYPES
 */

@export()
type remoteAppApplicationGroup = {
  @description('The name of the Remote Application Group.')
  name: string
  @description('The applications included in the group.')
  applications: application[]
  @description('The friendly (display) name of the group.')
  friendlyName: string
}

@export()
type roleDefinitions = {
  DesktopVirtualizationUser: string
  VirtualMachineUserLogin: string
  VirtualMachineAdministratorLogin: string

  *: string
}

import { application } from './remoteAppApplicationGroup.bicep'

import { credentialKeyVaultSecretUrisType } from '../types/credentialKeyVaultSecretUrisType.bicep'

import { imageReferenceType } from '../types/imageReferenceType.bicep'

/*
 * VARIABLES
 */

var resourceTypeAbbreviations = useResourceTypeAbbreviations == 'old'
  ? {
      hostPool: 'hp'
      applicationGroup: 'dag'
      workspace: 'ws'
    }
  : {
      hostPool: 'vdpool'
      applicationGroup: 'vdag'
      workspace: 'vdws'
    }

// Provide common default RDP properties for research workloads
var defaultRdpProperties = 'drivestoredirect:s:0;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:0;redirectprinters:i:0;devicestoredirect:s:0;redirectcomports:i:0;redirectsmartcards:i:1;usbdevicestoredirect:s:0;enablecredsspsupport:i:1;use multimon:i:1;'
var entraIDJoinCustomRdpProperties = (logonType == 'entraID')
  ? 'targetisaadjoined:i:1;enablerdsaadauth:i:1;redirectwebauthn:i:1;'
  : ''
var customRdpProperty = '${defaultRdpProperties}${entraIDJoinCustomRdpProperties}'
var intuneMdmId = '0000000a-0000-0000-c000-000000000000'

var splitSubnetId = split(subnetId!, '/')
var virtualNetworkResourceId = subnetId != null
  ? resourceId(splitSubnetId[4], 'Microsoft.Network/virtualNetworks', splitSubnetId[8])
  : null

/*
 * RESOURCES
 */

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2026-04-01-preview' = {
  name: replace(namingStructure, '{rtype}', resourceTypeAbbreviations.hostPool)
  location: location
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: deployDesktopAppGroup ? 'Desktop' : 'RailApplications'
    customRdpProperty: customRdpProperty
    registrationInfo: !useSessionHostConfiguration
      ? {
          registrationTokenOperation: 'Update'
          expirationTime: dateTimeAdd(deploymentTime, 'PT5H')
        }
      : null
    maxSessionLimit: 25 // TODO: Make this configurable via parameter

    publicNetworkAccess: usePrivateLinkForHostPool ? 'EnabledForClientsOnly' : 'Enabled'

    managementType: useSessionHostConfiguration ? 'Automated' : 'Standard'

    // LATER: Add Start VM On Connect configuration (role config!)
  }
  identity: useSessionHostConfiguration
    ? {
        type: 'SystemAssigned'
      }
    : null
  tags: tags
}

// Create role assignments for the managed identity of the host pool (?)
// - Desktop Virtualization Virtual Machine Contributor role
//   - Resource group for the session hosts
module resourceGroupRbacModule '../../module-library/roleAssignments/roleAssignment-rg.bicep' = if (useSessionHostConfiguration) {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'hp-rbac-rg'), 64)
  scope: resourceGroup(sessionHostResourceGroupName)
  params: {
    principalId: hostPool.identity.principalId
    roleDefinitionId: roles.DesktopVirtualizationVirtualMachineContributor
    principalType: 'ServicePrincipal'
    description: 'Role assignment for the managed identity of the host pool to manage (create, delete) session hosts.'
  }
}

//   - Host pool itself (could be different from session host RG)
module hostPoolRbacModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (useSessionHostConfiguration) {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'hp-rbac-hp'), 64)
  params: {
    principalId: hostPool.identity.principalId
    roleDefinitionId: roles.DesktopVirtualizationVirtualMachineContributor
    principalType: 'ServicePrincipal'
    description: 'Role assignment for the managed identity of the host pool.'
    resourceId: hostPool.id
    enableTelemetry: enableAvmTelemetry
  }
}
//   - Virtual network
module vnetRbacModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (useSessionHostConfiguration && !empty(virtualNetworkResourceId)) {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'hp-rbac-vnet'), 64)
  scope: resourceGroup(split(virtualNetworkResourceId!, '/')[4])
  params: {
    principalId: hostPool.identity.principalId
    roleDefinitionId: roles.DesktopVirtualizationVirtualMachineContributor
    principalType: 'ServicePrincipal'
    description: 'Role assignment for the managed identity of the host pool.'
    resourceId: virtualNetworkResourceId!
    enableTelemetry: enableAvmTelemetry
  }
}
// LATER: - Subnet (is that necessary? Portal does it)
// - Key Vault Secrets User
//   - Secrets for
//     - Domain join username, password
resource domainJoinCredentialKeyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = if (useSessionHostConfiguration && domainJoinCredentialKeyVaultSecretUris != null) {
  name: domainJoinCredentialKeyVaultSecretUris!.keyVaultName
  scope: resourceGroup(
    domainJoinCredentialKeyVaultSecretUris!.keyVaultSubscriptionId,
    domainJoinCredentialKeyVaultSecretUris!.keyVaultResourceGroupName
  )
}

resource domainJoinUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = if (useSessionHostConfiguration && domainJoinCredentialKeyVaultSecretUris != null) {
  name: split(domainJoinCredentialKeyVaultSecretUris!.username, '/')[4]
  parent: domainJoinCredentialKeyVault
}

resource domainJoinPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = if (useSessionHostConfiguration && domainJoinCredentialKeyVaultSecretUris != null) {
  name: split(domainJoinCredentialKeyVaultSecretUris!.password, '/')[4]
  parent: domainJoinCredentialKeyVault
}

module domainJoinUsernameSecretRbacModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (useSessionHostConfiguration && domainJoinCredentialKeyVaultSecretUris != null) {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'hp-rbac-djuname'), 64)
  scope: resourceGroup(
    domainJoinCredentialKeyVaultSecretUris!.keyVaultSubscriptionId,
    domainJoinCredentialKeyVaultSecretUris!.keyVaultResourceGroupName
  )
  params: {
    principalId: hostPool.identity.principalId
    roleDefinitionId: roles.KeyVaultSecretsUser
    principalType: 'ServicePrincipal'
    description: 'Role assignment for the managed identity of the host pool to access the domain join username secret.'
    resourceId: domainJoinUsernameSecret.id
    enableTelemetry: enableAvmTelemetry
  }
}

module domainJoinPasswordSecretRbacModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (useSessionHostConfiguration && domainJoinCredentialKeyVaultSecretUris != null) {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'hp-rbac-djpass'), 64)
  scope: resourceGroup(
    domainJoinCredentialKeyVaultSecretUris!.keyVaultSubscriptionId,
    domainJoinCredentialKeyVaultSecretUris!.keyVaultResourceGroupName
  )
  params: {
    principalId: hostPool.identity.principalId
    roleDefinitionId: roles.KeyVaultSecretsUser
    principalType: 'ServicePrincipal'
    description: 'Role assignment for the managed identity of the host pool to access the domain join password secret.'
    resourceId: domainJoinPasswordSecret.id
    enableTelemetry: enableAvmTelemetry
  }
}

//     - Session host local admin username, password
resource localCredentialKeyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = if (useSessionHostConfiguration && localCredentialKeyVaultSecretUris != null) {
  name: localCredentialKeyVaultSecretUris!.keyVaultName
  scope: resourceGroup(
    localCredentialKeyVaultSecretUris!.keyVaultSubscriptionId,
    localCredentialKeyVaultSecretUris!.keyVaultResourceGroupName
  )
}
resource localUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = if (useSessionHostConfiguration && localCredentialKeyVaultSecretUris != null) {
  name: split(localCredentialKeyVaultSecretUris!.username, '/')[4]
  parent: localCredentialKeyVault
}

resource localPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = if (useSessionHostConfiguration && localCredentialKeyVaultSecretUris != null) {
  name: split(localCredentialKeyVaultSecretUris!.password, '/')[4]
  parent: localCredentialKeyVault
}

module usernameSecretRbacModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (useSessionHostConfiguration && localCredentialKeyVaultSecretUris != null) {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'hp-rbac-uname'), 64)
  scope: resourceGroup(
    localCredentialKeyVaultSecretUris!.keyVaultSubscriptionId,
    localCredentialKeyVaultSecretUris!.keyVaultResourceGroupName
  )
  params: {
    principalId: hostPool.identity.principalId
    roleDefinitionId: roles.KeyVaultSecretsUser
    principalType: 'ServicePrincipal'
    description: 'Role assignment for the managed identity of the host pool to access the session host local admin username secret.'
    resourceId: localUsernameSecret.id
    enableTelemetry: enableAvmTelemetry
  }
}

module passwordSecretRbacModule 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (useSessionHostConfiguration && localCredentialKeyVaultSecretUris != null) {
  #disable-next-line BCP334
  name: take(replace(deploymentNameStructure, '{rtype}', 'hp-rbac-pass'), 64)
  scope: resourceGroup(
    localCredentialKeyVaultSecretUris!.keyVaultSubscriptionId,
    localCredentialKeyVaultSecretUris!.keyVaultResourceGroupName
  )
  params: {
    principalId: hostPool.identity.principalId
    roleDefinitionId: roles.KeyVaultSecretsUser
    principalType: 'ServicePrincipal'
    description: 'Role assignment for the managed identity of the host pool to access the session host local admin password secret.'
    resourceId: localPasswordSecret.id
    enableTelemetry: enableAvmTelemetry
  }
}

// LATER: Create additional role assignments for the managed identity
// - Desktop Virtualization Virtual Machine Contributor role
//   - Custom image resource group - which resource groups(s) are they in?
//     ? Determine from image resource ID if custom image?
//   - NSG - we don't use a VM-based NSG
// - Virtual Machine Contributor
//   - NSG - we don't use a VM-based NSG

// If needed, create a session configuration resource to define the session host configuration for the host pool.
resource sessionHostConfiguration 'Microsoft.DesktopVirtualization/hostPools/sessionHostConfigurations@2026-04-01-preview' = if (useSessionHostConfiguration && imageReference != null) {
  name: 'default'
  parent: hostPool
  properties: {
    vmResourceGroup: sessionHostResourceGroupName
    availabilityZones: [1, 2, 3]
    diskInfo: {
      managedDisk: {
        type: 'Premium_LRS'
      }
    }
    domainInfo: {
      joinType: logonType == 'ad' ? 'ActiveDirectory' : 'AzureActiveDirectory'
      activeDirectoryInfo: logonType == 'ad'
        ? {
            ouPath: adOuPath
            domainCredentials: {
              usernameKeyVaultSecretUri: domainJoinCredentialKeyVaultSecretUris.?username ?? ''
              passwordKeyVaultSecretUri: domainJoinCredentialKeyVaultSecretUris.?password ?? ''
            }
            domainName: adDomainFqdn
          }
        : null
      azureActiveDirectoryInfo: logonType != 'ad'
        ? {
            mdmProviderGuid: intuneEnrollment ? intuneMdmId : ''
          }
        : null
    }
    vmTags: tags
    vmLocation: location
    imageInfo: {
      type: imageReference.?id != null ? 'Custom' : 'Marketplace'
      marketplaceInfo: imageReference.?id == null
        ? {
            publisher: imageReference.?publisher!
            offer: imageReference.?offer!
            sku: imageReference.?sku!
            exactVersion: imageReference.?version!
          }
        : null
      customInfo: imageReference.?id != null
        ? {
            resourceId: imageReference.?id!
          }
        : null
    }
    networkInfo: {
      subnetId: subnetId!
    }
    vmAdminCredentials: {
      usernameKeyVaultSecretUri: localCredentialKeyVaultSecretUris.?username ?? ''
      passwordKeyVaultSecretUri: localCredentialKeyVaultSecretUris.?password ?? ''
    }
    // vmNamePrefix: 
    vmSizeId: sessionHostSize
    vmNamePrefix: vmNamePrefix!
  }
  // Requires explicit dependencies on the role assignments
  dependsOn: [
    resourceGroupRbacModule
    hostPoolRbacModule
    vnetRbacModule
    domainJoinUsernameSecretRbacModule
    domainJoinPasswordSecretRbacModule
    usernameSecretRbacModule
    passwordSecretRbacModule
  ]
}

var logOffDelay = 5

resource sessionHostManagement 'Microsoft.DesktopVirtualization/hostPools/sessionHostManagements@2026-04-01-preview' = if (useSessionHostConfiguration) {
  name: 'default'
  parent: hostPool
  properties: {
    provisioning: {
      canaryPolicy: 'Always'
      instanceCount: sessionHostCount
      setDrainMode: false
    }
    failedSessionHostCleanupPolicy: 'KeepOne'
    scheduledDateTimeZone: 'UTC'
    update: {
      logOffDelayMinutes: logOffDelay
      maxVmsRemoved: 1
      deleteOriginalVm: false
      logOffMessage: 'Your session will be logged off in ${logOffDelay} minutes for maintenance. Please save your work.'
    }
  }
}

resource desktopApplicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2026-04-01-preview' = if (deployDesktopAppGroup) {
  name: replace(namingStructure, '{rtype}', resourceTypeAbbreviations.applicationGroup)
  location: location
  properties: {
    applicationGroupType: 'Desktop'
    hostPoolArmPath: hostPool.id
    // This isn't actually displayed anywhere; just set here for possible future use
    friendlyName: desktopAppGroupFriendlyName
  }
  tags: tags
}

// Create a role assignment for the user or group to be assigned to the Virtual Machine User Login (vmul) role, if using Entra ID join
resource rgRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for userObjectId in userObjectIds: if (logonType == 'entraID') {
    name: guid(resourceGroup().id, userObjectId, roles.VirtualMachineUserLogin)
    properties: {
      roleDefinitionId: roles.VirtualMachineUserLogin
      principalId: userObjectId
    }
  }
]

// Create a role assignment for the admins to be assigned to the Virtual Machine Administrator Login (vmal) role, if using Entra ID join
resource rgAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (logonType == 'entraID') {
  name: guid(resourceGroup().id, adminObjectId, roles.VirtualMachineAdministratorLogin)
  properties: {
    roleDefinitionId: roles.VirtualMachineAdministratorLogin
    principalId: adminObjectId
  }
}

// LATER: Execute deployment script for Update-AzWvdDesktop -ResourceGroupName resourceGroup().name -ApplicationGroupName desktopApplicationGroup.name -Name SessionDesktop -FriendlyName desktopAppGroupFriendlyName

resource dagUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for userObjectId in userObjectIds: if (logonType == 'entraID') {
    name: guid(desktopApplicationGroup.id, userObjectId, roles.DesktopVirtualizationUser)
    scope: desktopApplicationGroup
    properties: {
      roleDefinitionId: roles.DesktopVirtualizationUser
      principalId: userObjectId
    }
  }
]

// TODO: Role assignment for admins required?
// resource dagAdminRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
//   for appGroup in remoteAppApplicationGroupInfo: if (!empty(adminObjectId)) {
//     name: guid(
//       desktopApplicationGroup.id,
//       remoteAppApplicationGroupsModule[0].outputs.id,
//       roles.DesktopVirtualizationUser
//     )
//     scope: desktopApplicationGroup
//     properties: {
//       roleDefinitionId: roles.DesktopVirtualizationUser
//       principalId: adminObjectId
//     }
//   }
// ]

module remoteAppApplicationGroupsModule 'remoteAppApplicationGroup.bicep' = [
  for appGroup in remoteAppApplicationGroupInfo: {
    #disable-next-line BCP334
    name: take(
      replace(deploymentNameStructure, '{rtype}', '${resourceTypeAbbreviations.applicationGroup}-${appGroup.name}'),
      64
    )
    params: {
      name: replace(namingStructure, '{rtype}', appGroup.name)
      location: location
      tags: tags
      applications: appGroup.applications
      friendlyName: appGroup.friendlyName
      hostPoolId: hostPool.id

      principalObjectIds: userObjectIds
      roleDefinitionId: roles.DesktopVirtualizationUser
    }
  }
]

var desktopApplicationGroupId = deployDesktopAppGroup ? [desktopApplicationGroup.id] : []
var expectedRemoteAppApplicationGroupIds = [
  for appGroup in remoteAppApplicationGroupInfo: '${resourceGroup().id}/providers/Microsoft.DesktopVirtualization/applicationgroups/${replace(namingStructure, '{rtype}', appGroup.name)}'
]
var allApplicationGroupIds = concat(desktopApplicationGroupId, expectedRemoteAppApplicationGroupIds)

// Create a Azure Virtual Desktop workspace and assign all application groups to it
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2026-04-01-preview' = {
  name: replace(namingStructure, '{rtype}', resourceTypeAbbreviations.workspace)
  location: location
  properties: {
    applicationGroupReferences: allApplicationGroupIds
    friendlyName: workspaceFriendlyName
  }
  // Dependency must be explicit because the allApplicationGroupIds array isn't created from the application groups module
  dependsOn: [remoteAppApplicationGroupsModule]
  tags: tags
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = if (usePrivateLinkForHostPool) {
  name: replace(namingStructure, '{rtype}', '${resourceTypeAbbreviations.hostPool}-pep')
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: replace(namingStructure, '{rtype}', '${resourceTypeAbbreviations.hostPool}-pep')
        properties: {
          privateLinkServiceId: hostPool.id
          groupIds: [
            'connection'
          ]
        }
      }
    ]
  }
}

resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = if (usePrivateLinkForHostPool) {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace('privatelink.wvd.microsoft.com', '.', '-')
        properties: {
          privateDnsZoneId: privateLinkDnsZoneId
        }
      }
    ]
  }
}

output hostPoolRegistrationToken string? = !useSessionHostConfiguration
  ? hostPool.properties.registrationInfo.token
  : null
output hostPoolName string = hostPool.name
output sessionHostConfigurationVersion string? = useSessionHostConfiguration
  ? sessionHostConfiguration!.properties.version
  : null
