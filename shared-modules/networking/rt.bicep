param location string
param rtName string
param routes array

param tags object = {}

resource rt 'Microsoft.Network/routeTables@2022-01-01' = {
  name: rtName
  location: location
  properties: {
    disableBgpRoutePropagation: true

    routes: routes
  }
  tags: tags
}

output routeTableId string = rt.id
