param zoneName string

param tags object

resource dnsZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

output zoneName string = dnsZone.name
output zoneId string = dnsZone.id
