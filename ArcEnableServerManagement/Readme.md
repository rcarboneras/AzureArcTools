# EnableServerManagement

This PowerShell script enables Software Assurance benefits for Azure Arc servers. It queries Azure resources, processes the results, and updates the servers accordingly.

## Prerequisites

- Azure PowerShell module (`Az`)
- Appropriate permissions to query and manage Azure resources

## Installation

1. Install the Azure PowerShell module if not already installed:

    ```powershell
    Install-Module -Name Az -AllowClobber -Scope CurrentUser
    ```

2. Clone this repository or download the `EnableServerManagement.ps1` script.

## Usage

1. Open a PowerShell terminal.
2. Connect to your Azure account:

    ```powershell
    Connect-AzAccount
    ```

3. Run the script:

    ```powershell
    .\EnableServerManagement.ps1 -SubscriptionId <YourSubscriptionId> -ResourceGroupNames <YourResourceGroupNames>
    ```

    Replace `<YourSubscriptionId>` and `<YourResourceGroupNames>` with your actual subscription ID and resource group names.

## Parameters

- `SubscriptionId`: The ID of the Azure subscription.
- `ResourceGroupNames`: An array of resource group names to query.

## Example

```powershell
.\EnableServerManagement.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupNames "ResourceGroup1", "ResourceGroup2"