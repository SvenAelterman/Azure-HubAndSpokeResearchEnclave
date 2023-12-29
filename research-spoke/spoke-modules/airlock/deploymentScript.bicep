param location string
param namingStructure string
param subWorkloadName string
param arguments string
param scriptContent string
param userAssignedIdentityId string
param tags object
param debugMode bool

param currentTime string = utcNow()

var baseName = !empty(subWorkloadName) ? replace(namingStructure, '{subWorkloadName}', subWorkloadName) : replace(namingStructure, '-{subWorkloadName}', '')

// Run PowerShell in Verbose mode when in debug mode
var actualArgs = debugMode ? '${arguments} -Verbose' : arguments

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: replace(baseName, '{rtype}', 'dplscr')
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '9.4' // Latest available as of 2023-04-12
    timeout: 'PT10M'
    arguments: actualArgs
    scriptContent: scriptContent
    cleanupPreference: debugMode ? 'OnExpiration' : 'OnSuccess'
    retentionInterval: 'P1D'
    forceUpdateTag: currentTime
  }
  tags: tags
}
