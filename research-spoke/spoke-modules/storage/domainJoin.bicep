param storageAccountName string
param storageObjectsRgName string
param storagePurpose string
param identityDomainName string
param identityServiceProvider string
param workloadSubsId string
param adminUserName string
param useCustomOUPath string = 'true'
param ouStgPath string = ''
param fileShareName string
param managedIdentityClientId string
param securityPrincipalName string = 'none'
param storageAccountFqdn string
@secure()
param adminUserPassword string

param hubManagementVmName string

var dscAgentPackageLocation = 'https://github.com/Azure/avdaccelerator/raw/main/workload/scripts/DSCStorageScripts/1.0.0/DSCStorageScripts.zip'

var scriptArguments = '-DscPath ${dscAgentPackageLocation} -StorageAccountName ${storageAccountName} -StorageAccountRG ${storageObjectsRgName} -StoragePurpose ${storagePurpose} -DomainName ${identityDomainName} -IdentityServiceProvider ${identityServiceProvider} -AzureCloudEnvironment ${az.environment().name} -SubscriptionId ${workloadSubsId} -AdminUserName ${adminUserName} -CustomOuPath ${useCustomOUPath} -OUName "${ouStgPath}" -ShareName ${fileShareName} -ClientId ${managedIdentityClientId} -SecurityPrincipalName "${securityPrincipalName}" -StorageAccountFqdn ${storageAccountFqdn} '
var file = 'Manual-DSC-Storage-Scripts.ps1'

resource managementVm 'Microsoft.Compute/virtualMachines@2024-03-01' existing = {
  name: hubManagementVmName
}

resource customStorageScript 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = {
  name: 'AzureFilesDomainJoin'
  parent: managementVm
  location: resourceGroup().location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      fileUris: array('https://raw.githubusercontent.com/Azure/avdaccelerator/main/workload/scripts/${file}')
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File ./${file} ${scriptArguments} -AdminUserPassword "${replace(adminUserPassword, '"', '""')}" -Verbose'
    }
  }
}
