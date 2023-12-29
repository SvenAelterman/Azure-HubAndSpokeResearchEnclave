param namingStructure string
param location string = resourceGroup().location
param tags object
param desktopAppGroupFriendlyName string
param workspaceFriendlyName string
param remoteAppApplicationGroupInfo array = []

@description('Entra ID object ID of the user or group to be assigned to the Desktop Virtualization User (dvu) role.')
param objectId string
@description('Desktop Virtualization User (dvu) role definition ID.')
param dvuRoleDefinitionId string

param usePrivateLinkForHostPool bool = true
param privateEndpointSubnetId string
param privateLinkDnsZoneId string

param deploymentNameStructure string
param deploymentTime string = utcNow()

// TODO: Using logonType param, set up Virtual Machine User Login role for objectId
@allowed([ 'ad', 'entraID' ])
param logonType string

param vmulRoleDefinitionId string

// Provide common default RDP properties for research workloads
var defaultRdpProperties = 'drivestoredirect:s:0;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:0;redirectprinters:i:0;devicestoredirect:s:0;redirectcomports:i:0;redirectsmartcards:i:1;usbdevicestoredirect:s:0;enablecredsspsupport:i:1;use multimon:i:1;'
var entraIDJoinCustomRdpProperties = (logonType == 'entraID') ? 'targetisaadjoined:i:1;enablerdsaadauth:i:1;redirectwebauthn:i:1;' : ''
var customRdpProperty = '${defaultRdpProperties}${entraIDJoinCustomRdpProperties}'

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2020-11-10-preview' = {
  name: replace(namingStructure, '{rtype}', 'hp')
  location: location
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: 'Desktop'
    customRdpProperty: customRdpProperty
    registrationInfo: {
      registrationTokenOperation: 'Update'
      expirationTime: dateTimeAdd(deploymentTime, 'PT5H')
    }
    maxSessionLimit: 25
    // TODO: Add Start VM On Connect configuration (role config!)
  }
  tags: tags
}

resource desktopApplicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2022-09-09' = {
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
resource rgRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (logonType == 'entraID') {
  name: guid(resourceGroup().id, objectId, vmulRoleDefinitionId)
  properties: {
    roleDefinitionId: vmulRoleDefinitionId
    principalId: objectId
  }
}

// LATER: Execute deployment script for Update-AzWvdDesktop -ResourceGroupName rg-wcmprj-avd-demo-eastus-02 -ApplicationGroupName ag-wcmprj-avd-demo-eastus-02 -Name SessionDesktop -FriendlyName Test

resource dagRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(desktopApplicationGroup.id, objectId, dvuRoleDefinitionId)
  scope: desktopApplicationGroup
  properties: {
    roleDefinitionId: dvuRoleDefinitionId
    principalId: objectId
  }
}

module remoteAppApplicationGroupsModule 'remoteAppApplicationGroup.bicep' = [for appGroup in remoteAppApplicationGroupInfo: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rag-${appGroup.name}'), 64)
  params: {
    name: replace(namingStructure, '{rtype}', appGroup.name)
    location: location
    tags: tags
    applications: appGroup.applications
    friendlyName: appGroup.friendlyName
    hostPoolId: hostPool.id

    principalId: objectId
    roleDefinitionId: dvuRoleDefinitionId
  }
}]

var desktopApplicationGroupId = [ desktopApplicationGroup.id ]
var expectedRemoteAppApplicationGroupIds = [for appGroup in remoteAppApplicationGroupInfo: '${resourceGroup().id}/providers/Microsoft.DesktopVirtualization/applicationgroups/${replace(namingStructure, '{rtype}', appGroup.name)}']
var allApplicationGroupIds = concat(desktopApplicationGroupId, expectedRemoteAppApplicationGroupIds)

// Create a Azure Virtual Desktop workspace and assign all application groups to it
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2022-09-09' = {
  name: replace(namingStructure, '{rtype}', 'ws')
  location: location
  properties: {
    applicationGroupReferences: allApplicationGroupIds
    friendlyName: workspaceFriendlyName
  }
  // Dependency must be explicit because the allApplicationGroupIds array isn't created from the application groups module
  dependsOn: [
    remoteAppApplicationGroupsModule
  ]
  tags: tags
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = if (usePrivateLinkForHostPool) {
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

output hostPoolRegistrationToken string = hostPool.properties.registrationInfo.token
output hostPoolName string = hostPool.name
