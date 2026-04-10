# Remove Azure Arc Extensions Runbook

This PowerShell runbook removes one or more Azure Arc extensions from all **Connected** Arc-enabled machines. It runs in an Azure Automation Account using a system-assigned managed identity and operates exclusively via `Invoke-AzRestMethod`, so it only requires the `Az.Accounts` module.

## What This Script Does

1. Connects to Azure using the Automation Account's managed identity
2. Reads the Boolean parameters to determine which extension types to remove
3. Queries Azure Resource Graph for instances of each selected extension on **Connected** machines only
4. Calls the ARM REST API to delete each extension
5. Produces a per-extension and overall summary report

## Required Module

| Module | Purpose |
|---|---|
| `Az.Accounts` | Authentication and `Invoke-AzRestMethod` |

> No other Az modules are needed. Resource Graph queries and extension deletions are all performed via REST.

## Required RBAC Permissions

Grant the following actions to the Automation Account's managed identity at the subscription or resource group level:

| Action | Purpose |
|---|---|
| `Microsoft.ResourceGraph/resources/read` | Query Resource Graph |
| `Microsoft.HybridCompute/machines/read` | Read Arc machines |
| `Microsoft.HybridCompute/machines/extensions/read` | Read Arc extensions |
| `Microsoft.HybridCompute/machines/extensions/delete` | Delete Arc extensions |

The recommended approach is a custom role named **"Azure Connected Machine extension remover"** containing only these four actions.

[Learn more about Azure Arc roles](https://learn.microsoft.com/en-us/azure/azure-arc/servers/security-permissions)

## Setup Instructions

### 1. Create an Automation Account

1. In the [Azure portal](https://portal.azure.com), create a new Automation Account
2. Enable **System assigned managed identity** on the Advanced tab

[Learn more](https://learn.microsoft.com/en-us/azure/automation/quickstarts/create-azure-automation-account-portal)

### 2. Assign Permissions to the Managed Identity

Assign the custom role (or the four RBAC actions above) to the managed identity at the appropriate scope (subscription or resource group).

[Learn more about role assignments](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal)

### 3. Create a Runtime Environment

1. In the Automation Account, go to **Runtime Environments** > **Create**
2. Select **PowerShell 7.6** as the runtime version
3. Add the `Az.Accounts` module

[Learn more about modules](https://learn.microsoft.com/en-us/azure/automation/shared-resources/modules)

### 4. Create and Configure the Runbook

1. Create a new PowerShell runbook named `RemoveAzureArcExtensions`
2. Select the runtime environment you created
3. Browse and upload `RemoveAzureArcExtensions.ps1`
4. Save and publish

### 5. Test and Schedule

1. Use the **Test pane** to run with `WhatIf = True` first to preview what would be removed
2. Once verified, publish and optionally link to a schedule

[Learn more about schedules](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules)

## Parameters

### Extension Selectors

Set to `$true` to remove that extension type. All default to `$false`.

| Parameter | Azure Extension Type |
|---|---|
| `ADAssessmentPlus` | ADAssessmentPlus |
| `ADSecurityAssessment` | ADSecurityAssessment |
| `AdminCenter` | AdminCenter |
| `AdvancedThreatProtection_Win` | AdvancedThreatProtection.Windows |
| `AssessmentPlatform` | AssessmentPlatform |
| `AzureMonitorLinuxAgent` | AzureMonitorLinuxAgent |
| `AzureMonitorWindowsAgent` | AzureMonitorWindowsAgent |
| `AzureSecurityLinuxAgent` | AzureSecurityLinuxAgent |
| `AzureSecurityWindowsAgent` | AzureSecurityWindowsAgent |
| `ChangeTracking_Linux` | ChangeTracking-Linux |
| `ChangeTracking_Windows` | ChangeTracking-Windows |
| `CustomScript` | CustomScript |
| `CustomScriptExtension` | CustomScriptExtension |
| `DependencyAgentLinux` | DependencyAgentLinux |
| `DependencyAgentWindows` | DependencyAgentWindows |
| `EdgeRemoteSupport` | EdgeRemoteSupport |
| `LinuxAgent_SqlServer` | LinuxAgent.SqlServer |
| `LinuxOsUpdateExtension` | LinuxOsUpdateExtension |
| `LinuxPatchExtension` | LinuxPatchExtension |
| `MDE_Linux` | MDE.Linux |
| `MDE_Windows` | MDE.Windows |
| `SQLAssessmentPlus` | SQLAssessmentPlus |
| `WindowsAgent_SqlServer` | WindowsAgent.SqlServer |
| `WindowsOsUpdateExtension` | WindowsOsUpdateExtension |
| `WindowsPatchExtension` | WindowsPatchExtension |
| `WindowsServerAssessment` | WindowsServerAssessment |

### General Options

| Parameter | Type | Default | Description |
|---|---|---|---|
| `SubscriptionIds` | `string[]` | *(all)* | Scope to specific subscription IDs. If omitted, all subscriptions visible to the managed identity are queried. |
| `WhatIf` | `bool` | `$false` | When `$true`, lists what would be removed without making any changes. |

## Usage Examples

**Remove MDE.Windows from all subscriptions:**
```powershell
.\RemoveAzureArcExtensions.ps1 -MDE_Windows $true
```

**Remove ChangeTracking-Windows scoped to two subscriptions:**
```powershell
.\RemoveAzureArcExtensions.ps1 -ChangeTracking_Windows $true `
    -SubscriptionIds @("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy")
```

**Dry run — preview MDE.Linux removal without making changes:**
```powershell
.\RemoveAzureArcExtensions.ps1 -MDE_Linux $true -WhatIf $true
```

**Remove multiple extensions at once:**
```powershell
.\RemoveAzureArcExtensions.ps1 -MDE_Windows $true -AzureMonitorWindowsAgent $true -ChangeTracking_Windows $true
```

## Output

The runbook produces three sections at the end of each run:

- **Extensions marked for deletion** — list of selected extension types
- **Per-extension report** — machines found, removals initiated, failures per extension type
- **Totals** — overall counts; in WhatIf mode, confirms no changes were made
- **Failed machines detail** — table of any machines where removal failed, including the error message

## Notes

- Only machines in **Connected** status are targeted. Disconnected or expired machines are excluded.
- Extension deletion is asynchronous. HTTP `202 Accepted` means the operation was initiated, not completed. Check the machine's extension status in the portal to confirm.
- At least one extension parameter must be set to `$true`, otherwise the runbook exits with an error.

## Additional Resources

- [Azure Arc-enabled servers](https://learn.microsoft.com/en-us/azure/azure-arc/servers/overview)
- [Azure Arc extensions](https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions)
- [Azure Automation](https://learn.microsoft.com/en-us/azure/automation/overview)
- [Azure Resource Graph](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview)
- [Invoke-AzRestMethod](https://learn.microsoft.com/en-us/powershell/module/az.accounts/invoke-azrestmethod)
