[CmdletBinding()]
param (
    # [Parameter()]
    # [string]$TenantId,
    [Parameter(Mandatory)]
    [string]$TargetSubscriptionId,
    [Parameter(Mandatory)]
    [string]$Location
)

Select-AzSubscription -Subscription $TargetSubscriptionId

$DeploymentResults = New-AzDeployment -TemplateFile .\main.bicep -TemplateParameterFile .\main.sample-parameters-aad.json `
    -Location $Location

if ($DeploymentResults.ProvisioningStatus -eq 'Succeeded') {
    Write-Host "🔥 Deployment successful!"
}
else {
    $DeploymentResults
}