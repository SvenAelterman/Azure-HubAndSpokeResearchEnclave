targetScope = 'subscription'

param pricingTier string = 'Standard'

param plansToEnable array = [
  'StorageAccounts'
  'SqlServers'
  'VirtualMachines'
  'Arm'
  //'KeyVaults' -- TODO: Not available in Gov Cloud
]

// Enable one plan at a time
@batchSize(1)
resource DefenderPlan 'Microsoft.Security/pricings@2022-03-01' = [for plan in plansToEnable: {
  name: plan
  properties: {
    pricingTier: pricingTier
  }
}]
