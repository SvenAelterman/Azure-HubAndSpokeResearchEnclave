/* Parent module for NSGs */
param subnetDefs object
param deploymentNameStructure string
param namingStructure string

param location string = resourceGroup().location
param tags object = {}

// Convert the subnet object to an array and filter out subnets that don't need an NSG
var subnetArray = filter(items(subnetDefs), sn => contains(sn.value, 'securityRules'))

// Create NSGs
module nsgModule 'nsg.bicep' = [for subnet in subnetArray: {
  name: replace(deploymentNameStructure, '{rtype}', 'nsg-${subnet.key}')
  params: {
    location: location
    nsgName: replace(namingStructure, '{rtype}', 'nsg-${subnet.key}')
    securityRules: subnet.value.securityRules
    tags: tags
  }
}]

output nsgIds array = [for i in range(0, length(subnetArray)): {
  '${subnetArray[i].key}': {
    id: nsgModule[i].outputs.nsgId
  }
}]
