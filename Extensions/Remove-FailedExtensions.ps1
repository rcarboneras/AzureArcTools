#Requires -Modules "Az.Compute","Az.ConnectedMachine","Az.ResourceGraph"
# Script to get all the extensions in tenant. Valid for Azure VMs & Azure Arc Machines

Param (
    [bool]$RemoveAll = $false
)


# Graph Query to check all failed extensions in tenant
$kqlQuery = @"
resources
| where type == 'microsoft.hybridcompute/machines/extensions' or type == 'microsoft.compute/virtualmachines/extensions'
| where properties.provisioningState == "Failed"
| extend machineid = tostring(split(id,'/extensions/',0)[0])
|join kind=inner (
resources
| where type in ('microsoft.hybridcompute/machines','microsoft.compute/virtualmachines')
| where properties.status == "Connected" or properties.extended.instanceView.powerState.displayStatus == "VM running"
| project machineid = id) on machineid
"@

# Query Graph using pagination
$batchSize = 1000
$skipResult = 0


$kqlResult = @()
while ($true) {

    if ($skipResult -gt 0) {
        $graphResult = Search-AzGraph -Query $kqlQuery -First $batchSize -SkipToken $graphResult.SkipToken -Skip $skipResult
    }
    else {
        $graphResult = Search-AzGraph -Query $kqlQuery -First $batchSize
    }
    $kqlResult += $graphResult.data
    if ($graphResult.data.Count -lt $batchSize) {
        break;
    }
    $skipResult += $batchSize
}


$failedExtensions = $kqlResult
Write-Output "A total of $($failedExtensions.Count) extension(s) in a failed state have been found in a total of $(($failedExtensions.subscriptionid | Select-Object -Unique).Count) subscription(s)"

Write-Output "Below you can find the number of extensions failed by type and a list of all the failed extensions"
$failedExtensions.name | Group-Object | Select-Object Name, Count | Sort-Object -Property count -Descending | Format-Table -AutoSize
$failedExtensionsFormated = $failedExtensions | Select-Object subscriptionid, resourceGroup, @{N = "Machine"; E = { ($_.id -split "/")[-3] } }, @{N = "Type"; E = { ($_.id -split "/")[-5] } }, location, name, @{N = "TypeHandlerVersion"; E = { $_.Properties.TypeHandlerVersion } }, @{N = "provisioningState"; E = { $_.Properties.provisioningState } } 
$failedExtensionsFormated | Format-Table -AutoSize


#Check if RemoveAll parameter was passed, and if so remove all failed extensions

if ($RemoveAll) {
    # Remove extensions from machines

    $failedExtensionsGrouped = $failedExtensions | Group-Object -Property subscriptionid
    $RemovalOperations = foreach ($group in $failedExtensionsGrouped) {
        #Get-AzSubscription -SubscriptionId $group.Name -WarningAction SilentlyContinue
        $Subscription = Select-AzSubscription -SubscriptionId $group.Name -WarningAction SilentlyContinue
        Write-Host "Removing failed extensions from Subscription: $($Subscription.Subscription.Name) $($Subscription.Subscription.id)" -ForegroundColor Green
        foreach ($extension in $group.Group ) {
            $machinename = ($extension.machineid -split "/")[-1]
            $resourcetype = ($extension.machineid -split "/")[6]
            $ResourceGroupName = ($extension.machineid -split "/")[-5]
            switch ($resourcetype) {
                { $_ -eq "Microsoft.Compute" } { Remove-AzVMExtension -VMName $machinename -ResourceGroupName $ResourceGroupName -Name $extension.name -Force -AsJob }
                { $_ -eq "microsoft.hybridcompute" } { Remove-AzConnectedMachineExtension  -MachineName $machinename -ResourceGroupName $ResourceGroupName -Name $extension.name -NoWait }
                Default {}
            } 
        }
    }

    # Display Removal Operations
    $RemovalOperations
}
else { Write-Output "'RemoveAll' parameter wasn't passed to the runbook. Skipping removal section" }
