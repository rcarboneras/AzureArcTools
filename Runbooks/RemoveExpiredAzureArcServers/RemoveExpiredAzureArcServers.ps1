#requires -Modules Az.Accounts, Az.ResourceGraph, Az.Resources, Az.ConnectedMachine

# This script will remove expired Azure Arc Servers.
# The script is meant to be run in an Azure Automation Account Runbook using a system assigned managed identity with permissions to read Azure Resources
# Graph and remove Azure Arc Servers in the subscription.

# Runbook: RemoveAzureArcExpiredMachines
Function QueryGraphPaged {
    param (
        $PageSize,
        $query,
        $Subscriptions
    )

    $GlobalResults = @()

    $Results = Search-AzGraph -Query $query -First $PageSize -Subscription $Subscriptions
    $GlobalResults += $Results
    $Skip = $PageSize
    
    do {
        $Results = Search-AzGraph -Query $query -First $PageSize -Skip $Skip -Subscription $Subscriptions
        $Skip += $PageSize
        $GlobalResults += $Results
    } while ($Results.Count -eq $PageSize)
    
    return $GlobalResults
    
}

#Main

Import-Module Az.Accounts -Force
$TagName = "Decommissioned"
$TagValue = "True"

Write-Output "This workbook is running in worker: $($Env:COMPUTERNAME)"

#Connect to Azure using a managed identity ()
try { Add-AzAccount -Identity }
catch { Write-Output "There was an error trying to connect to Azure"; Write-Warning "$_" }

# Determine subscriptions to process
$Subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }

if (-not $Subscriptions -or $Subscriptions.Count -eq 0) {
    Write-Output "No enabled subscriptions found in current context. Exiting..."
    exit
}

$SubscriptionIds = $Subscriptions.Id
Write-Output "Found $($SubscriptionIds.Count) enabled subscription(s) to evaluate."

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


$ArcmachinesExpired = QueryGraphPaged -PageSize 100 -query $Graphquery -Subscriptions $SubscriptionIds

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
$FailedServers = @()

$ArcMachinesBySubscription = $ArcmachinesExpired | Group-Object -Property subscriptionId

foreach ($subscriptionGroup in $ArcMachinesBySubscription)
{
    $CurrentSubscriptionId = $subscriptionGroup.Name
    Write-Output "`nSelecting subscription $CurrentSubscriptionId"

    try {
        Select-AzSubscription -SubscriptionId $CurrentSubscriptionId -Verbose -ErrorAction Stop
    }
    catch {
        Write-Output "Could not select subscription $CurrentSubscriptionId. Skipping machines in this subscription."
        Write-Output "$($_.Exception.Message)"
        foreach ($failedMachine in $subscriptionGroup.Group) {
            $FailedServers += $failedMachine
        }
        continue
    }

    foreach ($Arcmachine in $subscriptionGroup.Group)
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
            $FailedServers += $Arcmachine
        }
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

if ($FailedServers.Count -gt 0) {
    Write-Output "`n=========================================="
    Write-Output "FAILURE SUMMARY REPORT"
    Write-Output "=========================================="
    Write-Output "Total servers not deleted: $($FailedServers.Count)"
    Write-Output "`nFailed Servers:"

    foreach ($server in $FailedServers) {
        Write-Output "  - $($server.name) | RG: $($server.resourceGroup) | Subscription: $($server.subscriptionId) | Status: $($server.Status) | ID: $($server.id)"
    }

    Write-Output "=========================================="
}
