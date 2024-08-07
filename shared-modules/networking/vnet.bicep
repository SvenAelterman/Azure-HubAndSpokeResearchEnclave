param location string
param vnetName string
@description('The custom oject definition for the subnets. The key is the name of the subnet. The value is an object containing the properties for the subnet. { subnet-name: { addressPrefix: subnet-address-prefix, ... }, ... }')
param subnetDefs object
@minLength(1)
param vnetAddressPrefixes array

@description('The definition of additional subnets that have been manually created.')
param additionalSubnets array

@description('The NSG object must have a property with the name of the subnet. The value of the property is an object containing an id property. {subnet-name: { id: nsg-id }}')
param networkSecurityGroups object = {}
@description('The route tables object must have a property with the name of the subnet. The value of the property is an object containing an id property. {subnet-name: { id: rt-id }}')
param routeTables object = {}

param customDnsIPs array = []

param tags object = {}

// This will sort the subnets alphabetically by name
var subnetDefsArray = items(subnetDefs)

// Create an array of objects that match the ARM schema
var subnetArmDefs = [
  for subnet in subnetDefsArray: {
    name: subnet.key
    properties: {
      // All other properties are child properties of the value property
      addressPrefix: subnet.value.addressPrefix
      serviceEndpoints: subnet.?value.?serviceEndpoints ?? null
      // If this subnet needs an NSG and an NSG for the subnet is present in the NSG parameter
      networkSecurityGroup: contains(subnet.value, 'securityRules') && contains(networkSecurityGroups, subnet.key)
        ? {
            id: networkSecurityGroups[subnet.key].id
          }
        : null
      routeTable: contains(subnet.value, 'routes') && contains(routeTables, subnet.key)
        ? {
            id: routeTables[subnet.key].id
          }
        : null
      // Delegate the subnet to a resource provider, if specified
      delegations: contains(subnet.value, 'delegation') && !empty(subnet.value.delegation)
        ? [
            {
              name: 'delegation'
              properties: {
                serviceName: subnet.value.delegation
              }
            }
          ]
        : null
      privateLinkServiceNetworkPolicies: contains(subnet.value, 'privateLinkServiceNetworkPolicies') && !empty(subnet.value.privateLinkServiceNetworkPolicies)
        ? subnet.value.privateLinkServiceNetworkPolicies
        : null
    }
  }
]

// Combine the subnets created/managed by this template with any additional subnets provided as a parameter
var allSubnets = union(additionalSubnets, subnetArmDefs)

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetAddressPrefixes
    }

    subnets: allSubnets

    dhcpOptions: !empty(customDnsIPs)
      ? {
          dnsServers: customDnsIPs
        }
      : {}
  }
  tags: tags
}

// Retrieve the subnets as an array of existing resources
// This is important because we need to ensure subnet return value is matched to the name of the subnet correctly - order matters
// This works because the parent property is set to the virtual network, which means this won't be attempted until the VNet is created
resource subnetRes 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' existing = [
  for subnet in subnetDefsArray: {
    name: subnet.key
    parent: vnet
  }
]

// Outputs in the order of the subnetDefsArray
output actualSubnets array = [
  for i in range(0, length(subnetDefsArray)): {
    '${subnetRes[i].name}': {
      id: subnetRes[i].id
      addressPrefix: subnetRes[i].properties.addressPrefix
      routeTableId: contains(subnetRes[i].properties, 'routeTable') ? subnetRes[i].properties.routeTable.id : null
      routeTableName: contains(subnetRes[i].properties, 'routeTable') ? routeTables[subnetRes[i].name].name : null
      networkSecurityGroupId: contains(subnetRes[i].properties, 'networkSecurityGroup')
        ? subnetRes[i].properties.networkSecurityGroup.id
        : null
      networkSecurityGroupName: contains(subnetRes[i].properties, 'networkSecurityGroup')
        ? networkSecurityGroups[subnetRes[i].name].name
        : null
      // Add as many additional subnet properties as needed downstream
    }
  }
]

output vNetId string = vnet.id
