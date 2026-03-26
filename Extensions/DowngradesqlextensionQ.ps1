# This script downgrades the SQL Server extension on Azure Arc machines to a specified version.
# It searches for all Arc machines with the SQL Server extension in the given subscription and updates them to the
# desired version expecified in the $TypeHandlerVersion variable.

# Use Select-AzSubscription to set the context to the desired subscription before running this script.
$TypeHandlerVersion = '1.1.3238.350'
$SourceTypeHandlerVersion = '1.1.3307.355'
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

Write-Host "Found $($sqlArcExtensions.Count) Arc machine(s) with '$extensionName'. Evaluating candidates..."

$extensionsToUpdate = @()

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
	$currentExtension = $null

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

	if ($currentVersion -ne $SourceTypeHandlerVersion) {
		Write-Host "Skipping '$machineName' (current version '$currentVersion' is not '$SourceTypeHandlerVersion')."
		continue
	}

	try {
		$currentExtension = Get-AzConnectedMachineExtension -ResourceGroupName $resourceGroupName -MachineName $machineName -Name $extensionName -ErrorAction Stop
	}
	catch {
		Write-Warning "Skipping '$machineName' in '$resourceGroupName' because extension properties could not be resolved. Error: $($_.Exception.Message)"
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

	$extensionsToUpdate += [PSCustomObject]@{
		MachineName = $machineName
		ResourceGroupName = $resourceGroupName
		Location = $location
		CurrentVersion = $currentVersion
		Extension = $currentExtension
	}
}

if ($extensionsToUpdate.Count -eq 0) {
	Write-Host "No extensions match source version '$SourceTypeHandlerVersion'. Nothing to update."
	return
}

Write-Host "The following $($extensionsToUpdate.Count) extension(s) will be updated:" -ForegroundColor Yellow
foreach ($candidate in $extensionsToUpdate) {
	Write-Host "--- Machine: $($candidate.MachineName) | RG: $($candidate.ResourceGroupName) ---" -ForegroundColor Yellow
	$details = $candidate.Extension | Format-List * | Out-String
	Write-Host $details -ForegroundColor Yellow
}

$confirmation = Read-Host "Press ENTER to confirm update, or type anything to cancel"
if (-not [string]::IsNullOrEmpty($confirmation)) {
	Write-Host 'Operation cancelled by user.'
	return
}

foreach ($candidate in $extensionsToUpdate) {
	try {
		Write-Host "Updating '$($candidate.MachineName)' from version '$($candidate.CurrentVersion)' to '$TypeHandlerVersion' (RG: '$($candidate.ResourceGroupName)', Location: '$($candidate.Location)')..."

		Set-AzConnectedMachineExtension `
			-MachineName $candidate.MachineName `
			-ResourceGroupName $candidate.ResourceGroupName `
			-Name $extensionName `
			-Publisher $publisher `
			-ExtensionType $extensionType `
			-Location $candidate.Location `
			-TypeHandlerVersion $TypeHandlerVersion `
			-NoWait `
            -EnableAutomaticUpgrade:$true `
            -Settings $settings `
			-ErrorAction Stop | Out-Null

		Write-Host "Queued update for '$($candidate.MachineName)'."
	}
	catch {
		Write-Error "Failed to update '$($candidate.MachineName)' in '$($candidate.ResourceGroupName)'. Error: $($_.Exception.Message)"
	}
}

Write-Host 'Update requests submitted.'
