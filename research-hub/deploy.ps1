<#
.SYNOPSIS
    Deploy the Research Hub resources to the target subscription.

.DESCRIPTION
    Deploy the Research Hub resources to the target subscription.

.PARAMETER TemplateParameterFile
    The path to the template parameter file in bicepparam format.

.PARAMETER TargetSubscriptionId
    The subscription ID to deploy the resources to. The subscription must already exist.

.PARAMETER Location
    The Azure region to deploy the resources to.

.EXAMPLE
    ./deploy.ps1 -TemplateParameterFile '.\main.hub.bicepparam' -TargetSubscriptionId '00000000-0000-0000-0000-000000000000' -Location 'eastus'

.EXAMPLE
    ./deploy.ps1 '.\main.hub.bicepparam' '00000000-0000-0000-0000-000000000000' 'eastus'
#>

# LATER: Be more specific about the required modules; it will speed up the initial call
#Requires -Modules "Az"
#Requires -PSEdition Core

[CmdletBinding()]
param (
    [Parameter(Mandatory, Position = 1)]
    [string]$TemplateParameterFile,
    [Parameter(Mandatory, Position = 2)]
    [string]$TargetSubscriptionId,
    [Parameter(Mandatory, Position = 3)]
    [string]$Location
)

# Define common parameters for the New-AzDeployment cmdlet
[hashtable]$CmdLetParameters = @{
    TemplateFile          = './main.bicep'
    TemplateParameterFile = $TemplateParameterFile
    Location              = $Location
}

Select-AzSubscription -Subscription $TargetSubscriptionId

[string]$DeploymentName = "ResearchHub-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)"
$CmdLetParameters.Add('Name', $DeploymentName)

$DeploymentResults = New-AzDeployment @CmdLetParameters

if ($DeploymentResults.ProvisioningState -eq 'Succeeded') {
    Write-Host "🔥 Deployment successful!"

    $DeploymentResults.Outputs
}
else {
    $DeploymentResults
}