# This script removes Hub workspace to the existing ones
# Requires Logic Analytics Agent installed in the remote servers


#Workspace to remove

$WorkspaceIdtoRemove = "6b6e6f95-9b26-41b5-80e9-4b21df76fb8e"


#Get current Workspaces
    
try {
    $mma = New-Object -ComObject 'AgentConfigManager.MGmtSVCCfg'
    $Workspaces = $mma.GetCloudWorkspaces()
    $currentWorkspaces = $Workspaces
}
catch { $script:currentWorkspaces = @("No Agent"); $mma = $null }
    
#Remove Workspace
if ($null -ne $mma) {
    $mma = New-Object -ComObject 'AgentConfigManager.MGmtSVCCfg'

    If ($null -ne $mma.GetCloudWorkspace($WorkspaceIdtoRemove)) {
        $mma.RemoveCloudWorkspace($WorkspaceIdtoRemove)
    }


    $mma.ReloadConfiguration()
    $Workspaces = $mma.GetCloudWorkspaces()

}
else { $Workspaces = "No Agent" }
    
$Newworkspaces = $Workspaces
    
$results = New-Object -TypeName PSObject -Property @{
    OldWorkSpaces = $currentWorkspaces | Select-Object -ExpandProperty workspaceId -ErrorAction SilentlyContinue
    NewWorkSpaces = $Newworkspaces | Select-Object -ExpandProperty workspaceId -ErrorAction SilentlyContinue
}

Write-Output $results | Format-List