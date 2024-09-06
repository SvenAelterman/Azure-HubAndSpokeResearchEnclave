param namingConvention string
param environment string
param sequenceFormatted string
param namingStructure string
param deploymentNameStructure string
param workloadName string
param encryptionKeyUri string
param useCMK bool
param roles object
param keyVaultResourceGroupName string
param keyVaultName string

param debugMode bool = false

param location string = resourceGroup().location
param tags object
param storageType string = 'GeoRedundant'

var vaultName = replace(namingStructure, '{rtype}', 'rsv')

resource keyVaultResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: keyVaultResourceGroupName
  scope: subscription()
}

resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    // Use only Azure Monitor for alerts
    monitoringSettings: {
      azureMonitorAlertSettings: {
        alertsForAllJobFailures: 'Enabled'
        // Only supported (and required) in later API versions
        alertsForAllFailoverIssues: 'Enabled'
        alertsForAllReplicationIssues: 'Enabled'
      }
      classicAlertSettings: {
        alertsForCriticalOperations: 'Disabled'
        // Only supported in later API versions
        emailNotificationsForSiteRecovery: 'Disabled'
      }
    }

    securitySettings: {
      // Default to immutable but don't lock the policy
      immutabilitySettings: {
        state: debugMode ? 'Disabled' : 'Unlocked'
      }
    }

    // Do not allow cross-subscription restores (to avoid leaking data between projects)
    restoreSettings: {
      crossSubscriptionRestoreSettings: {
        crossSubscriptionRestoreState: 'PermanentlyDisabled'
      }
    }

    publicNetworkAccess: 'Enabled'

    // Use a customer-managed key when not debugging and when specified
    encryption: !debugMode && useCMK
      ? {
          keyVaultProperties: {
            keyUri: encryptionKeyUri
          }
          kekIdentity: {
            useSystemAssignedIdentity: true
          }
          infrastructureEncryption: 'Enabled'
        }
      : null

    redundancySettings: {
      standardTierStorageRedundancy: storageType
      crossRegionRestore: 'Enabled'
    }
  }
}

// Create a role assignment on the Key Vault for the system-assigned managed identity of the vault
module keyVaultRoleAssignment '../../module-library/roleAssignments/roleAssignment-kv.bicep' = if (useCMK) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rsv-kv-rbac'), 80)
  scope: keyVaultResourceGroup
  params: {
    kvName: keyVaultName
    principalId: recoveryServicesVault.identity.principalId
    roleDefinitionId: roles.KeyVaultCryptoUser
    principalType: 'ServicePrincipal'
  }
}

// Enable soft delete settings
resource backupConfig 'Microsoft.RecoveryServices/vaults/backupconfig@2024-04-01' = {
  name: 'vaultconfig'
  location: location
  parent: recoveryServicesVault
  properties: {
    enhancedSecurityState: debugMode ? 'Disabled' : 'Enabled'
    isSoftDeleteFeatureStateEditable: true
    softDeleteFeatureState: debugMode ? 'Disabled' : 'Enabled'
  }
}

// Create a new enhanced policy to use custom schedule
var backupTime = '2023-12-31T08:00:00.000Z'

// Break up the naming convention on the sequence placeholder to use for the backup RG name
var processNamingConventionPlaceholders = replace(
  replace(
    replace(
      replace(replace(namingConvention, '{workloadName}', workloadName), '{rtype}', 'rg-backup'),
      '{loc}',
      location
    ),
    '{env}',
    environment
  ),
  '-{subWorkloadName}',
  ''
)
var splitNamingConvention = split(processNamingConventionPlaceholders, '{seq}')
var azureBackupRGNamePrefix = '${splitNamingConvention[0]}${sequenceFormatted}-'
var azureBackupRGNameSuffix = length(splitNamingConvention) > 1 ? splitNamingConvention[1] : ''

// LATER: Parameterize backup policy values
resource enhancedBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  name: 'EnhancedPolicy-${workloadName}-${sequenceFormatted}'
  parent: recoveryServicesVault
  properties: {
    backupManagementType: 'AzureIaasVM'

    instantRPDetails: {
      // Following the naming convention of the other resource groups
      azureBackupRGNamePrefix: azureBackupRGNamePrefix
      azureBackupRGNameSuffix: azureBackupRGNameSuffix
    }

    instantRpRetentionRangeInDays: 2
    timeZone: 'Central Standard Time'
    policyType: 'V2'

    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicyV2'
      scheduleRunFrequency: 'Hourly'
      hourlySchedule: {
        interval: 4
        scheduleWindowStartTime: backupTime
        scheduleWindowDuration: 4
      }
      dailySchedule: null
      weeklySchedule: null
    }

    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'

      dailySchedule: {
        retentionTimes: [backupTime]
        retentionDuration: {
          count: 8
          durationType: 'Days'
        }
      }

      weeklySchedule: {
        retentionTimes: [backupTime]
        retentionDuration: {
          count: 6
          durationType: 'Weeks'
        }
        daysOfTheWeek: ['Sunday']
      }

      monthlySchedule: {
        retentionTimes: [backupTime]
        retentionDuration: {
          count: 13
          durationType: 'Months'
        }
        retentionScheduleFormatType: 'Daily'
        retentionScheduleDaily: {
          daysOfTheMonth: [
            {
              date: 1
              isLast: false
            }
          ]
        }
        retentionScheduleWeekly: null
      }

      yearlySchedule: null
    }
  }
}

// Lock the Recovery Services Vault to prevent accidental deletion
resource lock 'Microsoft.Authorization/locks@2020-05-01' = if (!debugMode) {
  name: replace(namingStructure, '{rtype}', 'rsv-lock')
  scope: recoveryServicesVault
  properties: {
    level: 'CanNotDelete'
  }
}

output id string = recoveryServicesVault.id
output name string = recoveryServicesVault.name
output backupPolicyName string = enhancedBackupPolicy.name

// For debug purposes only
output backupResourceGroupNameStructure string = '${azureBackupRGNamePrefix}{N}${azureBackupRGNameSuffix}'
