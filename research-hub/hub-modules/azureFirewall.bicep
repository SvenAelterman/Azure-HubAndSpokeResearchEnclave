param firewallSubnetId string
param firewallManagementSubnetId string
param namingStructure string
param tags object

@allowed([
  'Basic'
])
param firewallTier string = 'Basic'

param location string = resourceGroup().location

// Basic Firewall requires two, unsure about other tiers
var publicIpCount = 2

// Create the public IP address(es) for the Firewall
resource firewallPublicIps 'Microsoft.Network/publicIPAddresses@2022-09-01' = [for i in range(0, publicIpCount): {
  name: replace(namingStructure, '{rtype}', 'pip-fw${i}')
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  tags: tags
}]

// Create firewall policy
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2022-01-01' = {
  name: replace(namingStructure, '{rtype}', 'fwpol')
  location: location
  properties: {
    sku: {
      tier: firewallTier
    }
  }
  tags: tags
}

var defaultRuleCollectionGroups = {
  AVD: {
    rules: loadJsonContent('../azure-firewall-rules/azFwPolRuleColls-AVD.jsonc')
    priority: 500
  }
  AzurePlatform: {
    rules: loadJsonContent('../azure-firewall-rules/azFwPolRuleColls-AzurePlatform.jsonc')
    priority: 1000
  }
  AVDRDWeb: {
    rules: loadJsonContent('../azure-firewall-rules/azFwPolRuleColls-AVDRDWeb.jsonc')
    priority: 100
  }
  ManagedDevices: {
    rules: loadJsonContent('../azure-firewall-rules/azFwPolRuleColls-ManagedDevices.jsonc')
    priority: 300
  }
  Office365Activation: {
    rules: loadJsonContent('../azure-firewall-rules/azFwPolRuleColls-Office365Activation.jsonc')
    priority: 700
  }
  ResearchDataSources: {
    rules: loadJsonContent('../azure-firewall-rules/azFwPolRuleColls-ResearchDataSources.jsonc')
    priority: 600
  }
}

// TODO: Divide into optional rule collections: AzurePlatform, AVDRDWeb (rename!), ResearchDataSources (?)

@batchSize(1) // Do not process more than one rule collection group at a time
resource ruleCollectionGroups 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-07-01' = [for group in items(defaultRuleCollectionGroups): {
  name: group.key
  parent: firewallPolicy
  properties: {
    priority: group.value.priority
    ruleCollections: group.value.rules
  }
}]

// Create Azure Firewall resource
resource firewall 'Microsoft.Network/azureFirewalls@2022-01-01' = {
  name: replace(namingStructure, '{rtype}', 'fw')
  location: location

  properties: {
    ipConfigurations: [
      {
        name: firewallPublicIps[0].name
        properties: {
          subnet: {
            id: firewallSubnetId
          }
          publicIPAddress: {
            id: firewallPublicIps[0].id
          }
        }

      }
    ]
    managementIpConfiguration: {
      name: replace(namingStructure, '{rtype}', 'fwmgt')
      properties: {
        publicIPAddress: {
          id: firewallPublicIps[1].id
        }
        subnet: {
          id: firewallManagementSubnetId
        }
      }
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    sku: {
      name: 'AZFW_VNet'
      tier: firewallTier
    }
  }

  tags: tags

  // This dependency is added manually because otherwise the FW will try to deploy before the rule collections are ready
  dependsOn: [ ruleCollectionGroups ]
}

output fwPrIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
