/*
 * Deploys and links all Azure Private Link DNS zones (as specified in shared-modules/dns/allPrivateDnsZones.jsonc).
 */

param tags object
param deploymentNameStructure string
param vnetId string

// Load all private DNS zones to be created from a file.
// The file contains Azure Commercial and Azure Government entries.
var allPrivateLinkDnsZoneNames = loadJsonContent('../../../shared-modules/dns/allPrivateDnsZones.jsonc')['${az.environment().name}']

module privateDnsZones 'privateDnsZone.bicep' = [for zoneName in allPrivateLinkDnsZoneNames: {
  name: take(replace(deploymentNameStructure, '{rtype}', 'zone-${zoneName}'), 64)
  params: {
    zoneName: zoneName
    tags: tags
    vnetId: vnetId
    deploymentNameStructure: deploymentNameStructure
  }
}]
