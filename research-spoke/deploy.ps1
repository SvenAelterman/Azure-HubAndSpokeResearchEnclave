<#
.SYNOPSIS
    Performs a deployment of the Azure resources in a research spoke subscription.

.DESCRIPTION
    Use this for manual deployments only.
    If using a CI/CD pipeline, specify the necessary parameters in the pipeline definition.

.EXAMPLE
    .\deploy.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -Location 'eastus' -TemplateParameterFile '.\main.bicepparam'
#>

# LATER: Be more specific about the required modules; it will speed up the initial call
#Requires -Modules "Az"
#Requires -PSEdition Core

[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(Mandatory, Position = 1)]
    [string]$SubscriptionId,
    [Parameter(Mandatory, Position = 2)]
    [string]$Location,
    [Parameter(Mandatory, Position = 3)]
    [string]$TemplateParameterFile,
    [Parameter(Position = 4)]
    [string]$Environment = 'AzureCloud'
)

# Define common parameters for the New-AzDeployment cmdlet
[hashtable]$CmdLetParameters = @{
    TemplateFile = '.\main.bicep'
}

# Process the template parameter file and read relevant values for use here
Write-Verbose "Using template parameter file '$TemplateParameterFile'"
[string]$TemplateParameterJsonFile = [System.IO.Path]::ChangeExtension($TemplateParameterFile, 'json')
bicep build-params $TemplateParameterFile --outfile $TemplateParameterJsonFile

$CmdLetParameters.Add('TemplateParameterFile', $TemplateParameterJsonFile)

# Read the values from the parameters file, to use when generating the $DeploymentName value
$ParameterFileContents = (Get-Content $TemplateParameterJsonFile | ConvertFrom-Json)
$WorkloadName = $ParameterFileContents.parameters.workloadName.value

# Generate a unique name for the deployment
[string]$DeploymentName = "$WorkloadName-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)"
$CmdLetParameters.Add('Name', $DeploymentName)

$CmdLetParameters.Add('Location', $Location)

# Import the Azure subscription management module
Import-Module ..\scripts\PowerShell\Modules\AzSubscriptionManagement.psm1

# Determine if a cloud context switch is required
Set-AzContextWrapper -SubscriptionId $SubscriptionId -Environment $Environment

# Ensure the EncryptionAtHost feature is registered for the current subscription
# LATER: Do this with a deployment script
Register-AzProviderFeatureWrapper -ProviderNamespace "Microsoft.Compute" -FeatureName "EncryptionAtHost" -WhatIf:$WhatIfPreference

# Remove the module from the session
Remove-Module AzSubscriptionManagement

# Execute the deployment
$DeploymentResult = New-AzDeployment @CmdLetParameters -WhatIf:$WhatIfPreference

# Evaluate the deployment results
if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
    Write-Host "🔥 Deployment succeeded."
}
else {
    $DeploymentResult
}
