#This script will set the license type to the specified one, for all SQL servers Enterprise and Standard Edition
# that have the SQL extension installed
#Updated settings object
$LicenseType = "Paid" # Paid,PAYG
$Settings = @{ SqlManagement = @{ IsEnabled = $true }; LicenseType = $LicenseType }
#Command stays the same as before, only settings is changed above:
#New-AzConnectedMachineExtension -Name "WindowsAgent.SqlServer" -ResourceGroupName { your resource group name } -MachineName { your machine name } -Location { azure region } -Publisher "Microsoft.AzureData" -Settings $Settings -ExtensionType "WindowsAgent.SqlServer"


#Get Azure Arc Servers
$arcservers = Get-AzConnectedMachine | Select-Object -Property Name, ResourceGroupName

# Get SQL extensions

Write-Host "Getting SQL  información from $($arcservers.Count) servers using PowerShell Az module. This might take a few minutes"
$sqlextensions = foreach ($arcserver in $arcservers)
{ Get-AzConnectedMachineExtension -MachineName $arcserver.Name -ResourceGroupName $arcserver.ResourceGroupName -Name WindowsAgent.SqlServer -ErrorAction SilentlyContinue }

# Get SQL Instances

$query = @'
resources
| where ['type'] == "microsoft.azurearcdata/sqlserverinstances"
| project containerResourceId = properties.containerResourceId, instanceName = properties.instanceName, edition = properties.edition, version = properties.version, licenseType = properties.licenseType
| where edition == "Enterprise" or edition == "Standard"
'@
$SQLInstances = Search-AzGraph -Query $query -First 1000
$SQLInstanceshash = @{}
$SQLInstances | ForEach-Object { $id = ($_.containerResourceId).tolower(); $SQLInstanceshash["$id"] = $_ }


$sqlextensionsconf = $sqlextensions | ForEach-Object {
    $id = $($_.id -replace "/extensions/WindowsAgent.SqlServer").tolower()
    New-Object -TypeName psobject -Property @{
        Server      = ($_.id -split "/")[-3]
        LicenseType = $_.Setting.AdditionalProperties.LicenseType
        Version     = $_.TypeHandlerVersion
        edition     = $SQLInstanceshash["$id"].edition
        location   = $_.Location
    }    
}

# Show results
Write-Host "Servers with SQL extension installed and with license type set to $($LicenseType):" -ForegroundColor Green
$sqlextensionsconf | Where-Object { ($_.LicenseType -like $LicenseType) -and ($_.edition -in @("Standard", "Enterprise")) } | Sort-Object -Property Edition | Format-Table
Write-Host "Servers with SQL extension installed and with license type NOT set to $($LicenseType):" -ForegroundColor Yellow
$sqlextensionsconf | Where-Object { ($_.LicenseType -notlike $LicenseType) -and ($_.edition -in @("Standard", "Enterprise")) }  | Sort-Object -Property Edition | Format-Table

# Set extensions that don't have license type set to paid
$extensionstoset = $sqlextensions | Where-Object { 
    $id = ($_.id -replace "/extensions/WindowsAgent.SqlServer").tolower()
    $edition = $SQLInstanceshash["$id"].edition
    ($_.Setting.AdditionalProperties.LicenseType -ne $LicenseType) -and ($edition -in @("Standard", "Enterprise"))
}

# Check if there are any extensions to update
if ($extensionstoset.Count -eq 0) {
    Write-Host "All extensions are already set to `"$($LicenseType)`"" -ForegroundColor Green
    exit
}

# Confirmation prompt
Write-Warning "Are you sure you want to make changes to the above extensions and set their license to $($LicenseType)?"
$confirmation = Read-Host "Press ENTER to continue or any other key or CTRL+C to cancel"
if ($confirmation -ne "") {
    Write-Host "Operation cancelled" -ForegroundColor Red
    exit
}

# Create log file with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "LicenseChanges_$timestamp.log"
"License Type Changes Log - $(Get-Date)" | Out-File -FilePath $logFile
"=" * 80 | Out-File -FilePath $logFile -Append
"`n" | Out-File -FilePath $logFile -Append

foreach ($item in $extensionstoset) {
    $ResourceGroup = ($item.id -split "/")[-7]
    $Machinename = ($item.id -split "/")[-3]
    $location = $item.Location
    $id = ($item.id -replace "/extensions/WindowsAgent.SqlServer").tolower()
    $edition = $SQLInstanceshash["$id"].edition
    $oldLicenseType = $item.Setting.AdditionalProperties.LicenseType
    
    # Log the change
    "Server: $Machinename" | Out-File -FilePath $logFile -Append
    "Resource Group: $ResourceGroup" | Out-File -FilePath $logFile -Append
    "Location: $location" | Out-File -FilePath $logFile -Append
    "Edition: $edition" | Out-File -FilePath $logFile -Append
    "License Type BEFORE: $oldLicenseType" | Out-File -FilePath $logFile -Append
    "License Type AFTER: $LicenseType" | Out-File -FilePath $logFile -Append
    "Extension ID: $($item.id)" | Out-File -FilePath $logFile -Append
    "Timestamp: $(Get-Date)" | Out-File -FilePath $logFile -Append
    "-" * 80 | Out-File -FilePath $logFile -Append
    
    Set-AzConnectedMachineExtension -Name "WindowsAgent.SqlServer" -ResourceGroupName $ResourceGroup -MachineName $Machinename `
        -Location $location -Publisher "Microsoft.AzureData" -Setting $Settings -ExtensionType "WindowsAgent.SqlServer" -NoWait
}

Write-Host "`nChanges logged to: $logFile" -ForegroundColor Cyan
