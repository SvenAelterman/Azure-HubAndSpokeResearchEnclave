using '../main.bicep'

// TODO: Create custom rule to require backup
param backupPolicyName = ''
param recoveryServicesVaultId = ''

param logonType = 'entraID'
param intuneEnrollment = false

param namingStructure = 'test-test-{rtype}-eastus-01'
param location = 'eastus'

param subnetId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg-network-eastus-01/providers/Microsoft.Network/virtualNetworks/test-vnet-eastus-01/subnets/ComputeSubnet'

// Set at least one tag to avoid a failure
param tags = { test: 'value' }

param vmLocalAdminPassword = 'AzureUser'
param vmLocalAdminUsername = 'Test12341234'

param vmNamePrefix = 'vm-ad'
param osType = 'Windows'
param vmCount = 1
param vmSize = 'Standard_D2as_v5'
