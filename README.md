# AzureArcTools
This repository gathers a set of tools to work with your Azure Arc Environment


## Table of Contents

- **[AgentUpdates](/AgentUpdates/)**

  ***UpdateArcAgentFromTemplateMultipleWindowsnew.json*** - ARM template to update Azure Arc agents on multiple Windows servers using Custom Script Extension to upgrade the AzureConnectedMachineAgent.msi

  ***UpdateArcAgentFromTemplateMultipleWindowsWithProxy.json*** - ARM template for proxy-enabled environments to update Azure Arc agents on Windows servers through proxy configuration

- **[AMAProxy](/AMAProxy/)**

  ***AMAAgentAzureArcProxyPolicyWindows.json*** - Azure Policy definition to configure proxy settings for Azure Monitor Agent (AMA) on Windows Azure Arc servers

  ***AMAAgentAzureArcProxyPolicyLinux.json*** - Azure Policy definition to configure proxy settings for Azure Monitor Agent (AMA) on Linux Azure Arc servers

  ***SetProxyAMAAgent.ps1*** - PowerShell script for manual configuration of proxy settings for Azure Monitor Agent on Arc servers

- **[ArcEnableServerManagement](/ArcEnableServerManagement/)**

  ***EnableServerManagement.ps1*** - PowerShell script to enable Azure Arc server management features and capabilities

  ***WSReclass.kql*** - Kusto Query Language (KQL) query for workspace reclassification analysis

  ***Readme.md*** - Documentation for the server management enablement process

- **[ArcSQLServersBPA](/ArcSQLServersBPA/)**

  ***BPAConfigure Arc-enabled Servers with SQL Server extension installed to enable or disable SQL best practices assessment. Custom DCR.json*** - Azure Policy template to configure SQL Server Best Practices Assessment with custom Data Collection Rules

  ***BPAEnableAzureArc.ps1*** - PowerShell script to enable SQL Server Best Practices Assessment for Azure Arc-enabled SQL Servers

- **[ArcSQLSetLicenses](/ArcSQLSetLicenses/)**

  ***Get-SQLAzureArcReclassReport.ps1*** - PowerShell script to generate reports on SQL Server license classification for Azure Arc-enabled servers

  ***SetLicensestoExistingServersReclass.ps1*** - PowerShell script for bulk license assignment and reclassification of SQL Server licenses on Arc servers

  ***Inherit a tag from the resource group if missing - Azure Arc Servers.json*** - Azure Policy to automatically inherit tags from resource groups to Arc servers when tags are missing

- **[ArSQLMaintenance](/ArSQLMaintenance/)**

  ***RemoveOrphanedAzureArcSQLServers.ps1*** - PowerShell script to identify and remove orphaned Azure Arc SQL Server resources that no longer have corresponding machine resources

- **[CleanupAgent](/CleanupAgent/)**

  ***CleanUpArcAgent.ps1*** - PowerShell script to properly uninstall and clean up Azure Arc agent installations from servers

- **[ESUSetLicenses](/ESUSetLicenses/)**

  ***ESUsSetLicenses.ps1*** - PowerShell script for initial setup and configuration of Extended Security Update (ESU) licenses for Azure Arc servers

  ***ESUsModifyLicenses.ps1*** - PowerShell script to modify and update existing ESU license configurations

  ***ESUsChecklicenses.ps1*** - PowerShell script to validate and check the status of ESU licenses assigned to Arc servers

  ***ESULicensesSourcefilesample.csv*** - Sample CSV template file for bulk ESU license management operations

  ***README.md*** - Documentation for ESU license management tools and processes

- **[Extensions](/Extensions/)**

  ***Install-AzureArcExtensions.ps1*** - PowerShell script to install Azure Arc extensions on connected machines

  ***Update-AzureArcExtensions.ps1*** - PowerShell script to update existing Azure Arc extensions to newer versions

  ***Remove-FailedExtensions.ps1*** - PowerShell script to clean up and remove failed extension installations

  ***Get-ExtensionsVersionsReport.ps1*** - PowerShell script to generate inventory reports of installed extensions and their versions

  ***ExtensionSettings.psd1*** - PowerShell data configuration file containing extension settings and parameters

- **[MigrateMMAtoAMA](/MigrateMMAtoAMA/)**

  ***MigrateMachinesMMAtoAMA.ps1*** - PowerShell script for bulk migration from Microsoft Monitoring Agent (MMA) to Azure Monitor Agent (AMA)

  ***CustomScriptRemoveLogAnalitycsWorkspace.ps1*** - PowerShell script to remove Log Analytics workspace connections during migration cleanup

  ***ServerList.txt*** - Text file template containing the list of servers for migration operations

- **[Workbooks](/Workbooks/)**

  ***ChangeTrackingWorkbook.json*** - Azure Monitor workbook JSON template for visualizing and monitoring configuration changes across Azure Arc resources