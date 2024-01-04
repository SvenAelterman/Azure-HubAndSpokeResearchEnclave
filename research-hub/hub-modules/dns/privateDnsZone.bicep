#disable-next-line no-hardcoded-env-urls // Just used in a comment text as an example
@description('The name of the private DNS zone, e.g., privatelink.blob.core.windows.net.')
param zoneName string
@description('The resource ID of the virtual network to link to the private DNS zone.')
param vnetId string

param registrationEnabled bool = false
param tags object
param deploymentNameStructure string

resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

// Link the private DNS zone to the virtual network
module vnetLink '../../../shared-modules/dns/privateDnsZoneVNetLink.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'link-${zoneName}'), 64)
  params: {
    // Providing the name of the zone like this creates a dependency on the zone resource, which must be created first
    dnsZoneName: dnsZone.name
    registrationEnabled: registrationEnabled
    vnetId: vnetId
  }
}

output zoneName string = dnsZone.name
output zoneId string = dnsZone.id
