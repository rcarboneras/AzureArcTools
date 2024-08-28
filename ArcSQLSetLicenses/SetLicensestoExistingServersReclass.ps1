#This script will set the license type to the specified one, for all SQL servers Enterprise and Standard Edition
# that have the SQL extension installed

#Updated settings object
$LicenseType = "Paid"
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
Write-Host "Servers with SQL extension installed and with license type $($LicenseType):"
$sqlextensionsconf | Where-Object { ($_.LicenseType -like $LicenseType) -and ($_.edition -in @("Standard", "Enterprise")) } | Sort-Object -Property Edition
Write-Host "Servers with SQL extension installed and with license type not set to $($LicenseType):"
$sqlextensionsconf | Where-Object { ($_.LicenseType -notlike $LicenseType) -and ($_.edition -in @("Standard", "Enterprise")) } | Sort-Object -Property Edition

# Set extensions that don't have license type set to paid
$extensionstoset = $sqlextensions | Where-Object { $_.Setting["LicenseType"] -ne $LicenseType}

break # Remove this line to run the script to make changes

foreach ($item in $extensionstoset) {
    $ResourceGroup = ($item.id -split "/")[-7]
    $Machinename = ($item.id -split "/")[-3]
    $location = $item.Location
    Set-AzConnectedMachineExtension -Name "WindowsAgent.SqlServer" -ResourceGroupName $ResourceGroup -MachineName $Machinename `
        -Location $location -Publisher "Microsoft.AzureData" -Setting $Settings -ExtensionType "WindowsAgent.SqlServer" -NoWait
}



