# This script downgrades the SQL Server extension on Azure Arc machines to a specified version.
# It searches for all Arc machines with the SQL Server extension in the given subscription and updates them to the
# desired version expecified in the $TypeHandlerVersion variable.

# Use Select-AzSubscription to set the context to the desired subscription before running this script.
$TypeHandlerVersion = '1.1.3238.350'
$extensionName = 'WindowsAgent.SqlServer'
$publisher = 'Microsoft.AzureData'
$extensionType = 'WindowsAgent.SqlServer'
$licensetype = "Paid"
$settings = @{SqlManagement = @{IsEnabled = $true};LicenseType = $licensetype}


Write-Host "Searching Arc SQL extensions in current subscription"

$sqlArcExtensions = Get-AzResource -ResourceType 'Microsoft.HybridCompute/machines/extensions' -ErrorAction Stop |
	Where-Object {
		$_.Name -like "*/$extensionName" -and
		$_.ResourceType -eq 'Microsoft.HybridCompute/machines/extensions'
	}

if (-not $sqlArcExtensions -or $sqlArcExtensions.Count -eq 0) {
	Write-Host "No Arc machines with extension '$extensionName' were found in current subscription."
	return
}

Write-Host "Found $($sqlArcExtensions.Count) Arc machine(s) with '$extensionName'. Starting update..."

foreach ($extensionResource in $sqlArcExtensions) {
	$nameParts = $extensionResource.Name.Split('/')
	if ($nameParts.Count -lt 2) {
		Write-Warning "Skipping unexpected extension resource name format: $($extensionResource.Name)"
		continue
	}

	$machineName = $nameParts[0]
	$resourceGroupName = $extensionResource.ResourceGroupName
	$location = $extensionResource.Location
	$currentVersion = $null

	if ($extensionResource.Properties -and
		$extensionResource.Properties.PSObject.Properties.Name -contains 'typeHandlerVersion') {
		$currentVersion = [string]$extensionResource.Properties.typeHandlerVersion
	}

	if ([string]::IsNullOrWhiteSpace($currentVersion)) {
		try {
			$currentExtension = Get-AzConnectedMachineExtension -ResourceGroupName $resourceGroupName -MachineName $machineName -Name $extensionName -ErrorAction Stop
			$currentVersion = [string]$currentExtension.TypeHandlerVersion
		}
		catch {
			Write-Warning "Skipping '$machineName' in '$resourceGroupName' because current extension version could not be resolved. Error: $($_.Exception.Message)"
			continue
		}
	}

	if ($currentVersion -eq $TypeHandlerVersion) {
		Write-Host "Skipping '$machineName' (current version '$currentVersion' already matches desired version)."
		continue
	}

	if ([string]::IsNullOrWhiteSpace($location)) {
		try {
			$machine = Get-AzConnectedMachine -ResourceGroupName $resourceGroupName -Name $machineName -ErrorAction Stop
			$location = $machine.Location
		}
		catch {
			Write-Warning "Skipping '$machineName' in '$resourceGroupName' because location could not be resolved. Error: $($_.Exception.Message)"
			continue
		}
	}

	try {
		Write-Host "Updating '$machineName' from version '$currentVersion' to '$TypeHandlerVersion' (RG: '$resourceGroupName', Location: '$location')..."

		Set-AzConnectedMachineExtension `
			-MachineName $machineName `
			-ResourceGroupName $resourceGroupName `
			-Name $extensionName `
			-Publisher $publisher `
			-ExtensionType $extensionType `
			-Location $location `
			-TypeHandlerVersion $TypeHandlerVersion `
			-NoWait `
            -EnableAutomaticUpgrade:$true `
            -Settings $settings `
			-ErrorAction Stop | Out-Null

		Write-Host "Queued update for '$machineName'."
	}
	catch {
		Write-Error "Failed to update '$machineName' in '$resourceGroupName'. Error: $($_.Exception.Message)"
	}
}

Write-Host 'Update requests submitted.'
