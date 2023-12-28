using './main.bicep'

/*
 * A sample parameter file for Research Hub deployment using Entra ID for authentication.
 */

// aad: Use Azure Active Directory; ad: Use Active Directory (or AADDS)
param logonType = 'aad'

param tags = {
  lifetime: 'short'
}

param deployVpn = false
param researchVmsAreSessionHosts = true

param addAutoDateCreatedTag = false
param addDateModifiedTag = true

param networkAddressSpace = '10.40.0.0/16'
param customDnsIPs = [
  '10.40.6.4'
  '10.40.6.5'
]

param additionalSubnets = {
  aadds: {
    serviceEndpoints: []
    securityRules: [
      {
        name: 'AllowPSRemoting'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5986'
          sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 301
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowRD'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'CorpNetSaw'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 201
          direction: 'Inbound'
        }
      }
    ]
    delegation: ''
    order: 6
    subnetCidr: 24
  }
}
