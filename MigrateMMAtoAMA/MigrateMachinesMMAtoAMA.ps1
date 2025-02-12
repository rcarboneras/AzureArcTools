#https://learn.microsoft.com/en-us/powershell/module/az.monitor/new-azdatacollectionruleassociation?view=azps-13.1.0#code-try-3

# Services migration from MMA to AMA (Change Tracking and VM Insights)
# 1. Add server to Data Colleciton Rules
# 2. Set Dependency Agent to work with AMA
# 3. Remove Log Analytics Workspace from MMA

Param (
    [Parameter(Mandatory = $true)]
    [string]$MachineListtoMigrate
)

try { $Servernames = Get-Content -Path $MachineListtoMigrate }
catch { Write-Host "Error reading file $MachineListtoMigrate"; exit }

$AzureArcServers = Get-AzConnectedMachine
$InsightsDataCollecionRuleId = "/subscriptions/71ac1fd6-9ebc-4a20-9667-b873f7cee091/resourceGroups/Arc-Demo/providers/Microsoft.Insights/dataCollectionRules/DCR-Microsoft-VMInsights-LA-AzureArc"
$ChangeTrackingDataCollecionRuleId = "/subscriptions/71ac1fd6-9ebc-4a20-9667-b873f7cee091/resourceGroups/Arc-Demo/providers/Microsoft.Insights/dataCollectionRules/DCR-Microsoft-VMInsights-LA-AzureArc"

foreach ($ServerName in $Servernames) {
    Write-Host "$ServerName" -ForegroundColor Yellow
    $AzureArcServer = $AzureArcServers | Where-Object { $_.Name -eq $ServerName }
    if ($null -eq $AzureArcServer) {
        Write-Host "Server $ServerName not found in Azure Arc"
        continue
    }
    $Resourceuri = $AzureArcServer.Id

    # Add server to Data Colleciton Rules
    try {
        Write-Host "`tAdding server to Insights Data Collection Rule $InsightsDataCollecionRuleId" -ForegroundColor Green
        $AssociationName = "$ServerName-Insights"
        $Insights = New-AzDataCollectionRuleAssociation -AssociationName $AssociationName -ResourceUri $Resourceuri -DataCollectionRuleId $InsightsDataCollecionRuleId -ErrorAction Stop        
    }
    catch {
        Write-Host "Error adding server to Data Collection Rule $InsightsDataCollecionRuleId" -ForegroundColor Red
    }

    try {
        Write-Host "`tAdding server to Change Tracking Data Collection Rule $ChangeTrackingDataCollecionRuleId" -ForegroundColor Green
        $AssociationName = "$ServerName-ChangeTracking"
        $ChangeTracking = New-AzDataCollectionRuleAssociation -AssociationName $AssociationName -ResourceUri $Resourceuri -DataCollectionRuleId $ChangeTrackingDataCollecionRuleId -ErrorAction Stop
    }
    catch {
        Write-Host "Error adding server to Data Collection Rule $ChangeTrackingDataCollecionRuleId" -ForegroundColor Red
    }


    # Set Dependency Agent to work with AMA - Custom Script Extension
    try {

        # Get current extension
        Write-Host "`tSetting Dependency Agent to work with AMA" -ForegroundColor Green
        Set-AzConnectedMachineExtension -Publisher Microsoft.Azure.Monitoring.DependencyAgent `
            -ExtensionType DependencyAgentWindows `
            -Name DependencyAgentWindows `
            -Settings @{"enableAMA" = "false" } `
            -MachineName $ServerName -ResourceGroupName $AzureArcServer.ResourceGroupName -Location $AzureArcServer.Location -NoWait `
            -ErrorAction Stop | Out-Null
    
    }
    catch {
        <#Do this if a terminating exception happens#>
        Write-Host "Error setting Dependency Agent to work with AMA" -ForegroundColor Red;$_.ErrorDetails.Message
    }
 

    # Remove Log Analytics Workspace from MMA
    $UNCpath = "\\arcdc1\share\GustomSriptRemoveLogAnalitycsWorkspace.ps1"
    $protectedSettings = @{"commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File $UNCpath" };

    try {
        $CustomScriptExtension = Get-AzConnectedMachineExtension -MachineName $ServerName -ResourceGroupName $AzureArcServer.ResourceGroupName | where MachineExtensionType -eq "CustomScriptExtension"
        $CustomScriptExtensionname = $CustomScriptExtension.Name # Get Current CustomScriptExtensionname to avoid failure
        Write-Host "`tRemoving Log Analytics Workspace from MMA" -ForegroundColor Green
        Set-AzConnectedMachineExtension -Publisher "Microsoft.Compute" `
        -ExtensionType "CustomScriptExtension" `
        -TypeHandlerVersion "1.10" `
        -ProtectedSettings $protectedSettings `
        -MachineName $ServerName `
        -ResourceGroupName $AzureArcServer.ResourceGroupName `
        -ForceRerun "true" `
        -Location $AzureArcServer.Location -Name $CustomScriptExtensionname -NoWait `
        -ErrorAction Stop | Out-Null
        
    }
    catch {
        Write-Host "Error removing Log Analytics Workspace from MMA" -ForegroundColor Red;$_.ErrorDetails.Message
    }

}