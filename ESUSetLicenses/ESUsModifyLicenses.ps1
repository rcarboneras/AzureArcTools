
#requires -Version 7.3.8 -module Az.ResourceGraph -module Az.Accounts

<#
.DESCRIPTION
   This script will either delete or unassign ESU licenses for Azure Arc enabled servers running Windows Server 2012 or 2012 R2 at scale
  #https://learn.microsoft.com/en-us/azure/azure-arc/servers/api-extended-security-updates
  #Pricing Details https://azure.microsoft.com/en-us/pricing/details/azure-arc/#extended-security


.EXAMPLE
  Delete all the ESU licenses in the 'arc-demo' resource group

  .\ESUsModifyLicenses.ps1 -ResourceGroupNames arc-demo -Action Delete

.EXAMPLE
   Delete all the ESU licenses in the subscriptions '71ac1fd6-9ebc-4a20-9667-xxxxxxxxxxxx'

  .\ESUsModifyLicenses.ps1 -SubscriptionIds 71ac1fd6-9ebc-4a20-9667-xxxxxxxxxxxx -Action Delete

.EXAMPLE
    Unlink all the ESU licenses from the Azure Arc servers in the 'arc-demo' resource group

  .\ESUsModifyLicenses.ps1 -ResourceGroupNames arc-demo -Action Unlink   
#>



[CmdletBinding()]
Param (
  [string[]]$SubscriptionIds,
  [string[]]$ResourceGroupNames,
  [Validateset('Unlink', 'Delete')]
  [string]$Action
)

Function QueryGraphPaged {
  [CmdletBinding()]
  param (
    $PageSize = 500,
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

$apiversion = "2023-06-20-preview"
$timestamp = Get-Date -Format "yyyyMMddHHmmss"


if ($PSBoundParameters.ContainsKey('Action')) {
  switch ($Action) {
    'Unlink' {

      #Query for Azure Arc ESU servers
      $KQLquery = @"
resources
| where type== "microsoft.hybridcompute/machines"
| where properties.osName == "windows" and properties.osSku contains "2012"
"@
 
      if ($PSBoundParameters.ContainsKey('SubscriptionIds')) {
        $KQLquery = $KQLquery + "`n| where subscriptionId in ('" + ($SubscriptionIds -join "','") + "')"
      }

      if ($PSBoundParameters.ContainsKey('ResourceGroupNames')) {
        $KQLquery = $KQLquery + "`n| where resourceGroup in ('" + ($ResourceGroupNames -join "','") + "')"
      }

      $ESUArcServers = QueryGraphPaged -query $KQLquery

if ($ESUArcServers.Count -eq 0) {
        Write-Host "No Azure Arc servers found with the above criteria" -ForegroundColor Yellow
        break
      }
$ESUArcServers | Select-Object name, @{N="osSku";E={$_.properties.osSku}},resourceGroup, location, subscriptionId | ft
$ESUArcServers | Select-Object name, @{N="osSku";E={$_.properties.osSku}},resourceGroup, location, subscriptionId | Export-Csv -Path ".\ESUArcServerstoUnlink-$timestamp.csv" -Force -NoTypeInformation

Write-Host "A total of $($ESUArcServers.Count) Azure Arc servers will be unlinked from its ESU license" -ForegroundColor Yellow


Read-Host "Press Enter to continue or Ctrl+C to cancel"


      foreach ($ESUArcServer in $ESUArcServers) {
        $SubscriptionId = $ESUArcServer.subscriptionId
        $ResourceGroup = $ESUArcServer.resourceGroup
        $MachineName = $ESUArcServer.name
        $payload = @"
{
  "location": "$($ESUArcServer.location)",
  "properties": {
    "esuProfile": {
    }
  }
}     
"@
        # Unlink the ESU license from the Azure Arc server
        $Unlinkresponse = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/Providers/Microsoft.HybridCompute/machines/$MachineName/licenseProfiles/default?api-version=$apiversion" -Method PUT -payload $payload -ErrorAction Stop   
        if ($Unlinkresponse.StatusCode -eq 201) {
          Write-Host "The Azure Arc server $MachineName has been unlinked from its ESU license" -ForegroundColor Green
          $ESUArcServer | Select-Object name, @{N="osSku";E={$_.properties.osSku}},resourceGroup, location, subscriptionId | Export-Csv -Path ".\ESUArcServerstoUnlinksucceded-$timestamp.csv" -Force -NoTypeInformation -Append
        }
        else {
          Write-Host "The Azure Arc server $MachineName could not be unlinked from its ESU license" -ForegroundColor Red
          $ESUArcServer | Select-Object name, @{N="osSku";E={$_.properties.osSku}},resourceGroup, location, subscriptionId | Export-Csv -Path ".\ESUArcServerstoUnlinkerrors-$timestamp.csv" -Force -NoTypeInformation -Append
          $Unlinkresponse
        }
      }
    }
    'Delete' {

      #Query for Azure Arc ESU licenses
      $KQLquery = @"
resources
| where type == "microsoft.hybridcompute/licenses"
"@
 
      if ($PSBoundParameters.ContainsKey('SubscriptionIds')) {
        $KQLquery = $KQLquery + "`n| where subscriptionId in ('" + ($SubscriptionIds -join "','") + "')"
      }

      if ($PSBoundParameters.ContainsKey('ResourceGroupNames')) {
        $KQLquery = $KQLquery + "`n| where resourceGroup in ('" + ($ResourceGroupNames -join "','") + "')"
      }

      $ESUArcLicenses = QueryGraphPaged -query $KQLquery

    
      if ($ESUArcLicenses.Count -eq 0) {
        Write-Host "No ESU licenses found with the above criteria" -ForegroundColor Yellow
        break
      }
      $ESUArcLicenses | Select-Object Name,@{N="edition";E={$_.properties.licenseDetails.edition}},@{N="cores";E={$_.properties.licenseDetails.processors}},@{N="coretype";E={$_.properties.licenseDetails.type}},resourcegroup,subscriptionid | Sort-Object -Property cores -Descending | ft
      $ESUArcLicenses | Select-Object Name,@{N="edition";E={$_.properties.licenseDetails.edition}},@{N="cores";E={$_.properties.licenseDetails.processors}},@{N="coretype";E={$_.properties.licenseDetails.type}},resourcegroup,subscriptionid | Sort-Object -Property cores -Descending | export-csv -Path ".\ESUArcLicensesToDelete-$timestamp.csv" -Force -NoTypeInformation
      Write-Host "A total of $($ESUArcLicenses.Count) ESU licenses will be deleted" -ForegroundColor Yellow

      read-host "Press Enter to continue or Ctrl+C to cancel"

      foreach ($license in $ESUArcLicenses) {
        $LicenseName = $license.Name
        $SubscriptionId = $license.subscriptionid
        $ResourceGroup = $license.resourcegroup
        $Deleteresponse = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/Providers/Microsoft.HybridCompute/licenses/$($LicenseName)?api-version=$apiversion" -Method DELETE -ErrorAction Stop   
        if ($Deleteresponse.StatusCode -eq 200) {
          Write-Host "The ESU license $LicenseName has been deleted" -ForegroundColor Green
          $license | Select-Object Name,@{N="edition";E={$_.properties.licenseDetails.edition}},@{N="cores";E={$_.properties.licenseDetails.processors}},@{N="coretype";E={$_.properties.licenseDetails.type}},resourcegroup,subscriptionid | Export-Csv -Path ".\ESUArcLicensesToDeletesucceded-$timestamp.csv" -Force -NoTypeInformation -Append
        }
        else {
          Write-Host "The ESU license $LicenseName could not be deleted" -ForegroundColor Red
          $license | Select-Object Name,@{N="edition";E={$_.properties.licenseDetails.edition}},@{N="cores";E={$_.properties.licenseDetails.processors}},@{N="coretype";E={$_.properties.licenseDetails.type}},resourcegroup,subscriptionid | Export-Csv -Path ".\ESUArcLicensesToDeleteerrors-$timestamp.csv" -Force -NoTypeInformation -Append
          $Deleteresponse | select StatusCode, Content | fl
        }
      }
    }
  }
}

#Delete a license

#DELETE  
#https://management.azure.com/subscriptions/SUBSCRIPTION_ID/resourceGroups/RESOURCE_GROUP_NAME/Providers/Microsoft.HybridCompute/licenses/LICENSE_NAME?api-version=2023-06-20-preview


#UNLINK
 
#https://management.azure.com/subscriptions/SUBSCRIPTION_ID/resourceGroups/RESOURCE_GROUP_NAME/providers/Microsoft.HybridCompute/machines/MACHINE_NAME/licenseProfiles/default?api-version=2023-06-20-preview
#PUT
#{
#  "location": "SAME_REGION_AS_MACHINE",
#  "properties": {
#    "esuProfile": {
#    }
#  }
#}

