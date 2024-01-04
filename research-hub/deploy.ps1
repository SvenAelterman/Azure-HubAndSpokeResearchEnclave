<#
.SYNOPSIS
    Deploy the Research Hub resources to the target subscription.

.DESCRIPTION
    Deploy the Research Hub resources to the target subscription.

.PARAMETER TargetSubscriptionId
    The subscription ID to deploy the resources to. The subscription must already exist.

.PARAMETER Location
    The Azure region to deploy the resources to.

.PARAMETER TemplateParameterFile
    The path to the template parameter file in bicepparam format.

.EXAMPLE
    .\deploy.ps1 -TargetSubscriptionId '00000000-0000-0000-0000-000000000000' -Location 'eastus' -TemplateParameterFile '.\main.hub.bicepparam'
#>

# LATER: Be more specific about the required modules; it will speed up the initial call
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