/* Parent module for route tables */
param subnetDefs object
param deploymentNameStructure string
param namingStructure string

param location string = resourceGroup().location
param tags object = {}

// Convert the subnet object to an array and filter out subnets that don't need a route table
var subnetArray = filter(items(subnetDefs), sn => contains(sn.value, 'routes'))

// Create route tables
module rtModule 'rt.bicep' = [for subnet in subnetArray: {
  name: replace(deploymentNameStructure, '{rtype}', 'rt-${subnet.key}')
  params: {
    location: location
    rtName: replace(namingStructure, '{rtype}', 'rt-${subnet.key}')
    routes: subnet.value.routes
    tags: tags
  }
}]

// Output the created route tables as an object array (which can be union'd later)
output routeTables array = [for i in range(0, length(subnetArray)): {
  '${subnetArray[i].key}': {
    id: rtModule[i].outputs.routeTableId
    name: rtModule[i].outputs.routeTableName
  }
}]
