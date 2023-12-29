param name string
param location string = resourceGroup().location
param hostPoolId string
param friendlyName string
param applications array
param tags object

param principalId string
param roleDefinitionId string

resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2022-09-09' = {
  name: name
  location: location
  properties: {
    applicationGroupType: 'RemoteApp'
    hostPoolArmPath: hostPoolId
    friendlyName: friendlyName
  }
  tags: tags
}

resource remoteApplications 'Microsoft.DesktopVirtualization/applicationGroups/applications@2022-10-14-preview' = [for app in applications: {
  name: app.name
  parent: applicationGroup
  properties: {
    commandLineSetting: contains(app, 'commandLineSetting') && !empty(app.commandLineSetting) ? app.commandLineSetting : 'Allow'
    commandLineArguments: contains(app, 'commandLineArguments') && !empty(app.commandLineArguments) ? app.CommandLineArguments : ''

    applicationType: app.applicationType
    filePath: app.filePath
    friendlyName: app.friendlyName
    iconIndex: app.iconIndex
    iconPath: app.iconPath
    showInPortal: app.showInPortal
  }
}]

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationGroup.id, principalId, roleDefinitionId)
  scope: applicationGroup
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}

output id string = applicationGroup.id
output name string = applicationGroup.name
