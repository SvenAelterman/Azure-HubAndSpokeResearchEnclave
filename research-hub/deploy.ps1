#Requires -Modules "Az"
#Requires -PSEdition Core

[CmdletBinding()]
param (
    # [Parameter()]
    # [string]$TenantId,
    [Parameter(Mandatory)]
    [string]$TargetSubscriptionId,
    [Parameter(Mandatory)]
    [string]$Location,
    [Parameter(Mandatory)]
    [string]$TemplateParameterFile
)

Select-AzSubscription -Subscription $TargetSubscriptionId

# TODO: Provide a name with timestamp for the deployment
$DeploymentResults = New-AzDeployment -TemplateFile '.\main.bicep' -TemplateParameterFile $TemplateParameterFile `
    -Location $Location

if ($DeploymentResults.ProvisioningState -eq 'Succeeded') {
    Write-Host "🔥 Deployment successful!"
}
else {
    $DeploymentResults
}