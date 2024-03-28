using './main.bicep'

// Set these values to refer to the Key Vault that contains the deployment-support secrets (VM and domain join usernames/passwords)
var keyVaultSubscriptionId = ''
var keyVaultResourceGroupName = ''
var keyVaultName = ''

// Set these values based on the output of the hub deployment
param hubFirewallIp = ''
param hubVNetResourceId = ''
param hubPrivateDnsZonesResourceGroupId = ''
//

param location = 'eastus'
param workloadName = 'prj01'
param environment = 'dev'
param tags = {}
param sequence = 1
param namingConvention = '{workloadName}-{subWorkloadName}-{env}-{rtype}-{loc}-{seq}'
param networkAddressSpaces = ['10.27.${sequence - 1}.0/24']
param customDnsIps = []

param researcherEntraIdObjectId = ''
param adminEntraIdObjectId = ''
param logonType = 'entraID'

param filesIdentityType = logonType == 'entraID' ? 'AADKERB' : 'None'

param debugMode = true
param debugRemoteIp = ''
param debugPrincipalId = ''

param complianceTarget = 'NIST800171R2'
param encryptionKeyExpirySeed = '2024-03-02T21:45:00Z'

param desktopAppGroupFriendlyName = 'Research Spoke: ${workloadName} ${sequence}'
param workspaceFriendlyName = 'Research Spoke: ${workloadName} ${sequence}'
param useSessionHostAsResearchVm = true
param sessionHostCount = 1
param sessionHostLocalAdminUsername = az.getSecret(
  keyVaultSubscriptionId,
  keyVaultResourceGroupName,
  keyVaultName,
  'uark-local-username'
)
param sessionHostLocalAdminPassword = az.getSecret(
  keyVaultSubscriptionId,
  keyVaultResourceGroupName,
  keyVaultName,
  'uark-local-password'
)
param sessionHostNamePrefix = 'vm-${workloadName}-${sequence}'
param sessionHostSize = 'Standard_D2as_v5'

param airlockApproverEmail = ''

param isAirlockReviewCentralized = false
// Leave the next three parameter values empty if not using a centralized airlock review
param centralAirlockFileShareName = ''
param centralAirlockKeyVaultId = ''
param centralAirlockStorageAccountId = ''
