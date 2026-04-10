# Azure Arc Runbooks

This folder contains automation runbooks for Azure Arc Server management. Each runbook is organized in its own subfolder with supporting documentation and resources.

## Available Runbooks

### RemoveExpiredAzureArcServers
Automatically removes expired Azure Arc-enabled servers that are tagged for decommissioning.

**Location**: `./RemoveExpiredAzureArcServers/`

**Features**:
- Queries Azure Resource Graph for expired servers
- Filters by decommissioning tag to prevent accidental deletion
- Runs in Azure Automation using managed identity
- Provides detailed deletion summary reports

**Setup**: See `RemoveExpiredAzureArcServers/README.md` for complete setup instructions

---

### RemoveAzureArcExtensions
Removes one or more Azure Arc extensions from all **Connected** Arc-enabled machines across one or more subscriptions.

**Location**: `./RemoveAzureArcExtension/`

**Features**:
- Supports 26 well-known Arc extension types via Boolean parameters
- Operates exclusively via `Invoke-AzRestMethod` — only `Az.Accounts` module required
- Optional `WhatIf` mode to preview removals without making changes
- Scopeable to specific subscription IDs
- Provides per-extension and overall summary reports

**Required module**: `Az.Accounts` only

**Setup**: See `RemoveAzureArcExtension/README.md` for complete setup instructions

---

## General Requirements

These runbooks are designed to run in **Azure Automation Accounts** with:
- System-assigned managed identity enabled
- PowerShell 7.6 runtime environment
- Required Azure PowerShell modules installed

## Deployment

Each runbook subfolder contains:
- PowerShell script (`*.ps1`)
- README with setup and configuration instructions
- Supporting documentation and images

To use a runbook:
1. Navigate to the runbook's subfolder
2. Follow the README setup instructions
3. Upload the script to your Azure Automation Account
4. Configure according to your requirements
