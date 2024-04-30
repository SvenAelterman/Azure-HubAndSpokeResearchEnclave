param namingStructure string
param location string = resourceGroup().location
param tags object
param desktopAppGroupFriendlyName string
param workspaceFriendlyName string
param remoteAppApplicationGroupInfo remoteAppApplicationGroup[] = []

@description('Entra ID object ID of the user or group to be assigned to the Desktop Virtualization User (dvu) role.')
param userObjectId string = ''

@description('Entra ID object ID of the user or group to be assigned to the Virtual Machine Administrator Login (vmal) role, if using Entra ID join.')
param adminObjectId string

@description('RBAC role definitions. Must contain the following roles: DesktopVirtualizationUser, VirtualMachineUserLogin, VirtualMachineAdministratorLogin.')
param roles roleDefinitions

param usePrivateLinkForHostPool bool
param privateEndpointSubnetId string
@description('The Azure resource ID of the private DNS zone for privatelink.wvd.microsoft.com.')
param privateLinkDnsZoneId string

param deploymentNameStructure string
param deploymentTime string = utcNow()

param deployDesktopAppGroup bool = true

@allowed(['ad', 'entraID'])
param logonType string

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

/*
 * VARIABLES
 */

// Provide common default RDP properties for research workloads
var defaultRdpProperties = 'drivestoredirect:s:0;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:0;redirectprinters:i:0;devicestoredirect:s:0;redirectcomports:i:0;redirectsmartcards:i:1;usbdevicestoredirect:s:0;enablecredsspsupport:i:1;use multimon:i:1;'
var entraIDJoinCustomRdpProperties = (logonType == 'entraID')
  ? 'targetisaadjoined:i:1;enablerdsaadauth:i:1;redirectwebauthn:i:1;'
  : ''
var customRdpProperty = '${defaultRdpProperties}${entraIDJoinCustomRdpProperties}'

/*
 * RESOURCES
 */

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: replace(namingStructure, '{rtype}', 'hp')
  location: location
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: deployDesktopAppGroup ? 'Desktop' : 'RailApplications'
    customRdpProperty: customRdpProperty
    registrationInfo: {
      registrationTokenOperation: 'Update'
      expirationTime: dateTimeAdd(deploymentTime, 'PT5H')
    }
    maxSessionLimit: 25

    publicNetworkAccess: usePrivateLinkForHostPool ? 'EnabledForClientsOnly' : 'Enabled'

    // LATER: Add Start VM On Connect configuration (role config!)
  }
  tags: tags
}

// LATER: Add support for session host configuration data
// resource hostPoolConfigurations 'Microsoft.DesktopVirtualization/hostPools/sessionHostConfigurations@2024-01-16-preview' = {
//   name: 
//   properties: {
//     diskInfo: {
//       type: 
//     }
//     domainInfo: {
//       joinType: 
//     }
//     imageInfo: {
//       type:  
//     }
//     networkInfo: {
//       subnetId: 
//     }
//     vmAdminCredentials: {
//       passwordKeyVaultSecretUri: 
//       usernameKeyVaultSecretUri: 
//     }
//     vmNamePrefix: 
//     vmSizeId: 
//   }
// }

resource desktopApplicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2023-09-05' =
  if (deployDesktopAppGroup) {
    name: replace(namingStructure, '{rtype}', 'dag')
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
resource rgRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' =
  if (logonType == 'entraID' && !empty(userObjectId)) {
    name: guid(resourceGroup().id, userObjectId, roles.VirtualMachineUserLogin)
    properties: {
      roleDefinitionId: roles.VirtualMachineUserLogin
      principalId: userObjectId
    }
  }

// Create a role assignment for the admins to be assigned to the Virtual Machine Administrator Login (vmal) role, if using Entra ID join
resource rgAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' =
  if (logonType == 'entraID') {
    name: guid(resourceGroup().id, adminObjectId, roles.VirtualMachineAdministratorLogin)
    properties: {
      roleDefinitionId: roles.VirtualMachineAdministratorLogin
      principalId: adminObjectId
    }
  }

// LATER: Execute deployment script for Update-AzWvdDesktop -ResourceGroupName resourceGroup().name -ApplicationGroupName desktopApplicationGroup.name -Name SessionDesktop -FriendlyName desktopAppGroupFriendlyName

resource dagUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' =
  if (deployDesktopAppGroup && !empty(userObjectId)) {
    name: guid(desktopApplicationGroup.id, userObjectId, roles.DesktopVirtualizationUser)
    scope: desktopApplicationGroup
    properties: {
      roleDefinitionId: roles.DesktopVirtualizationUser
      principalId: userObjectId
    }
  }

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
    name: take(replace(deploymentNameStructure, '{rtype}', 'rag-${appGroup.name}'), 64)
    params: {
      name: replace(namingStructure, '{rtype}', appGroup.name)
      location: location
      tags: tags
      applications: appGroup.applications
      friendlyName: appGroup.friendlyName
      hostPoolId: hostPool.id

      principalId: userObjectId
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
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2023-09-05' = {
  name: replace(namingStructure, '{rtype}', 'ws')
  location: location
  properties: {
    applicationGroupReferences: allApplicationGroupIds
    friendlyName: workspaceFriendlyName
  }
  // Dependency must be explicit because the allApplicationGroupIds array isn't created from the application groups module
  dependsOn: [remoteAppApplicationGroupsModule]
  tags: tags
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' =
  if (usePrivateLinkForHostPool) {
    name: replace(namingStructure, '{rtype}', 'hp-pep')
    location: location
    tags: tags
    properties: {
      subnet: {
        id: privateEndpointSubnetId
      }
      privateLinkServiceConnections: [
        {
          name: replace(namingStructure, '{rtype}', 'hp-pep')
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

resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' =
  if (usePrivateLinkForHostPool) {
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

output hostPoolRegistrationToken string = hostPool.properties.registrationInfo.token
output hostPoolName string = hostPool.name
