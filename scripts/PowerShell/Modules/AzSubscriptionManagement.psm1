@{
    ModuleVersion = '0.0.1'
}

<#
#>
Function Set-AzContextWrapper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 1)]
        [string]$SubscriptionId,
        [Parameter(Position = 2)]
        [string]$Environment = 'AzureCloud'
    )

    # Because this function is in a module, $VerbosePreference doesn't carry over from the caller
    # See https://stackoverflow.com/a/44902512/816663
    if (-Not $PSBoundParameters.ContainsKey('Verbose')) {
        $VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
    }

    # Determine if a cloud context switch is required
    $AzContext = Get-AzContext
    if ($AzContext.Environment.Name -ne $Environment) {
        Write-Warning "Current Environment: '$($AzContext.Environment.Name)'. Switching to $Environment"
        Connect-AzAccount -Environment $Environment
        $AzContext = Get-AzContext
    }
    else {
        Write-Verbose "Current Environment: '$($AzContext.Environment.Name)'. No switch needed."
    }

    # Determine if a subscription switch is required
    if ($SubscriptionId -ne (Get-AzContext).Subscription.Id) {
        Write-Verbose "Current subscription: '$($AzContext.Subscription.Id)'. Switching subscription."
        Select-AzSubscription $SubscriptionId
        $AzContext = Get-AzContext
    }
    else {
        Write-Verbose "Current Subscription: '$($AzContext.Subscription.Name)'. No switch needed."
    }

    return $AzContext
}

<#
    .SYNOPSIS
    Registers an Azure subscription for a resource provider feature.

    .DESCRIPTION
    Determines if the specified feature for the specified resource provider namespace is registered. If not, it will register the feature and wait for registration to complete.

    .NOTES
    The current Azure context will be used to determine the subscription to register the feature in.
#>
Function Register-AzProviderFeatureWrapper {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 1)]
        [string]$ProviderNamespace,
        [Parameter(Mandatory, Position = 2)]
        [string]$FeatureName
    )

    # Because this function is in a module, $VerbosePreference doesn't carry over from the caller
    # See https://stackoverflow.com/a/44902512/816663
    if (-Not $PSBoundParameters.ContainsKey('Verbose')) {
        $VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
    }

    # Get the feature's current registration state
    $Feature = Get-AzProviderFeature -FeatureName $FeatureName -ProviderNamespace $ProviderNamespace
    $AzContext = Get-AzContext
    
    # If the feature is not registered yet
    if ($Feature.RegistrationState -ne 'Registered') {
        Write-Warning "About to register feature '$($Feature.ProviderName)::$($Feature.FeatureName)' in subscription '$($AzContext.Subscription.Name)'. Expect a (up to 15 minute) delay while the feature registration is completed."
        $Status = Register-AzProviderFeature -FeatureName $FeatureName -ProviderNamespace $ProviderNamespace

        if ($Status.RegistrationState -eq 'Registering') {
            [double]$PercentComplete = 1
            Write-Progress -Activity "Registering feature '$($Status.ProviderName)::$($Status.FeatureName)'" -Id 0 -PercentComplete $PercentComplete -SecondsRemaining -1

            while ($Status.RegistrationState -eq 'Registering') {
                Start-Sleep -Seconds 30
                $Status = Get-AzProviderFeature -FeatureName $FeatureName -ProviderNamespace $ProviderNamespace
                # Assuming 20 minutes (max); so each 30 seconds is 2.5% complete
                $PercentComplete += 2.5
                Write-Progress -Activity "Registering feature '$($Status.ProviderName)::$($Status.FeatureName)'" -Id 0 -PercentComplete $PercentComplete -SecondsRemaining -1
            }
		
            $PercentComplete = 100
            Write-Progress -Activity "Registering feature '$($Status.ProviderName)::$($Status.FeatureName)'" -Id 0 -PercentComplete $PercentComplete -SecondsRemaining 0
            Write-Information "Feature registration complete."
        }
        else {
            Write-Error "Feature registration failed: $($Status.RegistrationState)"
        }
    }
    else {
        Write-Verbose "Feature '$($Feature.ProviderName)::$($Feature.FeatureName)' is already registered in subscription '$($AzContext.Subscription.Name)'."
    }
}

<#
    .SYNOPSIS
    Registers an Azure subscription for a resource provider feature.

    .DESCRIPTION
    Determines if the specified feature for the specified resource provider namespace is registered. If not, it will register the feature and wait for registration to complete.

    .NOTES
    The current Azure context will be used to determine the subscription to register the feature in.
#>
Function Register-AzResourceProviderWrapper {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 1)]
        [string]$ProviderNamespace
    )

    # Because this function is in a module, $VerbosePreference doesn't carry over from the caller
    # See https://stackoverflow.com/a/44902512/816663
    if (-Not $PSBoundParameters.ContainsKey('Verbose')) {
        $VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
    }

    # Get the feature's current registration state
    $Provider = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace
    $AzContext = Get-AzContext
    
    # If the feature is not registered yet
    if ($Provider.RegistrationState -ne 'Registered') {
        Write-Warning "About to register provider '$($Provider.ProviderNamespace)' in subscription '$($AzContext.Subscription.Name)'. Expect a delay while the feature registration is completed."
        $Status = Register-AzResourceProvider -ProviderNamespace $ProviderNamespace

        if ($Status.RegistrationState -eq 'Registering') {
            [double]$PercentComplete = 1
            Write-Progress -Activity "Registering provider '$($Status.ProviderNamespace)'" -Id 0 -PercentComplete $PercentComplete -SecondsRemaining -1

            while ($Status.RegistrationState -eq 'Registering') {
                Start-Sleep -Seconds 30
                $Status = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace
                # Assuming 20 minutes (max); so each 30 seconds is 2.5% complete
                $PercentComplete += 2.5
                Write-Progress -Activity "Registering provider '$($Status.ProviderNamespace)'" -Id 0 -PercentComplete $PercentComplete -SecondsRemaining -1
            }
		
            $PercentComplete = 100
            Write-Progress -Activity "Registering provider '$($Status.ProviderNamespace)'" -Id 0 -PercentComplete $PercentComplete -SecondsRemaining 0
            Write-Information "Provider registration complete."
        }
        else {
            Write-Error "Provider registration failed: $($Status.RegistrationState)"
        }
    }
    else {
        Write-Verbose "Provider '$($Provider.ProviderNamespace)' is already registered in subscription '$($AzContext.Subscription.Name)'."
    }
}

Export-ModuleMember -Function Set-AzContextWrapper
Export-ModuleMember -Function Register-AzProviderFeatureWrapper
Export-ModuleMember -Function Register-AzResourceProviderWrapper