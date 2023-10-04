# Enable Best Practice Assessment for at Scale for Azure Arc enabled SQL Servers

#region Input Section
# BPA Log analytics Workspace
$workspaceResourceid = "<Enter your Log Analytics Workspace Resource ID>"

# Data Collection Rule ID for SQL Best Practices Assessment
$DataCollectionRuleId = "<Enter your Data Collection Rule ID>"

#Schedule
$Ocurrence = "monthly" # weekly, monthly
$Interval = 1 # each 1 week / First dayofWeek in month
$licensetype = "Paid" # Paid
$dayOfWeek = "Saturday"
$Starttime = "22:00"



$servers = @("server1","server2","server3")
$servers = Get-Content -Path ".\servers.txt"

#endregion

#Set assessment
$AzureArcServers = Get-AzConnectedMachine
    
$ServerstoEnableBPA = $AzureArcServers | Where-Object { $_.Name -in $servers }

foreach ($AzureArcServer in $ServerstoEnableBPA) {
    $Machinename = $AzureArcServer.Name
    $ResourceGroupName = $AzureArcServer.ResourceGroupName

  
    $Settings = @{LicenseType = $licensetype; SqlManagement = @{IsEnabled = $true }; AssessmentSettings = @{ Enable = $true ; WorkspaceResourceId = $workspaceResourceid; schedule = @{dayOfWeek = $dayOfWeek; Enable = $true ; startTime = $Starttime } } }

    if ($Ocurrence -eq "monthly") {
        $Settings.AssessmentSettings.schedule.Add("monthlyOccurrence", $Interval)
    }
    elseif ($Ocurrence -eq "weekly") {
        $Settings.AssessmentSettings.schedule.Add("WeeklyInterval", $Interval)
    }

    Set-AzConnectedMachineExtension -Name "WindowsAgent.SqlServer" -ResourceGroupName $ResourceGroupName -MachineName $Machinename -Location westeurope -Publisher "Microsoft.AzureData" -Setting $Settings -ExtensionType "WindowsAgent.SqlServer" -NoWait
}
# Check Configuration
foreach ($AzureArcServer in $ServerstoEnableBPA) {
    $Machinename = $AzureArcServer.Name
    $ResourceGroupName = $AzureArcServer.ResourceGroupName
    Get-AzConnectedMachineExtension -MachineName $Machinename -ResourceGroupName $ResourceGroupName -Name WindowsAgent.SQLServer | Select-Object -ExpandProperty Setting
}

# Add Servers to Best Practices Assessment Data Collection Rule

$AzureArcServers = Get-AzConnectedMachine
    
$ServerstoAddtoDCR = $AzureArcServers | Where-Object { $_.Name -in $servers }

foreach ($AzureArcServer in $ServerstoAddtoDCR) {
    $Machinename 
    New-AzDataCollectionRuleAssociation -TargetResourceId $AzureArcServer.id -AssociationName "BPA-$($AzureArcServer.Name)" -DataCollectionRuleId $DataCollectionRuleId
}