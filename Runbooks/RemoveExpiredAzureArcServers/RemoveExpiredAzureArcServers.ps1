#requires -Modules Az.Accounts, Az.ResourceGraph, Az.Resources, Az.ConnectedMachine

# This script will remove expired Azure Arc Servers.
# The script is meant to be run in an Azure Automation Account Runbook using a system assigned managed identity with permissions to read Azure Resources
# Graph and remove Azure Arc Servers in the subscription.

# Runbook: RemoveAzureArcExpiredMachines
Function QueryGraphPaged {
    param (
        $PageSize,
        $query
    )

    $GlobalResults = @()

    $Results = Search-AzGraph -Query $query -First $PageSize
    $GlobalResults += $Results
    $Skip = $PageSize
    
    do {
        $Results = Search-AzGraph -Query $query -First $PageSize -Skip $Skip
        $Skip += $PageSize
        $GlobalResults += $Results
    } while ($Results.Count -eq $PageSize)
    
    return $GlobalResults
    
}

#Main

Import-Module Az.Accounts -Force
$TagName = "Decommissioned"
$TagValue = "True"
$SubscriptionName = "MCAPS-Hybrid-REQ-46709-2022-racarb"

Write-Host "This workbook is running in worker: $($Env:COMPUTERNAME)"

#Connect to Azure using a managed identity ()
try { Add-AzAccount -Identity }
catch { Write-Output "There was an error trying to connect to Azure"; Write-Warning "$_" }

# Select Azure Subscription
Select-AzSubscription $SubscriptionName
# Determine wich Azure Arc machines are in a expired status
Write-Output "Determining Azure Arc machines that are in an expired status..."

# This query looks for Azure Arc machines with status expired and with the tag Decommissioned=True, this is to avoid removing machines that are expired but not meant to be decommissioned yet.
$Graphquery = @"
resources
| where type == "microsoft.hybridcompute/machines"
| extend Status = properties.status
| where Status == "Expired"
| where tags["$TagName"] == "$TagValue"
| extend id = tolower(id)
| project name,resourceGroup,id,Status,subscriptionId
"@


$ArcmachinesExpired = QueryGraphPaged -PageSize 100 -query $Graphquery

if ($ArcmachinesExpired.count -gt 0)
{
    Write-Output "The following $($ArcmachinesExpired.count) machine(s) are in an expired status"
    $ArcmachinesExpired
}
else {
    Write-Output "No Azure Arc Machines in an expired status and marked for decommissioning found. Exiting..."
    exit
}

Write-Output "Removing decommissioned machines.."

$DeletedServers = @()

foreach ($Arcmachine in $ArcmachinesExpired)
{
    
    Write-Output "`nRemoving Azure Arc Server $($Arcmachine.name).."
    Write-Output "$($Arcmachine.id)"
    try {
        Remove-AzConnectedMachine -Name $Arcmachine.name -ResourceGroupName $Arcmachine.resourceGroup -Verbose -ErrorAction Stop
        $DeletedServers += $Arcmachine
    }
    catch {
        Write-Output "Could not remove server $($Arcmachine.Name)"
        Write-Output "$($_.Exception.Message)"
    }
}

# Print detailed report of deleted servers
if ($DeletedServers.Count -gt 0) {
    Write-Output "`n=========================================="
    Write-Output "DELETION SUMMARY REPORT"
    Write-Output "=========================================="
    Write-Output "Total servers successfully deleted: $($DeletedServers.Count)"
    Write-Output "`nDeleted Servers:"
    
    foreach ($server in $DeletedServers) {
        Write-Output "  - $($server.name) | RG: $($server.resourceGroup) | Subscription: $($server.subscriptionId) | Status: $($server.Status) | ID: $($server.id)"
    }
    
    Write-Output "=========================================="
}
else {
    Write-Output "`nNo servers were successfully deleted."
}
