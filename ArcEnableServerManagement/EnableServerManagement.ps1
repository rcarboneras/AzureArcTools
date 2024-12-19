
#Requires -Modules @(@{"ModuleName"="Az.Accounts"; RequiredVersion="4.0.0",ModuleName="Az.ResourceGraph"; RequiredVersion="1.0.1"})
.DESCRIPTION
   This script enables Software Assurance benefits for Azure Arc servers (Server Management), as decribed in the following
   document # https://learn.microsoft.com/en-us/azure/azure-arc/servers/windows-server-management-overview.
   The script queries the Azure Arc servers in the tenant and enables Software Assurance benefits for the servers that are eligible for the benefits.

.PARAMETER SubscriptionIds
    Scope the query to the specified SubscriptionId(s)
.PARAMETER ResourceGroupName
    Scope the query to the specified ResourceGroupName(s)

.EXAMPLE
    .\EnableServerManagement.ps1
    This example enables Software Assurance benefits for Azure Arc servers in all subscriptions in the tenant.

.EXAMPLE
    .\EnableServerManagement.ps1 -ResourceGroupName arc-demo
    This example enables Software Assurance benefits for Azure Arc servers in the 'arc-demo' resource group.
   
.EXAMPLE
    .\EnableServerManagement.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
    This example enables Software Assurance benefits for Azure Arc servers in the specified subscription.

#>

Param (
    [string[]]$SubscriptionIds,
    [string[]]$ResourceGroupNames
)
Function QueryGraphPaged {
    [CmdletBinding()]
    param (
        $PageSize,
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

$apiversion = "2023-10-03-preview"
$LicenseMode = "NotActivated" # SoftwareAssurance, PayAsYouGo, NotActivated
$timestamp = Get-Date -Format "yyyyMMddHHmmss"

$benefitsStatus = switch ($LicenseMode) {
    "SoftwareAssurance" { "Activated" }
    "PayAsYouGo" { "Activated via Pay-as-you-go" }
    "NotActivated" { "Not activated" }
    default { "Not activated" }
}

$KQLquery = @"
resources
| where type =~ "microsoft.hybridcompute/machines"
| extend status = properties.status
| where status != "Expired"
| extend operatingSystem = properties.osSku
| where properties.osType =~ 'windows' and operatingSystem !contains "2008"
| extend licenseProfile = properties.licenseProfile
| extend licenseStatus = tostring(licenseProfile.licenseStatus)
| extend licenseChannel = tostring(licenseProfile.licenseChannel)
| extend productSubscriptionStatus = tostring(licenseProfile.productProfile.subscriptionStatus)
| extend softwareAssurance = licenseProfile.softwareAssurance
| extend softwareAssuranceCustomer = licenseProfile.softwareAssurance.softwareAssuranceCustomer
| extend coreCount = toint(properties.detectedProperties.coreCount)
| extend logicalCoreCount = toint(properties.detectedProperties.logicalCoreCount)
| extend BenefitsStatus = case(
    softwareAssuranceCustomer == true, "Activated",
    (licenseStatus =~ "Licensed" and licenseChannel =~ "PGS:TB") or productSubscriptionStatus =~ "Enabled", "Activated via Pay-as-you-go",
    isnull(softwareAssurance) or isnull(softwareAssuranceCustomer) or softwareAssuranceCustomer == false, "Not activated",
    "Not activated")
| project name, status,coreCount, logicalCoreCount, BenefitsStatus, resourceGroup, subscriptionId, operatingSystem, id, type, location, kind, tags
| order by ['logicalCoreCount'] desc 
| where BenefitsStatus == "$benefitsStatus"
"@

if ($PSBoundParameters.ContainsKey('SubscriptionIds')) {
    $KQLquery = $KQLquery + "`n| where subscriptionId in ('" + ($SubscriptionIds -join "','") + "')"
}

if ($PSBoundParameters.ContainsKey('ResourceGroupNames')) {
    $KQLquery = $KQLquery + "`n| where resourceGroup in~ ('" + ($ResourceGroupNames -join "','").ToLower() + "')"
}


try {
    $results = QueryGraphPaged -PageSize 500 -query $KQLquery -ErrorAction Stop
    
}
catch {
    Write-Host "An error occurred while querying the resources" -ForegroundColor Red
    if ($_.exception.response.content -match "There must be at least one subscription that is eligible to contain resources") {
        Write-Host "Please select a subscription first using 'Select-AzSubscription' command, and then run the script again." -ForegroundColor Yellow
        exit
    }
    else {
        exit
    }
}


# Query to check which servers are activated for Software Assurance benefits
$KQLqueryServeractivated = @"
resources
| where type =~ "microsoft.hybridcompute/machines"
| extend status = properties.status
| where status != "Expired"
| extend operatingSystem = properties.osSku
| where properties.osType =~ 'windows' and operatingSystem !contains "2008"
| extend licenseProfile = properties.licenseProfile
| extend licenseStatus = tostring(licenseProfile.licenseStatus)
| extend licenseChannel = tostring(licenseProfile.licenseChannel)
| extend productSubscriptionStatus = tostring(licenseProfile.productProfile.subscriptionStatus)
| extend softwareAssurance = licenseProfile.softwareAssurance
| extend softwareAssuranceCustomer = licenseProfile.softwareAssurance.softwareAssuranceCustomer
| extend coreCount = toint(properties.detectedProperties.coreCount)
| extend logicalCoreCount = toint(properties.detectedProperties.logicalCoreCount)
| extend benefitsStatus = case(
    softwareAssuranceCustomer == true, "Activated",
    (licenseStatus =~ "Licensed" and licenseChannel =~ "PGS:TB") or productSubscriptionStatus =~ "Enabled", "Activated via Pay-as-you-go",
    isnull(softwareAssurance) or isnull(softwareAssuranceCustomer) or softwareAssuranceCustomer == false, "Not activated",
    "Not activated")
| where benefitsStatus == "Activated"
| extend revenueUSD = round(coreCount * 1.05,2)
| extend cloudprovider = properties.detectedProperties.cloudprovider
| project name, status,coreCount, logicalCoreCount,revenueUSD, benefitsStatus, resourceGroup, subscriptionId, operatingSystem, id, type, location, kind, tags
| order by ['logicalCoreCount'] desc
| summarize totalrevenue = sum(revenueUSD)
"@

#ENABLEMENT
# This section enables Server Managemen) (Software Assurance benefits) for the selected servers


Write-Host "$($results | Format-Table Name,OperatingSystem,BenefitsStatus,status,logicalCoreCount,resourcegroup, location, subscriptionid | Out-String)" -ForegroundColor Green

# Export the list of servers to a CSV file
$results | Select-Object Name, BenefitsStatus, status, logicalCoreCount, resourcegroup, location, subscriptionid | Export-Csv -notypeinformation -Path ".\AzureArcServerstoActivateSM-$($timestamp).csv"

if ($results.Count -eq 0) {
    Write-Host "No Azure Arc servers were found to activate for Software Assurance benefits." -ForegroundColor Yellow
    exit
}

Write-Host "A total of $($results.Count) Azure Arc servers and $(($results | Measure-Object -Sum logicalCoreCount).Sum) cores will be enabled for Software Assurance benefits.`nPlease see file 'AzureArcServerstoActivateSM-$($timestamp).csv' for more details. `n" -Foregroundcolor Yellow
Write-Host "Press ENTER to continue." -ForegroundColor White

$response = Read-Host
if ($response -ne "") {
    Write-Host "Process aborted by the user" -ForegroundColor Red
    break
}

# Define the results CSV file path
$csvFilePath = ".\AzureArcServerstoActivateSM-Results-$($timestamp).csv"

# Check if the CSV file exists
if (-Not (Test-Path -Path $csvFilePath)) {
    # If the file does not exist, create it and add the headers
    "name,OperatingSystem,Status,BenefitsStatus,ResourceGroup,LogicalCoreCount,SubscriptionId,Location,details" | Out-File -Path $csvFilePath
}

Write-Host "Enabling Software Assurance benefits for the selected servers..." -ForegroundColor Green

# Get the access token
$profile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile 
$profileClient = [Microsoft.Azure.Commands.ResourceManager.Common.rmProfileClient]::new( $profile ) 
$tenantId = (Get-AzContext).Tenant.id
$token = $profileClient.AcquireAccessToken($tenantId) 
$header = @{ 
    'Content-Type'  = 'application/json' 
    'Authorization' = 'Bearer ' + $token.AccessToken 
}

# Results are grouped by subscription

$ResultsGroupedbysub = $results | Group-Object -Property subscriptionId
foreach ($group in $ResultsGroupedbysub) {

    $Subscriptionid = $group.Name # SelectS the subscription id for each group

    $subscription = Select-AzSubscription -SubscriptionId $Subscriptionid -WarningAction SilentlyContinue -Tenant $tenantId
    Write-Host " Working in subscription $($group.Name) $($Subscription.Subscriptionid)" -ForegroundColor Yellow
    foreach ($arcobject in $group.Group ) {
        $machinename = $arcobject.name
        $operatingSystem = $arcobject.operatingSystem
        $status = $arcobject.status
        $ResourceGroup = $arcobject.resourceGroup
        $coreCount = $arcobject.coreCount
        $logicalCoreCount = $arcobject.logicalCoreCount
        $location = $arcobject.location
        $uri = [System.Uri]::new( "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.HybridCompute/machines/$machineName/licenseProfiles/default?api-version=$apiversion" ) 
        $contentType = "application/json"  
        $data = @{         
            location   = $location; 
            properties = @{ 
                softwareAssurance = @{ 
                    softwareAssuranceCustomer = $true
                }
            }
        }
        $json = $data | ConvertTo-Json
        #Launch the activation
        try {
            $response = Invoke-RestMethod -Method PUT -Uri $uri.AbsoluteUri -ContentType $contentType -Headers $header -Body $json
            $serverObject = [PSCustomObject]@{
                Name             = $machinename
                OperatingSystem  = $operatingSystem
                Status           = $status
                BenefitsStatus   = "Activated"
                ResourceGroup    = $ResourceGroup
                LogicalCoreCount = $logicalCoreCount
                SubscriptionId   = $subscriptionId
                Location         = $location
                details          = "OK"
            }
            $serverObject | Export-Csv -Path $csvFilePath -NoTypeInformation -Append
            Write-Host "Software Assurance benefits enabled for the server '$($machinename)' in the subscription '$($Subscriptionid)'" -ForegroundColor Green
        }
        catch {
            Write-Host "An error occurred while enabling Software Assurance benefits for the server '$($machinename)' in the subscription '$($Subscriptionid)'" -ForegroundColor Red
            $serverObject = [PSCustomObject]@{
                Name             = $machinename
                OperatingSystem  = $operatingSystem
                Status           = $status
                BenefitsStatus   = "Not activated"
                ResourceGroup    = $ResourceGroup
                LogicalCoreCount = $logicalCoreCount
                SubscriptionId   = $subscriptionId
                Location         = $location
                details          = ($_.Errordetails.message | ConvertFrom-Json).error.message
            }
            $serverObject | Export-Csv -Path $csvFilePath -NoTypeInformation -Append
        }

    } 
}

Write-Host "`nThe process has finished. Please see the file '$csvFilePath' for more details." -ForegroundColor Green