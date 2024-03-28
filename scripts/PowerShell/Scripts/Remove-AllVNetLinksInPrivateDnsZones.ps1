[CmdletBinding()]
param (
    [Parameter(Position = 1)]
    [string]    $SubscriptionId,
    [Parameter(Position = 2)]
    [string]    $ResourceGroupName,
    [Parameter(Position = 3)]
    [string]$Environment = 'AzureCloud'
)

# Import the Azure subscription management module
Import-Module ..\Modules\AzSubscriptionManagement.psm1

# Determine if a cloud context switch is required
Set-AzContextWrapper -SubscriptionId $SubscriptionId -Environment $Environment

# Remove the module from the session
Remove-Module AzSubscriptionManagement -WhatIf:$false

# Get all private DNS zones in the specified resource group
$privateDnsZones = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName

# Iterate through each private DNS zone
foreach ($zone in $privateDnsZones) {
    Write-Verbose "Processing zone: $($zone.Name)"

    # Get all virtual networks linked to this DNS zone
    Get-AzPrivateDnsVirtualNetworkLink -ZoneName $zone.Name -ResourceGroupName $ResourceGroupName `
    | Remove-AzPrivateDnsVirtualNetworkLink
}

Write-Host "All virtual networks unlinked from all Azure Private DNS Zones in Resource Group '$ResourceGroupName'."
