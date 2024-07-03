param namingConvention string
param workloadName string
param userAssignedIdentityId string
param encryptionKeyUri string

param location string = resourceGroup().location
param tags object

resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: replace(namingConvention, '{rtype}', 'rsv')
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
    monitoringSettings: {
      // Use only Azure Monitor for alerts
      azureMonitorAlertSettings: {
        alertsForAllJobFailures: 'Enabled'
      }
      classicAlertSettings: {
        alertsForCriticalOperations: 'Disabled'
      }
    }

    securitySettings: {
      // Default to immutable but don't lock the policy
      immutabilitySettings: {
        state: 'Unlocked'
      }
      // Enforce 14 day soft delete
      softDeleteSettings: {
        softDeleteRetentionPeriodInDays: 14
        softDeleteState: 'AlwaysON'
      }
    }

    // Do not allow cross-subscription restores (to avoid leaking data between projects)
    restoreSettings: {
      crossSubscriptionRestoreSettings: {
        crossSubscriptionRestoreState: 'PermanentlyDisabled'
      }
    }

    publicNetworkAccess: 'Enabled'

    // Use a customer-managed key for compliance with NIST 800-171 R2 policy
    encryption: {
      keyVaultProperties: {
        keyUri: encryptionKeyUri
      }
      kekIdentity: {
        useSystemAssignedIdentity: false
        userAssignedIdentity: userAssignedIdentityId
      }
      infrastructureEncryption: 'Enabled'
    }
  }
}

// Enable cross-region restores, which requires geo-redundant storage
resource backupStorageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2023-06-01' = {
  name: 'vaultstorageconfig'
  parent: recoveryServicesVault
  properties: {
    storageType: 'GeoRedundant'
    crossRegionRestoreFlag: true
  }
}

// Create a new enhanced policy to use custom schedule
var backupTime = '2023-12-31T08:00:00.000Z'

resource enhancedBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-06-01' = {
  name: 'EnhancedPolicy-${workloadName}'
  parent: recoveryServicesVault
  properties: {
    backupManagementType: 'AzureIaasVM'

    instantRPDetails: {
      // TODO: Follow naming convention
      azureBackupRGNamePrefix: 'rg-backup-${location}-${workloadName}-'
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
resource lock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: replace(namingConvention, '{rtype}', 'rsv-lock')
  scope: recoveryServicesVault
  properties: {
    level: 'CanNotDelete'
  }
}

output id string = recoveryServicesVault.id
output backupPolicyName string = enhancedBackupPolicy.name
