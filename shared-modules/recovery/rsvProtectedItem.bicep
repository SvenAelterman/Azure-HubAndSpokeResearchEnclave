param backupPolicyName string
param recoveryServicesVaultId string
param virtualMachineId string

var rsvName = split(recoveryServicesVaultId, '/')[8]
var virtualMachineRgName = split(virtualMachineId, '/')[4]
var virtualMachineName = split(virtualMachineId, '/')[8]

resource protectedItem 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-06-01' = {
  name: '${rsvName}/Azure/iaasvmcontainer;iaasvmcontainerv2;${virtualMachineRgName};${virtualMachineName}/vm;iaasvmcontainerv2;${virtualMachineRgName};${virtualMachineName}'
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    sourceResourceId: virtualMachineId
    policyId: resourceId('Microsoft.RecoveryServices/vaults/backupPolicies', rsvName, backupPolicyName) // '${recoveryServicesVaultId}/backupPolicies/${backupPolicyName}'
  }
}
