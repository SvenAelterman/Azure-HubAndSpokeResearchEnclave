using './main.bicep'

var workloadName = 'Spoke1'
param location = 'eastus'
// TODO: Change to namingConvention
param namingStructure = ''
param tags = {}
param vmNamePrefix = 'rvm-${workloadName}'
param vmCount = 1
param vmSize = 'Standard_D2as_v5'
param diskEncryptionSetId = ''
param subnetId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-vm/providers/Microsoft.Network/virtualNetworks/vnet/subnets/ComputeSubnet'

// Get these values from a Key Vault
param vmLocalAdminUsername = ''
param vmLocalAdminPassword = ''

param imageReference = {
  publisher: 'microsoftwindowsdesktop'
  offer: 'office-365'
  version: 'latest'
  sku: 'win11-23h2-avd-m365'
  // -- OR --
  id: '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-vnet/providers/Microsoft.Compute/galleries/gal/images/sample/versions/1.0.0'
}
param osType = 'Windows'

param logonType = 'entraID'
param intuneEnrollment = false
param backupPolicyName = ''
param recoveryServicesVaultId = ''
