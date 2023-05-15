param namingStructure string
param location string
param bastionSubnetId string

param tags object = {}

resource pip 'Microsoft.Network/publicIPAddresses@2022-11-01' = {
  name: replace(namingStructure, '{rtype}', 'pip-bas')
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
  tags: tags
}

resource bastion 'Microsoft.Network/bastionHosts@2022-11-01' = {
  name: replace(namingStructure, '{rtype}', 'bas')
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          publicIPAddress: {
            id: pip.id
          }
          subnet: {
            id: bastionSubnetId
          }
        }
      }
    ]
  }
  tags: tags
}
