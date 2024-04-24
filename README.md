# PasswordStateConfig2Json
Powershell script that reads the PasswordState configuration from the database and stores it in JSON format.

## Prerequisites
- [PasswordState](https://www.clickstudios.com.au/passwordstate.aspx) version 9.8 (see compatibility below)
- A user account with read access to the passwordstate database
- Powershell 7
- [Powershell Module SQLServer](https://www.powershellgallery.com/packages/SqlServer)

## Usage
1. Before running the script for the first time, create a new directory for storing the configuration data (json files).
2. Run the script pwdstateconfig2json.ps1 while providing the required parameters.

## Script parameters
- __-OutputPath__: Directory for storing the configuration data. Existing files are overwritten.
- __-DBServerInstance__: The name of the SQL Server instance ("hostname\instance").
- __-DBName__: The name of the database.
- __-DBConnectionEncrypt__: Whether and how to encrypt the connection to the database. See the [documentation for Invoke-Sqlcmd](https://learn.microsoft.com/en-us/powershell/module/sqlserver/invoke-sqlcmd?view=sqlserver-ps#-encrypt). 
- __-ConnectionString__: The connection string to connect to the database server. Use this parameter instead of DBServerInstance, DBName and DBConnectionEncrypt to get full control of the connection.

## Compatibility
The current version has been tested with PasswordState version 9.8 Build 9858. Whether it works with other versions depends on the differences in the DB Schema. See the [PasswordState Change log](https://www.clickstudios.com.au/passwordstate-changelog.aspx).

## What about keys and other sensitive data?
The script masks sensitive data that is part of the configuration. It does this by removing keys and passwords and replacing them with asterisks before the data is stored on disk.

__TAKE CARE__: I may have missed some data that should be masked. Please let me know by creating an issue. __You are responsible for verifying the results in your environment. No warranty, use at your own risk.__
