param vaultName string
param policyName string
// Additional backup management types are allowed but this module only supports these
param backupManagementType 'AzureIaasVm' | 'AzureStorage'

param workloadType 'AzureFileShare' | null

param retentionPolicy object
param schedulePolicy object

param timeZone string = 'UTC'

param azureBackupRGNamePrefix string = ''
param azureBackupRGNameSuffix string = ''

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = { name: vaultName }

resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: vault
  name: policyName
  properties: {
    #disable-next-line BCP036 // Our type is narrower than what's allowed
    backupManagementType: backupManagementType

    schedulePolicy: schedulePolicy

    retentionPolicy: retentionPolicy

    timeZone: timeZone

    // AzureIaasVm-specific properties
    instantRpRetentionRangeInDays: backupManagementType == 'AzureIaasVm' ? 2 : null
    policyType: backupManagementType == 'AzureIaasVm' ? 'V2' : null
    instantRPDetails: backupManagementType == 'AzureIaasVm'
      ? {
          azureBackupRGNamePrefix: azureBackupRGNamePrefix
          azureBackupRGNameSuffix: azureBackupRGNameSuffix
        }
      : null

    // AzureStorage-specific properties
    workloadType: backupManagementType == 'AzureIaasVm' ? null : workloadType
  }
}

output name string = backupPolicy.name
