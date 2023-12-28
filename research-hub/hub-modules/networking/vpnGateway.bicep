param gatewaySubnetId string
param namingStructure string

param gatewaySku string = 'VpnGw2AZ'
param location string = resourceGroup().location
param tags object

// Create a static public IP address for the virtual network gateway
resource vngPublicIP 'Microsoft.Network/publicIPAddresses@2023-06-01' = {
  name: replace(namingStructure, '{rtype}', 'pip-vng')
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  zones: [ '1', '2', '3' ]
  tags: tags
}

// Create an VPN virtual network gateway
resource virtualNetworkGateway 'Microsoft.Network/virtualNetworkGateways@2023-06-01' = {
  name: replace(namingStructure, '{rtype}', 'vng')
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation2'
    sku: {
      name: gatewaySku
      tier: gatewaySku
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: vngPublicIP.id
          }
        }
      }
    ]
  }
  tags: tags
}
