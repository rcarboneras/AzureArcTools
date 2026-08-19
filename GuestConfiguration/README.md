# Custom Machine Configuration Script

## Overview

The `CustomMachineConfiguration.ps1` script provides an end-to-end workflow for creating, packaging, testing, and publishing Azure Guest Configuration policies for Azure Arc-enabled servers. This script enables you to define desired configuration states using PowerShell DSC (Desired State Configuration) and deploy them as Azure Policy definitions.

## Workflow

This script follows a 5-step workflow:

1. **Author the DSC Configuration** - Define machine configuration using PowerShell DSC resources
2. **Package the Configuration** - Convert DSC configuration to a Guest Configuration ZIP package
3. **Test Compliance** - Validate and remediate the configuration locally before publishing
4. **Build the Azure Policy Package** - Upload package to Azure Storage and generate policy definitions
5. **Publish the Azure Policy** - Create and publish the policy definition in Azure

## Prerequisites

### Required PowerShell Modules

Install the following modules before running the script:

```powershell
Install-Module PSDscResources -Force
Install-Module Az.Storage
Install-Module GuestConfiguration
```

### Required Azure Resources

- **Resource Group** - An Azure resource group where you'll store policies
- **Storage Account** - To host the Guest Configuration packages
  - Must have Blob Storage container
  - Requires appropriate RBAC permissions (Storage Blob Data Contributor)

### Azure Permissions

- Ability to create Storage Containers and upload blobs
- Permission to create Azure Policy definitions in the target resource group
- Connected Azure CLI/PowerShell context with proper subscription and resource group access

## Configuration Variables

Before running the script, configure these variables in **Section 4 (Build the Azure Policy package)**:

```powershell
$ResourceGroup = "arc-demo"                           # Your resource group name
$StorageAccountName = 'racarbmcsa'                    # Unique storage account name
$ContainerName = 'machine-configuration'              # Blob container name
$BlobName = "$($ConfigurationName).zip"               # Generated package name
$DisplayName = "Registry $configurationname"          # Friendly policy name
```

## Usage Instructions

### Section 1: Author DSC Configuration

Customize the DSC configuration block to define your desired machine state. The example configures a registry setting:

```powershell
Configuration RegistryExample
{
    Import-DscResource -ModuleName PSDscResources
    
    Registry RegistryExample {
        Ensure    = 'Present'
        Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\ExampleKey'
        ValueName = 'TestValue'
        ValueData = 'TestData'
    }
}
```

**Common DSC Resources:**
- `Registry` - Manage Windows registry entries
- `File` - Create/remove files and directories
- `Service` - Configure Windows services
- `WindowsFeature` - Enable/disable Windows features
- Custom resources from PSDscResources module

### Section 2: Package Configuration

Execute this section to generate the Guest Configuration ZIP package:

```powershell
$PackageParams = @{
    Name          = $ConfigurationName
    Configuration = ".\$ConfigurationName\$ConfigurationName.mof"
    Type          = 'AuditAndSet'
    Force         = $true
}

New-GuestConfigurationPackage @PackageParams
```

This creates a `<ConfigurationName>.zip` file in the current directory.

**Package Types:**
- `Audit` - Check compliance without making changes
- `AuditAndSet` - Check compliance and apply remediation

### Section 3: Test Locally

Before publishing to Azure, test the package locally:

```powershell
# Check compliance status
Get-GuestConfigurationPackageComplianceStatus -Path ".\$ConfigurationName.zip"

# Apply remediation locally
Start-GuestConfigurationPackageRemediation -Path ".\$ConfigurationName.zip" -Verbose
```

### Section 4: Build Azure Policy Package

This section:
1. Creates/retrieves Azure Storage Account
2. Creates blob container
3. Uploads the configuration package
4. Generates SAS token for secure access
5. Creates Azure Policy definition

**Key steps:**
- Ensure you've configured the variables above
- Authenticate to Azure with appropriate permissions
- Policy files are generated in `./policies/deployIfNotExists/` directory

### Section 5: Publish Azure Policy

The script generates policy definition JSON and publishes it:

```powershell
$PolicyDefinitionName = "Registry_$ConfigurationName"
New-AzPolicyDefinition -Name $PolicyDefinitionName `
    -Policy ".\policies\deployIfNotExists\$($ConfigurationName)_deployIfNotExists.json"
```

## Storage Account Authentication Methods

### With SAS Token (Default)

Uses time-limited SAS tokens for secure access:
- Token validity: 7 days maximum
- Requires Storage Account credentials
- Best for non-production or temporary access

### With Managed Identity (Recommended)

Uses Azure Arc server's managed identity for authentication:
- No credentials exposed
- More secure for production
- Requires "Storage Blob Data Reader" RBAC role on storage account

To use managed identity:
1. Assign "Storage Blob Data Reader" role to Azure Arc server's managed identity
2. Update the content URI to remove SAS token:
   ```powershell
   $NewContentUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"
   ```

## Output Files

The script generates the following files:

- `<ConfigurationName>.mof` - Compiled machine configuration
- `<ConfigurationName>.zip` - Guest Configuration package
- `./policies/deployIfNotExists/<ConfigurationName>_DeployifNotExists.json` - Azure Policy definition

## Common Use Cases

### Example 1: Configure Windows Registry

```powershell
Configuration WindowsRegistry
{
    Import-DscResource -ModuleName PSDscResources
    
    Registry SecuritySetting {
        Ensure    = 'Present'
        Key       = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
        ValueName = 'RequireSecuritySignature'
        ValueData = '1'
    }
}
```

### Example 2: Configure Windows Feature

```powershell
Configuration WebServerFeature
{
    Import-DscResource -ModuleName PSDscResources
    
    WindowsFeature WebServer {
        Ensure = 'Present'
        Name   = 'Web-Server'
    }
}
```

## Troubleshooting

### Module Not Found
```powershell
Import-Module GuestConfiguration -Force
```

### Storage Account Access Denied
- Verify your Azure credentials are correct
- Check RBAC permissions on the storage account
- Ensure the resource group and storage account exist

### Policy Creation Fails
- Verify the JSON policy file syntax
- Check that the storage account is accessible
- Ensure SAS token hasn't expired

### Compliance Check Fails
- Review the MOF configuration for syntax errors
- Verify all required DSC resources are installed
- Check local system configuration against expected state

## References

- [Azure Guest Configuration Overview](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/)
- [Develop Custom Guest Configuration Packages](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/how-to/develop-custom-package/1-set-up-authoring-environment)
- [Azure Arc Servers Documentation](https://learn.microsoft.com/en-us/azure/azure-arc/servers/)
- [PowerShell DSC Resources](https://learn.microsoft.com/en-us/powershell/dsc/reference/)

## Support

For issues or questions related to:
- **Azure Arc**: Visit [Azure Arc documentation](https://learn.microsoft.com/en-us/azure/azure-arc/)
- **Guest Configuration**: Check [Guest Configuration troubleshooting guide](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/troubleshoot/)
- **PowerShell DSC**: Review [DSC documentation](https://learn.microsoft.com/en-us/powershell/dsc/)
