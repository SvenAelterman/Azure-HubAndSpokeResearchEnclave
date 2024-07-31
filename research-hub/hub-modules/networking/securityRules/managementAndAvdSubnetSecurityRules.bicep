param deploySubnet bool
param includeDnsFirewallRules bool
param includeActiveDirectoryFirewallRules bool

param customDnsIPs array
param domainControllerIPAddresses array

param applicationSecurityGroupId string

var dnsSecurityRule = deploySubnet && includeDnsFirewallRules
  ? [
      {
        name: 'Allow_Outbound_DNS'
        properties: {
          direction: 'Outbound'
          priority: 200
          protocol: '*'
          access: 'Allow'
          sourceApplicationSecurityGroups: [
            {
              id: applicationSecurityGroupId
            }
          ]
          sourcePortRange: '*'
          destinationAddressPrefixes: customDnsIPs
          destinationPortRanges: ['53']
        }
      }
    ]
  : []

var addcSecurityRule = deploySubnet && includeActiveDirectoryFirewallRules
  ? [
      {
        name: 'Allow_Outbound_ADDC'
        properties: {
          direction: 'Outbound'
          priority: 210
          protocol: '*' // TCP, UDP, and also allows ICMP echo, which is a benefit
          access: 'Allow'
          sourceApplicationSecurityGroups: [
            {
              id: applicationSecurityGroupId
            }
          ]
          sourcePortRange: '*'
          destinationAddressPrefixes: domainControllerIPAddresses
          destinationPortRanges: ['88', '123', '135', '138', '389', '445', '636', '3268-3269', '9389', '49152-65535']
        }
      }
    ]
  : []

output securityRules array = union(dnsSecurityRule, addcSecurityRule)
