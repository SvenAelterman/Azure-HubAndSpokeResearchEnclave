param keyVaultName string
param debugMode bool = false

@description('The length of time before the keys expire. Default 1 year.')
param keyValidityPeriod string = 'P1Y'
@description('The time period before key expiration to send a notification of expiration. Default 30 days.')
param notifyPeriod string = 'P30D'
@description('The time period before key expiration to renew the key. Default 60 days.')
param autoRotatePeriod string = 'P60D'
@description('The time value used to seed the keys\' expiration date. Defaults to the deployment time. Must be set to ensure repeatability.')
param keyExpirySeed string = utcNow()

// The initial expiry time of the keys. Default 1 year from deployment time.
var expiryDateTime = dateTimeAdd(keyExpirySeed, keyValidityPeriod)

// LATER: Read encryption keys and rotation settings from parameter JSON?
param keysToCreate array = [
  'diskEncryptionSet'
  'storage'
  'adf'
  'rsv'
]

var rotationPolicy = !debugMode ? {
  attributes: {
    expiryTime: keyValidityPeriod
  }
  lifetimeActions: [
    // Notify (using Event Grid) before key expires
    // LATER: Set up Event Grid subscription?
    // If the notify period is less than the rotate period, notification shouldn't be sent
    {
      action: {
        type: 'notify'
      }
      trigger: {
        timeBeforeExpiry: notifyPeriod
      }
    }
    // Rotate the key before it expires
    {
      action: {
        type: 'rotate'
      }
      trigger: {
        timeBeforeExpiry: autoRotatePeriod
      }
    }
  ]
} : null

var defaultKeyAttributes = {
  enabled: true
}
var keyExpiryAttributes = !debugMode ? {
  exp: dateTimeToEpoch(expiryDateTime)
} : {}
var actualKeyAttributes = union(defaultKeyAttributes, keyExpiryAttributes)

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource keys 'Microsoft.KeyVault/vaults/keys@2023-02-01' = [for key in keysToCreate: {
  name: key
  parent: keyVault
  properties: {
    attributes: actualKeyAttributes
    kty: 'RSA'
    rotationPolicy: rotationPolicy
  }
}]

output keys array = [for (key, i) in keysToCreate: {
  '${key}': {
    id: keys[i].id
    name: keys[i].name
    keyUri: keys[i].properties.keyUri
    keyUriWithVersion: keys[i].properties.keyUriWithVersion
  }
}]
