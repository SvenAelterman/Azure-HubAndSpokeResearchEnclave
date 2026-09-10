[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[Parameter(Mandatory)]
	[string]$VaultName,
	[Parameter(Mandatory)]
	[string]$ResourceGroup,
	[Parameter(Mandatory)]
	[string]$SubscriptionId,
	[Parameter()]
	[string]$Tenant = (Get-AzContext).Tenant.Id
)

# LATER: Add PS version check (7)
# LATER: Add SYNOPSIS, DESCRIPTION, EXAMPLES, PARAMETERS

$RSmodule = Get-Module -Name Az.RecoveryServices -ListAvailable
$NWmodule = Get-Module -Name Az.Network -ListAvailable
$RSversion = $RSmodule.Version.ToString()
$NWversion = $NWmodule.Version.ToString()

if ($RSversion -lt "5.3.0") {
	Uninstall-Module -Name Az.RecoveryServices
	Set-ExecutionPolicy -ExecutionPolicy Unrestricted
	Install-Module -Name Az.RecoveryServices -Repository PSGallery -Force -AllowClobber
}

if ($NWversion -lt "4.15.0") {
	Uninstall-Module -Name Az.Network
	Set-ExecutionPolicy -ExecutionPolicy Unrestricted
	Install-Module -Name Az.Network -Repository PSGallery -Force -AllowClobber
}

Select-AzSubscription $SubscriptionId -Tenant $Tenant | Out-Null
$VaultToDelete = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroup
if ($null -eq $VaultToDelete) {
	Write-Error "Recovery Services Vault '$VaultName' was not found in resource group '$ResourceGroup'."
	return
}
Write-Verbose "Selected Recovery Services Vault: $($VaultToDelete.Name) in Resource Group: $($VaultToDelete.ResourceGroupName)`n$($VaultToDelete.ID)"
# Ignore WhatIfPreference here because future cmdlets will fail without this being set
# This should have no side effects
# Set-AzRecoveryServicesAsrVaultContext -Vault $VaultToDelete -WhatIf:$false
#Set-AzRecoveryServicesVaultContext -Vault $VaultToDelete #-WhatIf:$false

$UpdatedVault = Update-AzRecoveryServicesVault -ResourceGroupName $VaultToDelete.ResourceGroupName -Name $VaultToDelete.Name -ImmutabilityState "Disabled"
Write-Host "Immutability state set to '$($UpdatedVault.Properties.ImmutabilitySettings.ImmutabilityState)'."

# HACK: 2025-11-16: svaelter: Can no longer disable soft delete in any region for a Recovery Services Vault.
# Ref: https://learn.microsoft.com/azure/backup/secure-by-default?tabs=preview#supported-scenarios
#Set-AzRecoveryServicesVaultProperty -Vault $VaultToDelete.ID -SoftDeleteFeatureState Disable #disable soft delete
#Write-Host "Soft delete disabled for the vault" $VaultName
# $containerSoftDelete = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $VaultToDelete.ID | Where-Object { $_.DeleteState -eq "ToBeDeleted" } #fetch backup items in soft delete state
# foreach ($softitem in $containerSoftDelete) {
# 	Undo-AzRecoveryServicesBackupItemDeletion -Item $softitem -VaultId $VaultToDelete.ID -Force #undelete items in soft delete state
# }

# # Fetch MSSQL backup items in soft delete state
# $containerSoftDeleteSql = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $VaultToDelete.ID | Where-Object { $_.DeleteState -eq "ToBeDeleted" }
# foreach ($softitemsql in $containerSoftDeleteSql) {
# 	Undo-AzRecoveryServicesBackupItemDeletion -Item $softitemsql -VaultId $VaultToDelete.ID -Force #undelete items in soft delete state
# }

# Invoking API to disable Security features (Enhanced Security) to remove MARS/MAB/DPM servers.
#Set-AzRecoveryServicesVaultProperty -VaultId $VaultToDelete.ID -DisableHybridBackupSecurityFeature $true
#Write-Host "Disabled Security features for the vault"

# Fetch all protected items and servers
$backupItemsVM = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $VaultToDelete.ID
$backupItemsSQL = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $VaultToDelete.ID
$backupItemsAFS = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureStorage -WorkloadType AzureFiles -VaultId $VaultToDelete.ID
$backupItemsSAP = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType SAPHanaDatabase -VaultId $VaultToDelete.ID
$backupContainersSQL = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVMAppContainer -VaultId $VaultToDelete.ID | Where-Object { $_.ExtendedInfo.WorkloadType -eq "SQL" }
$protectableItemsSQL = Get-AzRecoveryServicesBackupProtectableItem -WorkloadType MSSQL -VaultId $VaultToDelete.ID | Where-Object { $_.IsAutoProtected -eq $true }
$backupContainersSAP = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVMAppContainer -VaultId $VaultToDelete.ID | Where-Object { $_.ExtendedInfo.WorkloadType -eq "SAPHana" }
$StorageAccounts = Get-AzRecoveryServicesBackupContainer -ContainerType AzureStorage -VaultId $VaultToDelete.ID
$backupServersMARS = Get-AzRecoveryServicesBackupContainer -ContainerType "Windows" -BackupManagementType MAB -VaultId $VaultToDelete.ID
$backupServersMABS = Get-AzRecoveryServicesBackupManagementServer -VaultId $VaultToDelete.ID | Where-Object { $_.BackupManagementType -eq "AzureBackupServer" }
$backupServersDPM = Get-AzRecoveryServicesBackupManagementServer -VaultId $VaultToDelete.ID | Where-Object { $_.BackupManagementType -eq "SCDPM" }
$pvtEndpoints = Get-AzPrivateEndpointConnection -PrivateLinkResourceId $VaultToDelete.ID

foreach ($item in $backupItemsVM) {
	Disable-AzRecoveryServicesBackupProtection -Item $item -VaultId $VaultToDelete.ID -RemoveRecoveryPoints -Force #stop backup and delete Azure VM backup items
}
Write-Host "Disabled and deleted Azure VM backup items"

foreach ($item in $backupItemsSQL) {
	Disable-AzRecoveryServicesBackupProtection -Item $item -VaultId $VaultToDelete.ID -RemoveRecoveryPoints -Force #stop backup and delete SQL Server in Azure VM backup items
}
Write-Host "Disabled and deleted SQL Server backup items"

foreach ($item in $protectableItemsSQL) {
	Disable-AzRecoveryServicesBackupAutoProtection -BackupManagementType AzureWorkload -WorkloadType MSSQL -InputItem $item -VaultId $VaultToDelete.ID #disable auto-protection for SQL
}
Write-Host "Disabled auto-protection and deleted SQL protectable items"

foreach ($item in $backupContainersSQL) {
	Unregister-AzRecoveryServicesBackupContainer -Container $item -Force -VaultId $VaultToDelete.ID #unregister SQL Server in Azure VM protected server
}
Write-Host "Deleted SQL Servers in Azure VM containers"

foreach ($item in $backupItemsSAP) {
	Disable-AzRecoveryServicesBackupProtection -Item $item -VaultId $VaultToDelete.ID -RemoveRecoveryPoints -Force #stop backup and delete SAP HANA in Azure VM backup items
}
Write-Host "Disabled and deleted SAP HANA backup items"

foreach ($item in $backupContainersSAP) {
	Unregister-AzRecoveryServicesBackupContainer -Container $item -Force -VaultId $VaultToDelete.ID #unregister SAP HANA in Azure VM protected server
}
Write-Host "Deleted SAP HANA in Azure VM containers"

foreach ($item in $backupItemsAFS) {
	Disable-AzRecoveryServicesBackupProtection -Item $item -VaultId $VaultToDelete.ID -RemoveRecoveryPoints -Force #stop backup and delete Azure File Shares backup items
}
Write-Host "Disabled and deleted Azure File Share backups"

foreach ($item in $StorageAccounts) {
	Unregister-AzRecoveryServicesBackupContainer -container $item -Force -VaultId $VaultToDelete.ID #unregister storage accounts
}
Write-Host "Unregistered Storage Accounts"

foreach ($item in $backupServersMARS) {
	Unregister-AzRecoveryServicesBackupContainer -Container $item -Force -VaultId $VaultToDelete.ID #unregister MARS servers and delete corresponding backup items
}
Write-Host "Deleted MARS Servers"

foreach ($item in $backupServersMABS) {
	Unregister-AzRecoveryServicesBackupManagementServer -AzureRmBackupManagementServer $item -VaultId $VaultToDelete.ID #unregister MABS servers and delete corresponding backup items
}
Write-Host "Deleted MAB Servers"

foreach ($item in $backupServersDPM) {
	Unregister-AzRecoveryServicesBackupManagementServer -AzureRmBackupManagementServer $item -VaultId $VaultToDelete.ID #unregister DPM servers and delete corresponding backup items
}
Write-Host "Deleted DPM Servers"
Write-Host "Ensure that you stop protection and delete backup items from the respective MARS, MAB and DPM consoles as well. Visit https://go.microsoft.com/fwlink/?linkid=2186234 to learn more." -ForegroundColor Yellow

# Deletion of ASR Items
# HACK: 2025-12-30: svaelter: This call fails but there should be no Site Recovery on this vault
# $fabricObjects = Get-AzRecoveryServicesAsrFabric
# if ($null -ne $fabricObjects) {
# 	# First DisableDR all VMs.
# 	foreach ($fabricObject in $fabricObjects) {
# 		$containerObjects = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabricObject
# 		foreach ($containerObject in $containerObjects) {
# 			$protectedItems = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $containerObject
# 			# DisableDR all protected items
# 			foreach ($protectedItem in $protectedItems) {
# 				Write-Host "Triggering DisableDR(Purge) for item:" $protectedItem.Name
# 				Remove-AzRecoveryServicesAsrReplicationProtectedItem -InputObject $protectedItem -Force
# 				Write-Host "DisableDR(Purge) completed"
# 			}

# 			$containerMappings = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $containerObject
# 			# Remove all Container Mappings
# 			foreach ($containerMapping in $containerMappings) {
# 				Write-Host "Triggering Remove Container Mapping: " $containerMapping.Name
# 				Remove-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainerMapping $containerMapping -Force
# 				Write-Host "Removed Container Mapping."
# 			}
# 		}
# 		$NetworkObjects = Get-AzRecoveryServicesAsrNetwork -Fabric $fabricObject
# 		foreach ($networkObject in $NetworkObjects) {
# 			# Get the PrimaryNetwork
# 			$PrimaryNetwork = Get-AzRecoveryServicesAsrNetwork -Fabric $fabricObject -FriendlyName $networkObject
# 			$NetworkMappings = Get-AzRecoveryServicesAsrNetworkMapping -Network $PrimaryNetwork
# 			foreach ($networkMappingObject in $NetworkMappings) {
# 				# Get the Network Mappings
# 				$NetworkMapping = Get-AzRecoveryServicesAsrNetworkMapping -Name $networkMappingObject.Name -Network $PrimaryNetwork
# 				Remove-AzRecoveryServicesAsrNetworkMapping -InputObject $NetworkMapping
# 			}
# 		}
# 		# Remove Fabric
# 		Write-Host "Triggering Remove Fabric:" $fabricObject.FriendlyName
# 		Remove-AzRecoveryServicesAsrFabric -InputObject $fabricObject -Force
# 		Write-Host "Removed Fabric."
# 	}
# }

#Write-Host "Warning: This script will only remove the replication configuration from Azure Site Recovery and not from the source. Please cleanup the source manually. Visit https://go.microsoft.com/fwlink/?linkid=2182781 to learn more." -ForegroundColor Yellow

foreach ($item in $pvtEndpoints) {
	$penamesplit = $item.Name.Split(".")
	$pename = $penamesplit[0]
	Remove-AzPrivateEndpointConnection -ResourceId $item.Id -Force #remove private endpoint connections
	Remove-AzPrivateEndpoint -Name $pename -ResourceGroupName $ResourceGroup -Force #remove private endpoints
}
Write-Host "Removed Private Endpoints"

# Recheck ASR items in vault
# $fabricCount = 0
# $ASRProtectedItems = 0
# $ASRPolicyMappings = 0
# $fabricObjects = Get-AzRecoveryServicesAsrFabric
# if ($null -ne $fabricObjects) {
# 	foreach ($fabricObject in $fabricObjects) {
# 		$containerObjects = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabricObject
# 		foreach ($containerObject in $containerObjects) {
# 			$protectedItems = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $containerObject
# 			foreach ($protectedItem in $protectedItems) {
# 				$ASRProtectedItems++
# 			}
# 			$containerMappings = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $containerObject
# 			foreach ($containerMapping in $containerMappings) {
# 				$ASRPolicyMappings++
# 			}
# 		}
# 		$fabricCount++
# 	}
# }

# Recheck presence of backup items in vault
# $backupItemsVMFin = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $VaultToDelete.ID
# $backupItemsSQLFin = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $VaultToDelete.ID
# $backupContainersSQLFin = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVMAppContainer -VaultId $VaultToDelete.ID | Where-Object { $_.ExtendedInfo.WorkloadType -eq "SQL" }
# $protectableItemsSQLFin = Get-AzRecoveryServicesBackupProtectableItem -WorkloadType MSSQL -VaultId $VaultToDelete.ID | Where-Object { $_.IsAutoProtected -eq $true }
# $backupItemsSAPFin = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType SAPHanaDatabase -VaultId $VaultToDelete.ID
# $backupContainersSAPFin = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVMAppContainer -VaultId $VaultToDelete.ID | Where-Object { $_.ExtendedInfo.WorkloadType -eq "SAPHana" }
# $backupItemsAFSFin = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureStorage -WorkloadType AzureFiles -VaultId $VaultToDelete.ID
# $StorageAccountsFin = Get-AzRecoveryServicesBackupContainer -ContainerType AzureStorage -VaultId $VaultToDelete.ID
# $backupServersMARSFin = Get-AzRecoveryServicesBackupContainer -ContainerType "Windows" -BackupManagementType MAB -VaultId $VaultToDelete.ID
# $backupServersMABSFin = Get-AzRecoveryServicesBackupManagementServer -VaultId $VaultToDelete.ID | Where-Object { $_.BackupManagementType -eq "AzureBackupServer" }
# $backupServersDPMFin = Get-AzRecoveryServicesBackupManagementServer -VaultId $VaultToDelete.ID | Where-Object { $_.BackupManagementType -eq "SCDPM" }
$pvtEndpointsFin = Get-AzPrivateEndpointConnection -PrivateLinkResourceId $VaultToDelete.ID

# Display items which are still present in the vault and might be preventing vault deletion.
# HACK: These don't make sense anymore because the counts will be > 0 with soft delete enabled
# if ($backupItemsVMFin.count -ne 0) { Write-Host $backupItemsVMFin.count "Azure VM backups are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupItemsSQLFin.count -ne 0) { Write-Host $backupItemsSQLFin.count "SQL Server Backup Items are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupContainersSQLFin.count -ne 0) { Write-Host $backupContainersSQLFin.count "SQL Server Backup Containers are still registered to the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($protectableItemsSQLFin.count -ne 0) { Write-Host $protectableItemsSQLFin.count "SQL Server Instances are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupItemsSAPFin.count -ne 0) { Write-Host $backupItemsSAPFin.count "SAP HANA Backup Items are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupContainersSAPFin.count -ne 0) { Write-Host $backupContainersSAPFin.count "SAP HANA Backup Containers are still registered to the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupItemsAFSFin.count -ne 0) { Write-Host $backupItemsAFSFin.count "Azure File Shares are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($StorageAccountsFin.count -ne 0) { Write-Host $StorageAccountsFin.count "Storage Accounts are still registered to the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupServersMARSFin.count -ne 0) { Write-Host $backupServersMARSFin.count "MARS Servers are still registered to the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupServersMABSFin.count -ne 0) { Write-Host $backupServersMABSFin.count "MAB Servers are still registered to the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($backupServersDPMFin.count -ne 0) { Write-Host $backupServersDPMFin.count "DPM Servers are still registered to the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($ASRProtectedItems -ne 0) { Write-Host $ASRProtectedItems "ASR protected items are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($ASRPolicyMappings -ne 0) { Write-Host $ASRPolicyMappings "ASR policy mappings are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
# if ($fabricCount -ne 0) { Write-Host $fabricCount "ASR Fabrics are still present in the vault. Remove the same for successful vault deletion." -ForegroundColor Red }
if ($pvtEndpointsFin.count -ne 0) { Write-Host $pvtEndpointsFin.count "Private endpoints are still linked to the vault. Remove the same for successful vault deletion." -ForegroundColor Red }

if ($PSCmdlet.ShouldProcess($VaultName, "DELETE")) {
	$RestMethodParameters = @{
		Method               = 'DELETE'
		SubscriptionId       = $SubscriptionId
		ResourceGroupName    = $ResourceGroup
		ResourceProviderName = 'Microsoft.RecoveryServices'
		ResourceType         = 'vaults'
		Name                 = $VaultName
		ApiVersion           = '2025-08-01'
	}

	$Response = Invoke-AzRestMethod @RestMethodParameters #-WaitForCompletion
	
	Write-Verbose "DELETE HTTP request returned status code: $($Response.StatusCode)"

	# If the operation is asynchronous
	if ($Response.StatusCode -eq 202) {
		$headers = $Response.Headers
		Write-Verbose "Response headers: $($headers | Out-String)"

		# Get the URL to track operation status
		# Prefer Azure-AsyncOperation; fall back to Location if not present
		[string]$OperationUrl = $null
		if ($headers.Contains("Azure-AsyncOperation")) {
			$OperationUrl = $headers.GetValues("Azure-AsyncOperation")[0]
		}
		elseif ($headers.Contains("Location")) {
			$OperationUrl = $headers.GetValues("Location")[0]
		}

		if (-not $OperationUrl) {
			throw "202 Accepted without Azure-AsyncOperation or Location headers; cannot poll operation. Your vault deletion may still succeed."
		}
		else {
			Write-Verbose "Polling operation status at: '$OperationUrl'"

			# Derive AzRestMethod path from full URL; need to remove 'https://management.azure.com' prefix but not the `/`
			# https://learn.microsoft.com/powershell/module/az.accounts/invoke-azrestmethod?view=azps-15.1.0#-path
			[string]$RegexEscapedResourceManagerUrl = [Regex]::Escape((Get-AzContext).Environment.ResourceManagerUrl)
			$AzRestMethodPath = $OperationUrl -replace "^$RegexEscapedResourceManagerUrl", "/"
			Write-Verbose "Derived AzRestMethod path: '$AzRestMethodPath'"
		}

		# Polling parameters
		[int]$PollIntervalSec = [int]($headers.GetValues("Retry-After")?[0]) ?? 20

		[int]$MaxWaitMinutes = 10      # overall timeout budget
		$Deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
		[int]$Attempt = 0

		while ((Get-Date) -lt $Deadline) {
			$Attempt++

			$opResponse = Invoke-AzRestMethod -Method GET -Path $AzRestMethodPath -ErrorAction SilentlyContinue

			# If the polling request returns 404 Not Found, it means that the resource is deleted
			if (404 -eq $opResponse.StatusCode) {
				# Some services return 404 Not Found when the resource is deleted
				Write-Host "DELETE operation succeeded (resource not found)."
				break
			}

			# Attempt to parse JSON; handle cases where content may be empty or non-JSON
			$opJson = $opResponse.Content | ConvertFrom-Json -ErrorAction SilentlyContinue

			# If the conversion to JSON succeeded and there is a 'status' property
			$Status = ${opJson}?.status
			
			# If there is no status property or the conversion failed
			if ($null -eq $Status) {
				if ($opResponse.StatusCode -eq 200 -or $opResponse.StatusCode -eq 204) {
					# Many services treat a 200/204 on the operation URL as success
					$Status = "Succeeded"
				}
			}

			Write-Verbose "Attempt $($Attempt): operation status = '$Status' (HTTP $($opResponse.StatusCode))"

			switch ($Status) {
				"Succeeded" {
					Write-Host "DELETE operation succeeded."
					# Exit the loop
					break
				}
				"Failed" {
					$Err = ${opJson}?.error
					$code = ${Err}?.code
					$message = ${Err}?.message
					throw "DELETE operation failed. Code: '$code' Message: '$message'."
				}
				"Canceled" {
					throw "DELETE operation was canceled."
				}
				default {
					# Any other status, like InProgress
					# Not terminal yet: exponential backoff with cap of maximum 60 seconds
					[int]$Sleep = [Math]::Min($PollIntervalSec * [Math]::Pow(1.5, $Attempt - 1), 60)
					Write-Verbose "Operation not complete yet; waiting $Sleep seconds before next poll..."
					Start-Sleep -Seconds $Sleep
					continue
				}
			}

			# Reached terminal state (Succeeded/Failed/Canceled or inferred Success)
			break
		}

		# Timeout handling
		if ((Get-Date) -ge $Deadline) {
			throw "Timed out after $MaxWaitMinutes minutes waiting for DELETE operation to complete."
		}
	}

	$VaultDeleted = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroup -ErrorAction 'SilentlyContinue'

	if ($null -eq $VaultDeleted) {
		Write-Host "Recovery Services Vault '$VaultName' successfully deleted."
	}
	else {
		Write-Error "Recovery Services Vault '$VaultName' was not successfully deleted. Status code: $($Response.StatusCode)."
		Write-Verbose $Response.Content
	}
}
