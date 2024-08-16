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

.EXAMPLE
    ./deploy.ps1 '.\main.hub.bicepparam' '00000000-0000-0000-0000-000000000000' 'eastus' 'AzureUSGovernment'
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
    [string]$Location,
    [Parameter(Position = 4)]
    [string]$Environment = 'AzureCloud'
)

# Define common parameters for the New-AzDeployment cmdlet
[hashtable]$CmdLetParameters = @{
    TemplateFile          = './main.bicep'
    TemplateParameterFile = $TemplateParameterFile
    Location              = $Location
}

Write-Verbose "Using template parameter file '$TemplateParameterFile'"
[string]$TemplateParameterJsonFile = [System.IO.Path]::ChangeExtension($TemplateParameterFile, 'json')
bicep build-params $TemplateParameterFile --outfile $TemplateParameterJsonFile

# Read the values from the parameters file, to use when generating the $DeploymentName value
$ParameterFileContents = (Get-Content $TemplateParameterJsonFile | ConvertFrom-Json)
$WorkloadName = $ParameterFileContents.parameters.workloadName.value
$ImagingSubscriptionId = $ParameterFileContents.parameters.imageBuildSubscriptionId.value

# Import the Azure subscription management module
Import-Module ..\scripts\PowerShell\Modules\AzSubscriptionManagement.psm1

# Determine if a cloud context switch is required for configuring the image build subscription, which could be different from the hub subscription
Set-AzContextWrapper -SubscriptionId $ImagingSubscriptionId -Environment $Environment

# LATER: Run provider and feature registrations in parallel
Register-AzResourceProviderWrapper -ProviderNamespace "Microsoft.Storage"
Register-AzResourceProviderWrapper -ProviderNamespace "Microsoft.ContainerInstance" # For image builder

# Determine if a cloud context switch is required
Set-AzContextWrapper -SubscriptionId $TargetSubscriptionId -Environment $Environment

# Ensure the EncryptionAtHost feature is registered for the current subscription
# LATER: Do this with a deployment script in Bicep
Register-AzProviderFeatureWrapper -ProviderNamespace "Microsoft.Compute" -FeatureName "EncryptionAtHost"
# Remove the module from the session (always, even in WhatIf mode)
Remove-Module AzSubscriptionManagement -WhatIf:$false

[string]$DeploymentName = "$WorkloadName-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)"
$CmdLetParameters.Add('Name', $DeploymentName)

$DeploymentResults = New-AzDeployment @CmdLetParameters

if ($DeploymentResults.ProvisioningState -eq 'Succeeded') {
    Write-Host "🔥 Deployment successful!"

    $DeploymentResult.Outputs | Format-Table -Property Key, @{Name = 'Value'; Expression = { $_.Value.Value } }
}
else {
    $DeploymentResults
}