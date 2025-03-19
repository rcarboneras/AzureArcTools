
# This script is used to clean up the Azure Arc agent and extensions from a Windows machine.
# ...existing code...

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$msg,

        [ValidateSet("INFO", "ERROR", "WARNING")]
        [System.String]$msgtype,
        
        [string]$LogPath = 'C:\logs\CleanUpArcAgent.log'
    )
    Write-Host $msg

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[${timestamp}] $msg"
    Add-Content -Path $LogPath -Value $logEntry
}

# This piece of code detects if the Azure Arc Agent has been already cleaned up


Write-Log -msg "Checking registry key..." -msgtype INFO
$registryPath = 'HKLM:\SOFTWARE\Microsoft\AzureArc'
$regName = 'AgentCleanedUp'
try {
    $regValue = (Get-ItemProperty -Path $registryPath -Name $regName -ErrorAction Stop).$regName
    if ($regValue -eq 1) {
        
        Write-Log -msg "Registry value is 1. Exiting script." -msgtype INFO
        exit
    }
    else {
        
        Write-Log -msg "Registry value is not 1. Continuing..." -msgtype INFO
    }
} catch {
    
    Write-Log -msg "Registry key not found or cannot be accessed. Continuing..." -msgtype ERROR
}


#Disconnecting the Azure Arc agent from the Azure Arc service
#azcmagent disconnect --force-local-only


Write-Log -msg "Ensuring himds, extensionservice, and gcarcservice services are running..." -msgtype INFO
$services = @("himds","extensionservice","gcarcservice")
$startTime = Get-Date

foreach ($svc in $services) {
    while ((Get-Service $svc -ErrorAction SilentlyContinue).Status -ne "Running") {
        Start-Sleep -Seconds 5
        
        Write-Log -msg "Waiting for $svc service to start..." -msgtype INFO
    }
    
    Write-Log -msg "$svc service is running." -msgtype INFO
}


#Stopping extension services
$services = @("Observability Remote Support Agent","SqlServerExtension","AutoAssessPatchService","Microsoft Defender For SQL","AzureSecurityAgent")
foreach ($svc in $services) {
    Stop-Service $svc -Force -Verbose -ErrorAction SilentlyContinue
    sc.exe delete $svc
    
    write-Log -msg "$svc service stopped and deleted" -msgtype INFO
}

#Stoping process to help remove the Azure Arc extensions without errors


write-Log -msg "Stopping Azure Arc processes..." -msgtype INFO

#Stop GC processes
Stop-Process -Name "gc_extension_service" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Service "extensionservice" -Force -Verbose -ErrorAction SilentlyContinue


#Stop AMA processes
Stop-Process -Name "AMAExtHealthMonitor" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "MOnAgentLauncher" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "MOnAgentCore" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "MonAgentManager" -Verbose -Force -ErrorAction SilentlyContinue

#Stop Change Tracking processes
Stop-Process -Name "cta_windows_handler" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "change_tracking_agent_windows_amd64" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "change_tracking_service" -Verbose -Force -ErrorAction SilentlyContinue

#Stop Update Management processes
Stop-Process -Name "AutoAssessPatchService" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "UpdateManagementActionExec" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "WindowsVmUpdateExtension" -Verbose -Force -ErrorAction SilentlyContinue

#Stop Azure Security Agent processes
Stop-Process -Name "AzureSecurityAgent" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "SecurityScanMgr" -Verbose -Force -ErrorAction SilentlyContinue

#Stop Windows Patch extension
Stop-Process -Name "AutoAssessPatchService" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "UpdateManagementActionExec" -Verbose -Force -ErrorAction SilentlyContinue
Stop-Process -Name "WindowsVMUpdateExtension" -Verbose -Force -ErrorAction SilentlyContinue


#Remove Azure Arc extensions

Write-Log -msg "Removing Azure Arc extensions..." -msgtype INFO
#azcmagent extension remove --name WindowsPatchExtension
azcmagent extension remove --all --verbose
#Start-Process -FilePath 'azcmagent' -ArgumentList 'extension','remove','--all' -Wait
write-Log -msg "Azure Arc extensions removed." -msgtype INFO

Stop-Service -Name "extensionservice" -Force -Verbose
write-Log -msg "Azure Arc extension service stopped." -msgtype INFO

Remove-Item -Force -Recurse -Path "C:\Packages\Plugins" -Verbose

#Disconnecting the Azure Arc agent from the Azure Arc service
try {
    
    Write-Log -msg "Disconnecting the Azure Arc agent from the Azure Arc service..." -msgtype INFO
    azcmagent disconnect --force-local-only  --verbose
    
}
catch {
    <#Do this if a terminating exception happens#>
}



# Write 1 to registry at the end
New-Item -Path $registryPath -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $registryPath -Name $regName -Value 1 -Type DWord -Force

Write-Log -msg "Script Finished. Registry key $regname set to 1" -msgtype INFO


$endTime = Get-Date
$elapsed = $endTime.Subtract($startTime)
$minutes = [math]::Floor($elapsed.TotalMinutes)
$seconds = $elapsed.Seconds

Write-Log -msg "Script completed in $minutes minute(s) and $seconds second(s)." -msgtype INFO