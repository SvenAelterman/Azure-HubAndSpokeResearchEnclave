param location string
param nsgName string
param securityRules array = []

param tags object = {}

resource nsg 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: securityRules
  }
  tags: tags
}

output nsgId string = nsg.id
output nsgName string = nsg.name
