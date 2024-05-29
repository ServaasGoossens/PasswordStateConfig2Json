# PasswordStateConfig2Json
This PowerShell script allows you to track configuration changes in PasswordState. It reads the full configuration directly from the database and writes it to JSON files. You can then store these files in any version control system (like git).

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
The script masks sensitive data that is part of the configuration, such as keys and passwords. It replaces these values with asterisks before the data is stored on disk. Some non-sensitive data is also masked. This applies to data that changes regularly as a result of normal operations (hence, it is not configuration data).

__Note__: All fields of type VarBinary are masked. Most of these are encrypted (according to ClickStudios support). Encryption keys are obviously not encrypted, but they are masked as well. I may still have missed some data that should be masked. Please let me know by creating an issue.
