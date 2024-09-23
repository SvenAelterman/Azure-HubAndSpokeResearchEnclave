param localVNetName string
param remoteVNetId string

param localVNetFriendlyName string
param remoteVNetFriendlyName string

param allowVirtualNetworkAccess bool = true
// This should generally be true because this is a spoke that might receive traffic forwarded by the FW from other spokes
param allowForwardedTraffic bool = true
param allowGatewayTransit bool = false
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
