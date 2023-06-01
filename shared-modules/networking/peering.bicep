param localVNetName string
param remoteVNetId string

param localVNetFriendlyName string
param remoteVNetFriendlyName string

param allowForwardedTraffic bool = true
param allowGatewayTransit bool = false
param allowVirtualNetworkAccess bool = true
param useRemoteGateways bool = false

var peeringName = take('peering-${localVNetFriendlyName}-to-${remoteVNetFriendlyName}', 80)

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-09-01' = {
  name: '${localVNetName}/${peeringName}'
  properties: {
    remoteVirtualNetwork: {
      id: remoteVNetId
    }

    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    useRemoteGateways: useRemoteGateways
  }
}
