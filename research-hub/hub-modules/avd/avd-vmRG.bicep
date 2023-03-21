targetScope = 'subscription'

param hostPoolRegistrationToken string
param hostPoolName string
param namingStructure string
param avdVmHostNameStructure string
param avdSubnetId string
param tags object

param location string = deployment().location
param deploymentNameStructure string
param vmCount int = 1

// If needed, create a separate resource group for the VMs
resource avdVmResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(namingStructure, '{rtype}', 'rg')
  location: location
  tags: tags
}

module avdVm 'avd-vm.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'avdvm-vms')
  scope: avdVmResourceGroup
  params: {
    namingStructure: namingStructure
    hostPoolRegistrationToken: hostPoolRegistrationToken
    location: location
    deploymentNameStructure: deploymentNameStructure
    vmCount: vmCount
    avdVmHostNameStructure: avdVmHostNameStructure
    hostPoolName: hostPoolName
    avdSubnetId: avdSubnetId
  }
}
