# ESU license creation and assignment script

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