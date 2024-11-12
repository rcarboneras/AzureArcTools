#requires  -module  Az.ResourceGraph,AZ.Resources

# This script will remove orphaned Azure Arc SQL Servers. The orphaned Azure Arc SQL Servers are Azure Arc SQL Servers
# that are not associated with an Azure Arc machine or the Azure Arc machine does not exist anymore.

# The script is meant to run as an Azure Automation Runbook. The Azure Automation must have a managed identity
# with the appropiate permissions to remove Azure Arc SQL Servers.


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

# Login in Azure with the identity of the Azure Automation account

Write-Output "Logging in to Azure with the identity of the Azure Automation account"
Connect-AzAccount -Identity


# Determine wich Azure Arc machines are not in a expired status
Write-Output "Determining Azure Arc machines that are not in an expired status..."

$Graphquery = @"
resources
| where type == "microsoft.hybridcompute/machines"
| extend Status = properties.status
| where Status != "Expired"
| extend id = tolower(id)
| project id,Status,subscriptionId
"@

$Arcmachines = QueryGraphPaged -PageSize 100 -query $Graphquery
$ArcmachineIds = $Arcmachines | Select-Object -ExpandProperty ResourceId # Get the Azure Arc machine ids

# Determine Azure Arc SQL Instances
Write-Output "Determining Azure Arc SQL Instances ..."
$Graphquery = @"
resources
| where type == "microsoft.azurearcdata/sqlserverinstances"
| extend containerResourceId = tolower(tostring(properties.containerResourceId))
| extend id = tolower(id)
| project id,containerResourceId,subscriptionId
"@

$ArcSQLInstances = QueryGraphPaged -PageSize 100 -query $Graphquery

# Determine wich Azure Arc SQL Servers are in an orphaned state

Write-Output "Determining orphaned Azure Arc SQL Servers..."
$OrphanedSQLServers = $ArcSQLInstances | Where-Object { $_.containerResourceId -notin $ArcmachineIds } | Select-Object -Property id, containerResourceId, subscriptionId

if ($null -eq $OrphanedSQLServers) {
    Write-Output "No orphaned Azure Arc SQL Servers found. Exiting"
    exit
}
else {

    Write-Output "The following $($OrphanedSQLServers.count) Azure Arc SQL Servers are orphaned, the Azure Arc machine does not exist anymore:"
    $OrphanedSQLServers

    Write-Host "Attempting to remove orphaned SQL Servers..."

    # Generate jobs to remove orphaned SQL Servers

    # Get-Job | Remove-Job -Force

    $OrphanedSQLServers | ForEach-Object {
        $Resourceid = $_.id
        Write-Output "Removing Azure Arc SQL Server with id $Resourceid"
        try { Remove-AzResource -ResourceId $Resourceid -Force -AsJob -Verbose | Out-Null }
        catch { Write-Output "Failed to remove Azure Arc SQL Server with id $Resourceid" }
    }

    $Jobs = Get-Job

    # Wait for all jobs to complete

    Write-Output "Waiting for all jobs to complete... This may take a while."
    $Jobs | ForEach-Object { Wait-Job -Job $_ }

    # Clean up completed jobs
    $Jobs | ForEach-Object { Remove-Job -Job $_ }

    Write-Output "All jobs have been completed."
}

