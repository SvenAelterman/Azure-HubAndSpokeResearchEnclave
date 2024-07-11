// TODO: Use AVM Module
// https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/ip-group

param name string
param location string = resourceGroup().location
param ipAddresses array
param tags object

resource ipGroup 'Microsoft.Network/ipGroups@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    ipAddresses: ipAddresses
  }
}

output id string = ipGroup.id
output name string = ipGroup.name
