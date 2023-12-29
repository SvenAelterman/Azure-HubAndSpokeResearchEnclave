param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string]$AzureDataFactoryName,
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

# Connect to Azure with the UAMI of the deploymentScript
Connect-AzAccount -Identity -Subscription $SubscriptionId

# Stop all started triggers in the Data Factory instance
Get-AzDataFactoryV2Trigger -DataFactoryName $AzureDataFactoryName -ResourceGroupName $ResourceGroupName | Where-Object { $_.RuntimeState -eq 'Started' } | Stop-AzDataFactoryV2Trigger -Force | Out-Null
