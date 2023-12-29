param(
    [Parameter(Mandatory)]
    [array]$PrivateLinkResourceIds,
    [Parameter(Mandatory)]
    [array]$PrivateEndpointIds,
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

# Connect to Azure with the UAMI of the deploymentScript
Connect-AzAccount -Identity -Subscription $SubscriptionId

# Loop through all resources
foreach ($PrivateLinkResourceId in $PrivateLinkResourceIds) {
    # Approve pending private endpoints created by this deployment for the specified resource
    foreach ($PrivateLinkConnection in (Get-AzPrivateEndpointConnection -PrivateLinkResourceId $PrivateLinkResourceId)) {
        if ($PrivateLinkConnection.PrivateLinkServiceConnectionState.Status -eq "Pending") { 
            if ($PrivateLinkConnection.PrivateEndpoint.Id -in $PrivateEndpointIds) { 
                Write-Host "Approving private link connection for private endpoint $($PrivateLinkConnection.PrivateEndpoint.Id)"
                Approve-AzPrivateEndpointConnection -ResourceId $PrivateLinkConnection.id 
            }
            else {
                Write-Warning "Not approving private link connection for private endpoint $($PrivateLinkConnection.PrivateEndpoint.Id) because it was not created by this deployment."
            }
        } 
    }
}