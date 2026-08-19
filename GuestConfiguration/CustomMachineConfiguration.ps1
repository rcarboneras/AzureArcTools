# https://learn.microsoft.com/en-us/azure/governance/machine-configuration/how-to/develop-custom-package/1-set-up-authoring-environment
# https://learn.microsoft.com/en-us/azure/governance/machine-configuration/how-to/develop-custom-package/2-create-package#author-a-configuration

# -----------------------------------------------------------------------------
# Custom Machine Configuration workflow
# -----------------------------------------------------------------------------
# 1. Author the DSC configuration and generate the MOF
# 2. Package the configuration into a Guest Configuration ZIP
# 3. Test compliance and apply remediation locally
# 4. Build the Azure Policy definition package
# 5. Publish the policy definition in Azure
# -----------------------------------------------------------------------------

# Prerequisites:
# Install-Module PSDscResources -Force
# Install-Module Az.Storage
# Install-Module GuestConfiguration

# -----------------------------------------------------------------------------
# 1) Author the DSC configuration
# -----------------------------------------------------------------------------

$ConfigurationName = 'RegistryExample'

Configuration $ConfigurationName
{
    Import-DscResource -ModuleName PSDscResources

    Registry RegistryExample {
        Ensure    = 'Present' # Use 'Absent' to remove the registry value
        Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\ExampleKey'
        ValueName = 'TestValue'
        ValueData = 'TestData'
    }
}

# Generate the MOF and rename it to a predictable name for the packaging step.
& $ConfigurationName
Rename-Item ".\$ConfigurationName\localhost.mof" "$($ConfigurationName).mof"

# -----------------------------------------------------------------------------
# 2) Package the configuration for Guest Configuration
# -----------------------------------------------------------------------------

$PackageParams = @{
    Name          = $ConfigurationName
    Configuration = ".\$ConfigurationName\$ConfigurationName.mof"
    Type          = 'AuditAndSet'
    Force         = $true
}

New-GuestConfigurationPackage @PackageParams


# -----------------------------------------------------------------------------
# 3) Test compliance and remediate locally
# -----------------------------------------------------------------------------

Get-GuestConfigurationPackageComplianceStatus -Path ".\$ConfigurationName.zip"
Start-GuestConfigurationPackageRemediation -Path ".\$ConfigurationName.zip" -Verbose

# -----------------------------------------------------------------------------
# 4) Build the Azure Policy package
# -----------------------------------------------------------------------------

# Set these before running this section:
$ResourceGroup = "arc-demo"
$StorageAccountName = 'racarbmcsa'
$ContainerName = 'machine-configuration'
$BlobName = "$($ConfigurationName).zip"

$DisplayName = "Registry $configurationname"


$newAccountParams = @{
    ResourceGroupname = $ResourceGroup
    Location          = $Location
    Name              = $Storageaccountname
    SkuName           = 'Standard_LRS'
}
$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $Storageaccountname -ErrorAction SilentlyContinue

if (-not $storageAccount) {
    $storageAccount = New-AzStorageAccount @newAccountParams
}

$container = Get-AzStorageContainer -Name 'machine-configuration' -Context $storageAccount.Context -ErrorAction SilentlyContinue

if (-not $container) {
    $container = New-AzStorageContainer -Name 'machine-configuration' -Permission Off -Context $storageAccount.Context
}

# User must have appropiated RBAC permissions in the Storage Account
$context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

# Adds the configuration package to the storage account. This example uploads the zip file 
$setParams = @{
    Container = 'machine-configuration'
    File      = $BlobName
    Context   = $context
}
$blob = Set-AzStorageBlobContent @setParams -Force



# Build the content URI consumed by Guest Configuration policy.



# Time Windows

$start = (Get-Date).ToUniversalTime().AddMinutes(-5)
$end   = $start.AddDays(7)   # keep <= 7 days for delegation key


# Generate (AAD-backed)

$sasToken = New-AzStorageBlobSASToken `
    -Container $ContainerName `
    -Blob $BlobName `
    -Permission r `
    -StartTime $start `
    -ExpiryTime $end `
    -Context $context

# --------------------------------------------
# Build Final Url

$contentUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName`?$sasToken"

$contentUri

$PolicyId = (New-Guid).Guid

$PolicyConfig = @{
    PolicyId      = $PolicyId
    ContentUri    = $ContentUri
    DisplayName   = $DisplayName
    Description   = 'This is an example to configure a registry configuration'
    Path          = './policies/deployIfNotExists'
    Platform      = 'Windows'
    PolicyVersion = '1.0.0'
    Mode          = 'ApplyAndAutoCorrect'
    LocalContentPath = ".\$($ConfigurationName).zip"
}

New-GuestConfigurationPolicy @PolicyConfig -Verbose -UseSystemAssignedIdentity

# -----------------------------------------------------------------------------
# 5) Publish the Azure Policy definition
# -----------------------------------------------------------------------------

# In case you don't want to use a SAS Token to download the package from the storage account, the Azure Arc Servers can authenticate directly with the storage account using their managed identities, given
# the appropriate role (Storage Blob Data Reader), so the new URI will be this one:
$NewContentUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"

#Replace the URI in the json file before creating the Azure Policy
$path = ".\policies\deployifnotexists\$($Configurationname)_DeployifNotExists.json"
$path
$Content = Get-Content -Raw -Path $path | ConvertFrom-Json

$Content.properties.metadata.guestConfiguration.contentUri = $NewContentUri
$Content.properties.policyRule.then.details.deployment.properties.template.resources[0].properties.guestConfiguration.contentUri = $NewContentUri
$Content.properties.policyRule.then.details.deployment.properties.template.resources[1].properties.guestConfiguration.contentUri = $NewContentUri
$Content.properties.policyRule.then.details.deployment.properties.template.resources[2].properties.guestConfiguration.contentUri = $NewContentUri

$Content | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding UTF8

#Create the Azure Policy

$PolicyDefinitionName = "Registry_$ConfigurationName"
New-AzPolicyDefinition -Name $PolicyDefinitionName -Policy ".\policies\deployIfNotExists\$($ConfigurationName)_deployIfNotExists.json"