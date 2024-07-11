using '../main.bicep'

param backupPolicyName = ''
param recoveryServicesVaultId = ''

param namingStructure = 'test-test-{rtype}-eastus-01'
param location = 'eastus'

param subnetId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg-network-eastus-01/providers/Microsoft.Network/virtualNetworks/test-vnet-eastus-01/subnets/ComputeSubnet'

param tags = { test: 'value' }

param vmLocalAdminPassword = 'AzureUser'
param vmLocalAdminUsername = 'Test12341234'

param vmNamePrefix = 'vm-ad'
param vmSize = 'Standard_D2as_v5'
param vmCount = 1
param osType = 'Windows'

param logonType = 'ad'
param intuneEnrollment = false
param domainJoinUsername = 'admin@domain.example.com'
param domainJoinPassword = 'Test12341234'
param adDomainFqdn = 'domain.example.com'
param adOuPath = 'OU=Research,OU=Devices,DC=domain,DC=example,DC=com'
