#https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-data-collection-endpoint?tabs=PowerShellWindows#proxy-configuration
$ResourceGroupName = "Arc-Demo"
$Location = "westeurope"
$MachineName = "ARC2016SQL"
$TypeHandlerVersion = "1.19"
$settings = @{"proxy" = @{"mode" = "application";"address" = "http://proxy.contoso.com"}}

Set-AzConnectedMachineExtension -Name AzureMonitorWindowsAgent `
-ExtensionType AzureMonitorWindowsAgent `
-Publisher Microsoft.Azure.Monitor `
-ResourceGroupName $ResourceGroupName `
-MachineName $MachineName `
-Location $Location`
-TypeHandlerVersion $TypeHandlerVersion
-Settings $settings