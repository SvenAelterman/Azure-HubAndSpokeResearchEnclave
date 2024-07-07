param namingConvention string
param environment string
param sequenceFormatted string
param namingStructure string
param workloadName string
param userAssignedIdentityId string
param encryptionKeyUri string
param useCMK bool

param debugMode bool = false

param location string = resourceGroup().location
param tags object
param storageType string = 'GeoRedundant'

resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: replace(namingStructure, '{rtype}', 'rsv')
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }

  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }

  properties: {
    // Use only Azure Monitor for alerts
    monitoringSettings: {
      azureMonitorAlertSettings: {
        alertsForAllJobFailures: 'Enabled'
        // Only supported in later API versions
        // alertsForAllFailoverIssues: 'Enabled'
        // alertsForAllReplicationIssues: 'Enabled'
      }
      classicAlertSettings: {
        alertsForCriticalOperations: 'Disabled'
        // Only supported in later API versions
        // emailNotificationsForSiteRecovery: 'Disabled'
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
            useSystemAssignedIdentity: false
            userAssignedIdentity: userAssignedIdentityId
          }
          infrastructureEncryption: 'Enabled'
        }
      : null
  }
}

// Enable cross-region restores, which requires geo-redundant storage
resource backupStorageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2023-06-01' = {
  name: 'vaultstorageconfig'
  parent: recoveryServicesVault
  properties: {
    storageModelType: storageType
    storageType: storageType
    crossRegionRestoreFlag: true
  }
}

// Enable soft delete settings
resource backupConfig 'Microsoft.RecoveryServices/vaults/backupconfig@2023-06-01' = {
  name: 'vaultconfig'
  location: location
  parent: recoveryServicesVault
  properties: {
    enhancedSecurityState: debugMode ? 'Disabled' : 'Enabled'
    isSoftDeleteFeatureStateEditable: true
    softDeleteFeatureState: debugMode ? 'Disabled' : 'Enabled'
    storageModelType: backupStorageConfig.properties.storageModelType
    storageType: backupStorageConfig.properties.storageType
  }
}

// Create a new enhanced policy to use custom schedule
var backupTime = '2023-12-31T08:00:00.000Z'

// Break up the naming convention on the sequence placeholder to use for the backup RG name
var processNamingConventionPlaceholders = replace(
  replace(
    replace(replace(replace(namingConvention, '{workloadName}', workloadName), '{rtype}', 'rg'), '{loc}', location),
    '{env}',
    environment
  ),
  '-{subWorkloadName}',
  ''
)
var splitNamingConvention = split(processNamingConventionPlaceholders, '{seq}')
var azureBackupRGNamePrefix = '${splitNamingConvention[0]}${sequenceFormatted}-'
var azureBackupRGNameSuffix = length(splitNamingConvention) > 1 ? splitNamingConvention[1] : ''

resource enhancedBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-06-01' = {
  name: 'EnhancedPolicy-${workloadName}-${sequenceFormatted}'
  parent: recoveryServicesVault
  properties: {
    backupManagementType: 'AzureIaasVM'

    instantRPDetails: {
      // TODO: Follow naming convention
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
      // LATER: Parameterize RSV retention policy
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
output backupPolicyName string = enhancedBackupPolicy.name

// For debug purposes only
output backupResourceGroupNameStructure string = '${azureBackupRGNamePrefix}{N}${azureBackupRGNameSuffix}'
