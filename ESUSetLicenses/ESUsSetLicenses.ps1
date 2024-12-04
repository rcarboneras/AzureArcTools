
#requires -Version 7.3.8 -module Az.ResourceGraph -module Az.Accounts

<#
.DESCRIPTION
   This script will create ESU licenses for Azure Arc enabled servers running Windows Server 2012 or 2012 R2 and link them to the servers automatically.
  #https://learn.microsoft.com/en-us/azure/azure-arc/servers/api-extended-security-updates
  #Pricing Details https://azure.microsoft.com/en-us/pricing/details/azure-arc/#extended-security

.EXAMPLE
  Extract the information of the Azure Arc servers that need ESU licenses and create the csv file with the licenses information
  A 'ESULicensesSourcefile.csv' file will be created with the information of the licenses to be created. Modify it as needed.
  No change is made with this switch parameter

   .\ESUsSetLicenses.ps1 -ReadOnly

.EXAMPLE
  Create the ESU licenses for the Azure Arc servers running Windows Server 2012 or 2012 R2, using the ESULicensesSourcefile.csv file
  A 'ESUAssigmentInfo.csv' file will be created with the information of the licenses created and the Azure Arc servers linked to them.

   .\ESUsSetLicenses.ps1 -ProvisionLicenses

.EXAMPLE
  Create the ESU licenses for the Azure Arc servers running Windows Server 2012 or 2012 R2, using a modified ModifiedESULicensesSourcefile.csv file
  A 'ESUAssigmentInfo.csv' file will be created with the information of the licenses created and the Azure Arc servers linked to them.

   .\ESUsSetLicenses.ps1 -ProvisionLicenses -SourceLicensesFile 'ModifiedESULicensesSourcefile.csv'

.EXAMPLE
  Assign the ESU licenses to the Azure Arc servers running Windows Server 2012 or 2012 R2, using the 'ESUAssigmentInfo.csv' file or a modified one

  .\ESUsSetLicenses.ps1 -AssignLicenses
  .\ESUsSetLicenses.ps1 -AssignLicenses -SourceLicenseAssigmentInfoFile ModifiedESUAssigmentInfo.csv

.EXAMPLE
  Create the ESU licenses for the Azure Arc servers running Windows Server 2012 or 2012 R2, using a modified ModifiedESULicensesSourcefile.csv file
  A 'ESUAssigmentInfo.csv' file will be created with the information of the licenses created and the Azure Arc servers linked to them.

  This sintaxis is for customers that already purchashed the ESU licenses for Year 1 and have the Year1InvoiceId (10 digits) available.

   .\ESUsSetLicenses.ps1 -ProvisionLicenses -SourceLicensesFile 'ModifiedESULicensesSourcefile.csv' -Year1InvoiceId 1234567890
#>


[CmdletBinding(DefaultParameterSetName = 'Readonly')]

Param (
  [Parameter(Mandatory = $false,
    ParameterSetName = 'Readonly')]
  [switch]$ReadOnly,
  [Parameter(Mandatory = $false,
    ParameterSetName = 'ProvisionLicenses')]
  [switch]$ProvisionLicenses,
  [Parameter(Mandatory = $false,
    ParameterSetName = 'ProvisionLicenses')]
  [string]$SourceLicensesFile,
  [Parameter(Mandatory = $false,
    ParameterSetName = 'AssignLicenses')]
  [switch]$AssignLicenses,
  [Parameter(Mandatory = $false,
    ParameterSetName = 'AssignLicenses')]
  [string]$SourceLicenseAssigmentInfoFile,
  [Parameter(Mandatory = $false,
    ParameterSetName = 'ProvisionLicenses')]
  [string]$Year1InvoiceId

)

$apiversion = "2023-06-20-preview"
if ($ReadOnly -or ($ProvisionLicenses -and (-not $SourceLicensesFile))) {
  if ($ReadOnly) {
    Write-Host "Running in read-only mode. No licenses will be created or linked." -ForegroundColor Yellow
  }
  Write-Host "Querying Azure Arc enabled servers..." -ForegroundColor Green

  #Query for Azure Arc enabled servers
  $ESUquery = @"
resources
| where type =~ "microsoft.hybridcompute/machines"
| where properties.osSku contains "Windows Server 2012"
| extend  model = tostring(properties.detectedProperties.model), status = tostring(properties.status)
| project location, name, target = replace (" Standard","", replace(" Datacenter","",tostring(properties.osSku))), Edition =  tostring(split(properties.osSku, ' ')[-1]), Processors = toint(properties.detectedProperties.logicalCoreCount),Type = iff(model contains "virtual" or  model contains "VMWare","Virtual","Physical"),status,model, id
"@



  $ESUArcServers = Search-AzGraph -Query $ESUquery -First 1000
  $ESUArcServers | Select-Object location, Name, target, Edition, Processors, Type, status, model, id |  Sort-Object -Property Processors -Descending | ft
  $ESUArcServers | Select-Object location, Name, target, Edition, Processors, Type, status, model, id |  Sort-Object -Property Processors -Descending | Export-Csv -Path .\ESUArcServers.csv -Force -NoTypeInformation


  Write-Host "Existing Azure Arc enabled servers with correspondent Edition & core information has been generated in file 'ESUArcServers.csv'`n`n`n" -ForegroundColor Yellow

  #region Create the license csv file 

  Write-Host "Creating the csv licensing file acording to the servers found ..." -ForegroundColor Green
  # For each license we need the following information location,state,target,Edition,Type,Processors,server,id

  $ESUlicenses = @()
  $ESUArcServers | ForEach-Object {
    # Processors calculation.
    # Minimal cores per license
    # Physical: 16 Cores
    # Virtual: 8 Cores

    if ($_.Type -eq "Physical") {
      $Edition = $_.Edition
      if ([int]$_.processors -lt 16) {
        $Processors = 16
      }
      else {
        $Processors = $_.processors
      }
    }
    else {
      #Virtual machine
      $Edition = "Standard"
      if ([Int]$_.processors -lt 8) {
        $Processors = 8
      }
      else {
        $Processors = $_.processors
      }
    }
    $obj = [PSCustomObject]@{
      location   = $_.location
      state      = "Activated" # State of the license: Activated or Deactivated
      target     = $_.target # 2012 or 2012 R2
      Edition    = $Edition # Standard or Datacenter
      Type       = $_.Type # Physical or Virtual (vCore or pCore)
      Processors = $Processors # Number of processors
      server     = $_.name
      status     = $_.status
      id         = $_.id
    }
    $ESUlicenses += $obj
  }


  $ESUlicenses | Export-Csv -Path .\ESULicensesSourcefile.csv -Force -NoTypeInformation


  Write-Host "`n'ESULicensesSourcefile.csv' was created. The file contains all the ESU license you need for your environment . Modify it as needed`n`n`n" -ForegroundColor Yellow


  #endregion
}
if ($ReadOnly) {
  break
}

if ($ProvisionLicenses) {
  #region Create licenses
  #Create licenses based on license file ESUlicensesSourcefile.csv

  Write-Host "Creating ESU licenses for Azure Arc enabled servers running Windows Server 2012 or 2012 R2..." -ForegroundColor Green

  if ($SourceLicensesFile) {
    $ESUlicensestoCreate = Import-Csv -Path .\$SourceLicensesFile -ErrorAction Stop
  }
  else {
    $ESUlicensestoCreate = Import-Csv -Path .\ESULicensesSourcefile.csv
  }


  # Group licenses by subscription
  $ESUlicensestoCreate | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name SubscriptionId -Value ($_.id -split "/")[2] }


  # Datacenter vs Standard Editions
  # Standard edition is ideal for those customers who want to have a physical or lightly virtualized environment.
  # This edition enables you to run up to two virtual instances of Windows Server with each license and Provisions all the same features as Datacenter edition.
  # https://www.microsoft.com/en-us/licensing/product-licensing/windows-server-2012-r2?activetab=windows-server-2012-r2-pivot%3aprimaryr2

  $ESUAssigmentInfo = @()
  foreach ($license in $ESUlicensestoCreate) {

    if ($license.Type -eq "Virtual") {
      $Type = "vCore"
    }
    else {
      $Type = "pCore"
    }

    $location = $license.location
    $state = $license.state
    $target = $license.target
    $Edition = $license.Edition
    $LicenseName = "ESULicense-$($license.server)"
    $Processors = $license.Processors
    $Type = $Type # pCore, vCore
    $SubscriptionId = $license.SubscriptionId
    $ResourceGroup = ($license.id -split "/")[4]

    if ($PSBoundParameters.ContainsKey('Year1InvoiceId')) {
      $payload = @"
      {
          "location": "$location", 
          "properties": {
              "licenseDetails": {
                  "state": "$state",
                  "target": "$target",
                  "Edition": "$Edition", 
                  "Type": "$Type",
                  "Processors": $Processors,
                  "volumeLicenseDetails": [
                    {
                      "programYear": "Year 1",
                      "invoiceId": "$Year1InvoiceId"
                    }
                  ]
              } 
          } 
      }
"@
    }
    else {
      $payload = @"
{
    "location": "$location", 
    "properties": {
        "licenseDetails": {
            "state": "$state",
            "target": "$target",
            "Edition": "$Edition", 
            "Type": "$Type",
            "Processors": $Processors 
        } 
    } 
}
"@
    }
    $payload | ConvertFrom-Json 

    #Provision license 
    try {
     
      $ESUlicense = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/Providers/Microsoft.HybridCompute/licenses/$($LicenseName)?api-version=$apiversion" -Method PUT -payload $payload -Verbose -ErrorAction Stop   
      $ESUlicenseid = $ESUlicense.Content | ConvertFrom-Json | Select-Object -ExpandProperty id
      $ESUCreatedobj = [PSCustomObject]@{
        ESUlicenseid = $ESUlicenseid
        ArcServerid  = $license.id
        location     = $license.location
      }
      $ESUAssigmentInfo += $ESUCreatedobj
     
    }
    catch {
      Write-Host "Could not create license for $($license.server):" -ForegroundColor Red; $_.Exception.Message
    }
  }

  $ESUAssigmentInfo | Export-Csv -Path .\ESUAssigmentInfo.csv -Force -NoTypeInformation

  Write-Host "Sucessfully created ESU licenses for $($ESUAssigmentInfo.count) Windows Server 2012 or 2012 R2 servers. File 'ESUAssigmentInfo.csv' contains Licenses ids, and correspondent Arc servers." -ForegroundColor Green

  #endregion
}

# region Link licenses to servers
if ($AssignLicenses) {
  #region Assign licenses
  #Assign licenses based on license file ESUAssigmentInfo.csv

  Write-Host "Assigning ESU licenses to Azure Arc enabled servers running Windows Server 2012 or 2012 R2..." -ForegroundColor Green

  if ($SourceLicenseAssigmentInfoFile) {
    $ESUAssigmentInfo = Import-Csv -Path .\$SourceLicenseAssigmentInfoFile -ErrorAction Stop
  }
  else {
    $ESUAssigmentInfo = Import-Csv -Path .\ESUAssigmentInfo.csv
  }

  foreach ($license in $ESUAssigmentInfo) {
    $ArcResourceid = $license.ArcServerid
    $Arcmachinelocation = $license.location
    $ESUlicenseid = $license.ESUlicenseid
  
  
    $payload = @"
{ 
  "location": "$Arcmachinelocation", 
  "properties": { 
    "esuProfile": { 
      "assignedLicense": "$ESUlicenseid"
    } 
  } 
}
"@
    $ArcResourceid
    try {
      Invoke-AzRestMethod -Path "$ArcResourceid/licenseProfiles/default?api-version=$apiversion" -Method PUT -payload $payload -Verbose -ErrorAction Stop
    }
    catch { Write-Host "Error assigning license to $($ArcResourceid):" -ForegroundColor Red; $_.Exception.Message }
  }

  #endregion
}

break
#Delete a license

$Path = "/$subscripionid/resourceGroups/arc-demo/Providers/Microsoft.HybridCompute/licenses/ESUlicense-SQL2014"
Invoke-AzRestMethod -Path "$($Path)?api-version=$apiversion" -Method DELETE -Verbose

#DELETE  
#https://management.azure.com/subscriptions/SUBSCRIPTION_ID/resourceGroups/RESOURCE_GROUP_NAME/Providers/Microsoft.HybridCompute/licenses/LICENSE_NAME?api-version=2023-06-20-preview
