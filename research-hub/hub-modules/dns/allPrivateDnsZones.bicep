param tags object
param deploymentNameStructure string

// Load all private DNS zones to be created from a file.
// The file contains Azure Commercial and Azure Government entries.
var allPrivateDnsZoneNames = loadJsonContent('allPrivateDnsZones.jsonc')['${az.environment().name}']

module privateDnsZones 'privateDnsZone.bicep' = [for zoneName in allPrivateDnsZoneNames: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zone-${zoneName}'), 64)
  params: {
    zoneName: zoneName
    tags: tags
  }
}]
