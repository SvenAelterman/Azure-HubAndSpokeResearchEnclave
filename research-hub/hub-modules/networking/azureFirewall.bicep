param firewallSubnetId string
@description('The Azure resource ID of the management subnet for a Basic firewall or for a firewall with forced tunneling.')
param firewallManagementSubnetId string = ''

param forcedTunneling bool = false

param namingStructure string
param tags object

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param firewallTier string = 'Basic'

param location string = resourceGroup().location

param includeActiveDirectoryRules bool = false
param includeDnsRules bool = false
param includeManagementSubnetRules bool = false
param dnsServerIPAddresses array = []
param domainControllerIPAddresses array = []
param ipAddressPool array = []
param managementSubnetRange string = ''

var createManagementIPConfiguration = (firewallTier == 'Basic' || forcedTunneling)
// Basic Firewall AND not forced tunneling requires two public IP addresses
var publicIpCount = (firewallTier == 'Basic' && !forcedTunneling) ? 2 : 1

// Create the public IP address(es) for the Firewall
resource firewallPublicIps 'Microsoft.Network/publicIPAddresses@2022-09-01' = [
  for i in range(0, publicIpCount): {
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
  }
]

// Create firewall policy
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2022-01-01' = {
  name: replace(namingStructure, '{rtype}', 'fwpol')
  location: location
  properties: {
    sku: {
      tier: firewallTier
    }
    // Do not SNAT when in forced tunneling mode
    snat: forcedTunneling
      ? {
          autoLearnPrivateRanges: 'Disabled'
          privateRanges: ['0.0.0.0/0']
        }
      : {}
  }
  tags: tags
}

var defaultRuleCollectionGroups = {
  AVD: {
    rules: loadJsonContent('../../azure-firewall-rules/azFwPolRuleColls-AVD.jsonc')
    priority: 500
  }
  AzurePlatform: {
    rules: loadJsonContent('../../azure-firewall-rules/azFwPolRuleColls-AzurePlatform.jsonc')[az.environment().name]
    priority: 1000
  }
  AVDRDWeb: {
    rules: loadJsonContent('../../azure-firewall-rules/azFwPolRuleColls-AVDRDWeb.jsonc')
    priority: 100
  }
  ManagedDevices: {
    rules: loadJsonContent('../../azure-firewall-rules/azFwPolRuleColls-ManagedDevices.jsonc')[az.environment().name]
    priority: 300
  }
  Office365Activation: {
    rules: loadJsonContent('../../azure-firewall-rules/azFwPolRuleColls-Office365Activation.jsonc')[az.environment().name]
    priority: 700
  }
  ResearchDataSources: {
    rules: loadJsonContent('../../azure-firewall-rules/azFwPolRuleColls-ResearchDataSources.jsonc')
    priority: 600
  }
}

var activeDirectoryRuleCollectionGroup = includeActiveDirectoryRules && length(domainControllerIPAddresses) > 0
  ? {
      ActiveDirectory: {
        rules: json(replace(
          replace(
            loadTextContent('../../azure-firewall-rules/azFwPolRuleColls-ActiveDirectory.jsonc'),
            '"{{domainControllerIPAddresses}}"',
            string(domainControllerIPAddresses)
          ),
          '"{{ipAddressPool}}"',
          string(ipAddressPool)
        ))
        priority: 2100
      }
    }
  : {}

var dnsRuleCollectionGroup = includeDnsRules && length(dnsServerIPAddresses) > 0
  ? {
      DNS: {
        rules: json(replace(
          replace(
            loadTextContent('../../azure-firewall-rules/azFwPolRuleColls-DNS.jsonc'),
            '"{{dnsServerAddresses}}"',
            string(dnsServerIPAddresses)
          ),
          '"{{ipAddressPool}}"',
          string(ipAddressPool)
        ))
        priority: 2000
      }
    }
  : {}

var managementSubnetRuleCollectionGroup = includeManagementSubnetRules && length(managementSubnetRange) > 0
  ? {
      ManagementSubnet: {
        rules: json(replace(
          loadTextContent('../../azure-firewall-rules/azFwPolRuleColls-ManagementSubnet.jsonc'),
          '{{managementSubnetRange}}',
          managementSubnetRange
        ))
        priority: 5000
      }
    }
  : {}

var ruleCollectionGroupsAll = union(
  defaultRuleCollectionGroups,
  activeDirectoryRuleCollectionGroup,
  dnsRuleCollectionGroup,
  managementSubnetRuleCollectionGroup
)

// LATER: Divide into optional rule collections: AzurePlatform, AVDRDWeb (rename!), ResearchDataSources (?)

@batchSize(1) // Do not process more than one rule collection group at a time
resource ruleCollectionGroups 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-07-01' = [
  for group in items(ruleCollectionGroupsAll): {
    name: group.key
    parent: firewallPolicy
    properties: {
      priority: group.value.priority
      ruleCollections: group.value.rules
    }
  }
]

// In forced tunneling mode, there is only one public IP address, for the Management interface
// (Cannot reference the public IP address directly, as ARM wants both 0 and 1 index to exist when doing so)
var managementIPConfigPublicIPIndex = forcedTunneling ? 0 : 1

// Create Azure Firewall resource
resource firewall 'Microsoft.Network/azureFirewalls@2022-01-01' = {
  name: replace(namingStructure, '{rtype}', 'fw')
  location: location

  properties: {
    ipConfigurations: [
      {
        name: replace(namingStructure, '{rtype}', 'fwip')
        properties: {
          subnet: {
            id: firewallSubnetId
          }
          // If forced tunneling is enabled, the public IP address is not needed
          publicIPAddress: !forcedTunneling
            ? {
                id: firewallPublicIps[0].id
              }
            : null
        }
      }
    ]
    managementIpConfiguration: createManagementIPConfiguration
      ? {
          name: replace(namingStructure, '{rtype}', 'fwmgtip')
          properties: {
            publicIPAddress: {
              id: firewallPublicIps[managementIPConfigPublicIPIndex].id
            }
            subnet: {
              id: firewallManagementSubnetId
            }
          }
        }
      : null

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
  dependsOn: [ruleCollectionGroups]
}

output fwPrIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
