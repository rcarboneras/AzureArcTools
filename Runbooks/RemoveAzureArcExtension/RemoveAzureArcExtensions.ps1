#requires -Modules Az.Accounts

<#
.SYNOPSIS
    Removes one or more Azure Arc extensions from connected machines.

.DESCRIPTION
    This runbook is designed to run in an Azure Automation Account.
    It authenticates using the Automation Account's System Assigned Managed Identity,
    queries Azure Resource Graph and removes extensions using ARM REST API calls
    via Invoke-AzRestMethod (part of Az.Accounts).

    NOTE: This runbook ONLY requires the Az.Accounts module. It does NOT need
    Az.ResourceGraph or Az.ConnectedMachine. All operations use Invoke-AzRestMethod.

    Each extension is represented as a Boolean parameter in the Portal.
    Set the extension(s) you want to remove to True. All others default to False.

    Required RBAC actions for the Managed Identity:
    -----------------------------------------------
    - Microsoft.ResourceGraph/resources/read                          (query Resource Graph)
    - Microsoft.HybridCompute/machines/read                           (read Arc machines)
    - Microsoft.HybridCompute/machines/extensions/read                (read Arc extensions)
    - Microsoft.HybridCompute/machines/extensions/delete              (delete Arc extensions)

    A custom role "Azure Connected Machine extension remover" with those four actions
    is the recommended least-privilege approach.

.PARAMETER SubscriptionIds
    Optional. One or more subscription IDs to scope the operation.
    If omitted, all subscriptions visible to the Managed Identity are queried.

.PARAMETER WhatIf
    When set to $true, no removal is performed. The runbook only lists the extensions 
    that would be removed.

.EXAMPLE
    # Remove MDE.Windows from all connected Arc machines (set MDE_Windows = True in Portal)
    .\Remove-AzureArcExtension.ps1 -MDE_Windows $true

.EXAMPLE
    # Dry run: preview what ChangeTracking-Windows removal would do
    .\Remove-AzureArcExtension.ps1 -ChangeTracking_Windows $true -WhatIf $true
#>

[CmdletBinding()]
Param (
    # ── Extension selectors (set to True to remove) ──────────────────────
    [bool]$ADAssessmentPlus              = $false,
    [bool]$ADSecurityAssessment          = $false,
    [bool]$AdminCenter                   = $false,
    [bool]$AdvancedThreatProtection_Win  = $false,
    [bool]$AssessmentPlatform            = $false,
    [bool]$AzureMonitorLinuxAgent        = $false,
    [bool]$AzureMonitorWindowsAgent      = $false,
    [bool]$AzureSecurityLinuxAgent       = $false,
    [bool]$AzureSecurityWindowsAgent     = $false,
    [bool]$ChangeTracking_Linux          = $false,
    [bool]$ChangeTracking_Windows        = $false,
    [bool]$CustomScript                  = $false,
    [bool]$CustomScriptExtension         = $false,
    [bool]$DependencyAgentLinux          = $false,
    [bool]$DependencyAgentWindows        = $false,
    [bool]$EdgeRemoteSupport             = $false,
    [bool]$LinuxAgent_SqlServer          = $false,
    [bool]$LinuxOsUpdateExtension        = $false,
    [bool]$LinuxPatchExtension           = $false,
    [bool]$MDE_Linux                     = $false,
    [bool]$MDE_Windows                   = $false,
    [bool]$SQLAssessmentPlus             = $false,
    [bool]$WindowsAgent_SqlServer        = $false,
    [bool]$WindowsOsUpdateExtension      = $false,
    [bool]$WindowsPatchExtension         = $false,
    [bool]$WindowsServerAssessment       = $false,

    # ── General options ──────────────────────────────────────────────────
    [string[]]$SubscriptionIds,
    [bool]$WhatIf = $false
)

#region --- Functions ---

Function Invoke-ResourceGraphQuery {
    <#
    .SYNOPSIS
        Queries Azure Resource Graph via REST API using Invoke-AzRestMethod.
        Handles pagination automatically. Does NOT require Az.ResourceGraph module.
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Query,

        [string[]]$Subscriptions,

        [int]$PageSize = 1000
    )

    $uri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01"
    $allResults = [System.Collections.ArrayList]::new()
    $skipToken = $null

    do {
        $body = @{
            query   = $Query
            options = @{
                '$top'  = $PageSize
            }
        }

        if ($Subscriptions) {
            $body["subscriptions"] = @($Subscriptions)
        }

        if ($skipToken) {
            $body.options['$skipToken'] = $skipToken
        }

        $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

        $response = Invoke-AzRestMethod -Uri $uri -Method POST -Payload $jsonBody

        if ($response.StatusCode -ne 200) {
            $errorDetail = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            $msg = if ($errorDetail.error.message) { $errorDetail.error.message } else { $response.Content }
            throw "Resource Graph query failed (HTTP $($response.StatusCode)): $msg"
        }

        $result = $response.Content | ConvertFrom-Json

        if ($result.data) {
            $null = $allResults.AddRange(@($result.data))
        }

        $skipToken = $result.'$skipToken'

    } while ($skipToken)

    return $allResults
}

#endregion

#region --- Parameter-to-Extension mapping ---
# Maps each Boolean parameter name to the real Azure extension type name
$ExtensionMap = @{
    'ADAssessmentPlus'              = 'ADAssessmentPlus'
    'ADSecurityAssessment'          = 'ADSecurityAssessment'
    'AdminCenter'                   = 'AdminCenter'
    'AdvancedThreatProtection_Win'  = 'AdvancedThreatProtection.Windows'
    'AssessmentPlatform'            = 'AssessmentPlatform'
    'AzureMonitorLinuxAgent'        = 'AzureMonitorLinuxAgent'
    'AzureMonitorWindowsAgent'      = 'AzureMonitorWindowsAgent'
    'AzureSecurityLinuxAgent'       = 'AzureSecurityLinuxAgent'
    'AzureSecurityWindowsAgent'     = 'AzureSecurityWindowsAgent'
    'ChangeTracking_Linux'          = 'ChangeTracking-Linux'
    'ChangeTracking_Windows'        = 'ChangeTracking-Windows'
    'CustomScript'                  = 'CustomScript'
    'CustomScriptExtension'         = 'CustomScriptExtension'
    'DependencyAgentLinux'          = 'DependencyAgentLinux'
    'DependencyAgentWindows'        = 'DependencyAgentWindows'
    'EdgeRemoteSupport'             = 'EdgeRemoteSupport'
    'LinuxAgent_SqlServer'          = 'LinuxAgent.SqlServer'
    'LinuxOsUpdateExtension'        = 'LinuxOsUpdateExtension'
    'LinuxPatchExtension'           = 'LinuxPatchExtension'
    'MDE_Linux'                     = 'MDE.Linux'
    'MDE_Windows'                   = 'MDE.Windows'
    'SQLAssessmentPlus'             = 'SQLAssessmentPlus'
    'WindowsAgent_SqlServer'        = 'WindowsAgent.SqlServer'
    'WindowsOsUpdateExtension'      = 'WindowsOsUpdateExtension'
    'WindowsPatchExtension'         = 'WindowsPatchExtension'
    'WindowsServerAssessment'       = 'WindowsServerAssessment'
}

# Determine which extensions were selected (set to True)
$SelectedExtensions = @()
foreach ($paramName in $ExtensionMap.Keys) {
    if ((Get-Variable -Name $paramName -ValueOnly -ErrorAction SilentlyContinue) -eq $true) {
        $SelectedExtensions += $ExtensionMap[$paramName]
    }
}

if ($SelectedExtensions.Count -eq 0) {
    Write-Error "No extensions selected. Set at least one extension parameter to True."
    throw "No extensions selected."
}

#endregion

#region --- Main ---

Write-Output "============================================="
Write-Output " Remove Azure Arc Extension Runbook"
Write-Output " WhatIf    : $WhatIf"
Write-Output " Started   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
Write-Output " Worker    : $($Env:COMPUTERNAME)"
Write-Output "============================================="
Write-Output ""
Write-Output ">>> EXTENSIONS MARKED FOR DELETION <<<"
Write-Output "--------------------------------------"
foreach ($ext in ($SelectedExtensions | Sort-Object)) {
    Write-Output "  [X] $ext"
}
Write-Output "--------------------------------------"
Write-Output "Total: $($SelectedExtensions.Count) extension type(s) selected"
Write-Output ""

# Authenticate using Automation Account Managed Identity
try {
    Write-Output "Connecting to Azure using Managed Identity..."
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "Successfully authenticated."
}
catch {
    Write-Error "Failed to connect to Azure with Managed Identity: $_"
    throw
}

# Global counters and per-extension tracking
$totalFound     = 0
$successCount   = 0
$failCount      = 0
$failedMachines = @()
$extensionStats = @{}

# Process each selected extension
foreach ($ExtensionName in $SelectedExtensions) {

    Write-Output "`n#############################################"
    Write-Output " Processing extension: $ExtensionName"
    Write-Output "#############################################"

    # Build the Resource Graph query for this extension on connected Arc machines
    $kqlQuery = @"
resources
| where type == 'microsoft.hybridcompute/machines/extensions'
| where properties.type =~ '$ExtensionName'
| extend 
    machineId          = tostring(split(id, '/extensions/', 0)[0]),
    extensionName      = tostring(properties.type),
    provisioningState  = tostring(properties.provisioningState),
    typeHandlerVersion = tostring(properties.typeHandlerVersion)
| join kind=inner (
    resources
    | where type == 'microsoft.hybridcompute/machines'
    | where properties.status == 'Connected'
    | project machineId = id, machineName = name, machineRG = resourceGroup, 
              machineSubscription = subscriptionId, machineLocation = location,
              osType = tostring(properties.osType)
) on machineId
| project extensionResourceId = id, machineName, machineRG, machineSubscription, 
          machineLocation, osType, extensionName, provisioningState, typeHandlerVersion
"@

    Write-Output "Querying Azure Resource Graph for '$ExtensionName'..."

    $queryParams = @{
        Query    = $kqlQuery
        PageSize = 1000
    }
    if ($SubscriptionIds) {
        $queryParams["Subscriptions"] = $SubscriptionIds
        Write-Output "Scoped to subscription(s): $($SubscriptionIds -join ', ')"
    }

    $extensionsFound = Invoke-ResourceGraphQuery @queryParams

    # Initialize stats for this extension
    $extensionStats[$ExtensionName] = [PSCustomObject]@{
        Found   = 0
        Success = 0
        Failed  = 0
    }

    if ($extensionsFound.Count -eq 0) {
        Write-Output "No instances of '$ExtensionName' found on connected Arc machines. Skipping."
        continue
    }

    $extensionStats[$ExtensionName].Found = $extensionsFound.Count
    $totalFound += $extensionsFound.Count

    # Display found extensions
    Write-Output "`nFound $($extensionsFound.Count) instance(s) of '$ExtensionName':"
    $extensionsFound | Select-Object machineName, machineRG, machineSubscription, machineLocation, osType, provisioningState, typeHandlerVersion |
        Format-Table -AutoSize | Out-String | Write-Output

    # WhatIf - skip removal
    if ($WhatIf) {
        Write-Output "[WhatIf] Skipping removal for '$ExtensionName'."
        continue
    }

    # Perform removal using ARM REST API
    Write-Output "Starting removal of '$ExtensionName'..."

    $grouped = $extensionsFound | Group-Object -Property machineSubscription
    foreach ($group in $grouped) {
        Write-Output "`n--- Subscription: $($group.Name) ($($group.Count) machine(s)) ---"

        foreach ($ext in $group.Group) {
            try {
                Write-Output "  Removing '$ExtensionName' from $($ext.machineName) (RG: $($ext.machineRG))..."

                $deleteUri = "https://management.azure.com/subscriptions/$($ext.machineSubscription)" +
                             "/resourceGroups/$($ext.machineRG)" +
                             "/providers/Microsoft.HybridCompute/machines/$($ext.machineName)" +
                             "/extensions/$($ext.extensionName)?api-version=2024-07-10"

                $response = Invoke-AzRestMethod -Uri $deleteUri -Method DELETE

                if ($response.StatusCode -in @(200, 202, 204)) {
                    $successCount++
                    $extensionStats[$ExtensionName].Success++
                    Write-Output "    -> Removal initiated successfully (HTTP $($response.StatusCode))."
                }
                else {
                    $failCount++
                    $extensionStats[$ExtensionName].Failed++
                    $errorContent = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $errorMsg = if ($errorContent.error.message) { $errorContent.error.message } else { "HTTP $($response.StatusCode)" }
                    $failedMachines += [PSCustomObject]@{
                        MachineName   = $ext.machineName
                        ResourceGroup = $ext.machineRG
                        Subscription  = $ext.machineSubscription
                        Extension     = $ExtensionName
                        Error         = $errorMsg
                    }
                    Write-Warning "    -> Failed (HTTP $($response.StatusCode)): $errorMsg"
                }
            }
            catch {
                $failCount++
                $extensionStats[$ExtensionName].Failed++
                $failedMachines += [PSCustomObject]@{
                    MachineName   = $ext.machineName
                    ResourceGroup = $ext.machineRG
                    Subscription  = $ext.machineSubscription
                    Extension     = $ExtensionName
                    Error         = $_.Exception.Message
                }
                Write-Warning "    -> Failed to remove extension from $($ext.machineName): $($_.Exception.Message)"
            }
        }
    }
}

# ── Final report ─────────────────────────────────────────────────────

$mode = if ($WhatIf) { "WHATIF" } else { "REMOVAL" }

Write-Output ""
Write-Output "============================================="
Write-Output " $mode SUMMARY"
Write-Output "============================================="
Write-Output " Completed : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
Write-Output ""

# Repeat the list of extensions marked for deletion
Write-Output ">>> EXTENSIONS MARKED FOR DELETION <<<"
Write-Output "--------------------------------------"
foreach ($ext in ($SelectedExtensions | Sort-Object)) {
    Write-Output "  [X] $ext"
}
Write-Output "--------------------------------------"
Write-Output ""

# Per-extension breakdown table
Write-Output ">>> PER-EXTENSION REPORT <<<"
Write-Output "--------------------------------------"

$reportRows = foreach ($extName in ($extensionStats.Keys | Sort-Object)) {
    $stat = $extensionStats[$extName]
    [PSCustomObject]@{
        Extension       = $extName
        'Machines Found'  = $stat.Found
        'Removal OK'      = $stat.Success
        'Failed'          = $stat.Failed
    }
}
$reportRows | Format-Table -AutoSize | Out-String | Write-Output

# Totals
Write-Output ">>> TOTALS <<<"
Write-Output "--------------------------------------"
Write-Output " Extension types selected : $($SelectedExtensions.Count)"
Write-Output " Total machines found     : $totalFound"
if (-not $WhatIf) {
    Write-Output " Removal initiated       : $successCount"
    Write-Output " Failed                  : $failCount"
}
else {
    Write-Output " No changes were made (WhatIf mode)."
}
Write-Output "============================================="

if ($failedMachines.Count -gt 0) {
    Write-Output ""
    Write-Output ">>> FAILED MACHINES DETAIL <<<"
    Write-Output "--------------------------------------"
    $failedMachines | Format-Table -AutoSize | Out-String | Write-Output
}

#endregion
