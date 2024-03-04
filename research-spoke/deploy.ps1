<#
.SYNOPSIS
    Performs a deployment of the Azure resources in a research spoke subscription.

.DESCRIPTION
    Use this for manual deployments only.
    If using a CI/CD pipeline, specify the necessary parameters in the pipeline definition.

.PARAMETER TemplateParameterFile
    The path to the template parameter file in bicepparam format.

.PARAMETER TargetSubscriptionId
    The subscription ID to deploy the resources to. The subscription must already exist.

.PARAMETER Location
    The Azure region to deploy the resources to.

.EXAMPLE
    ./deploy.ps1 -TemplateParameterFile '.\main.prj.bicepparam' -TargetSubscriptionId '00000000-0000-0000-0000-000000000000' -Location 'eastus' 

    .EXAMPLE
    ./deploy.ps1 '.\main.prj.bicepparam' '00000000-0000-0000-0000-000000000000' 'eastus'
#>

# LATER: Be more specific about the required modules; it will speed up the initial call
#Requires -Modules "Az"
#Requires -PSEdition Core

[CmdletBinding()]
Param(
    [Parameter(Position = 1)]
    [string]$TemplateParameterFile = './main.bicepparam',
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

# Process the template parameter file and read relevant values for use here
Write-Verbose "Using template parameter file '$TemplateParameterFile'"
[string]$TemplateParameterJsonFile = [System.IO.Path]::ChangeExtension($TemplateParameterFile, 'json')
bicep build-params $TemplateParameterFile --outfile $TemplateParameterJsonFile

# Read the values from the parameters file, to use when generating the $DeploymentName value
$ParameterFileContents = (Get-Content $TemplateParameterJsonFile | ConvertFrom-Json)
$WorkloadName = $ParameterFileContents.parameters.workloadName.value

# Generate a unique name for the deployment
[string]$DeploymentName = "$WorkloadName-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)"
$CmdLetParameters.Add('Name', $DeploymentName)

# Import the Azure subscription management module
Import-Module ..\scripts\PowerShell\Modules\AzSubscriptionManagement.psm1

# Determine if a cloud context switch is required
Set-AzContextWrapper -SubscriptionId $TargetSubscriptionId -Environment $Environment

# Ensure the EncryptionAtHost feature is registered for the current subscription
# LATER: Do this with a deployment script in Bicep
Register-AzProviderFeatureWrapper -ProviderNamespace "Microsoft.Compute" -FeatureName "EncryptionAtHost"

# Remove the module from the session
Remove-Module AzSubscriptionManagement

# Execute the deployment
$DeploymentResult = New-AzDeployment @CmdLetParameters

# Evaluate the deployment results
if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
    Write-Host "🔥 Deployment succeeded."

    $DeploymentResult.Outputs
}
else {
    $DeploymentResult
}
