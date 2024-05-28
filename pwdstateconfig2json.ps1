# pwdstateconfig2json.ps1
#
# | Copyright (C) 2024 Servaas Goossens
# | This Source Code Form is subject to the terms of the Mozilla Public
# | License, v. 2.0. If a copy of the MPL was not distributed with this
# | file, You can obtain one at https://mozilla.org/MPL/2.0/.
# | 
# | Some parts of the file sqlqueries.jsonc (as indicated there) is subject
# | to CC BY-SA 3.0 (instead of the MPL). See https://creativecommons.org/licenses/by-sa/3.0/
#
# This script reads the configuration data from a passwordstate database
# and writes it to a set of JSON files. 
#
# What data to read is specified by sqlqueries.jsonc. Some values, such
# as passwords and other secrets, are masked (replaced by "********").
# This is automatically done for fields of type VarBinary (many of which
# contain encrypted data). Additional fields to be masked can be specified 
# in sqlqueries.jsonc.
#
# When done, a file _latestlog.json is created for diagnostics.
#
# The script returns the number of files written (excl. the log file)
#
# Tip: Store the json files in git to easily detect and track changes.
#
# Required module: SQLServer
#  > install-module -Name SQLServer -Verbose
param (
  # Directory for storing the configuration data
  [Parameter(Mandatory)]
  [string] $OutputPath,

  # The name of the SQL Server instance ("hostname\instance")
  [Parameter()]
  [string] $DBServerInstance,

  # The name of the database.
  [Parameter()]
  [string] $DBName,

  # Whether and how to encrypt the connection to the database.
  # See https://learn.microsoft.com/en-us/powershell/module/sqlserver/invoke-sqlcmd?view=sqlserver-ps#-encrypt
  [Parameter()]
  [ValidateSet("Strict", "Mandatory", "Optional")]
  [string] $DBConnectionEncrypt,

  # The connection string to connect to the database server
  # Use this parameter instead of DBServerInstance, DBName and DBConnectionEncrypt to get full control of the connection.
  [Parameter()]
  [string] $ConnectionString
)
Import-Module SQLServer

$sqlqueriesfile = Join-Path -Path $PSScriptRoot -ChildPath "sqlqueries.jsonc"
$logfile = Join-Path -Path $OutputPath -ChildPath "_latestlog.json"

function Main {
    # read sqlqueries file, remove comments then convert to objects
    $SqlQueriesData = Get-Content -Path $sqlqueriesfile
    $SqlQueries = $SqlQueriesData -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/' | ConvertFrom-JSON

    if (!(Test-Path -Path $OutputPath -PathType Container)) {
        Throw "Path does not exist or is not a directory: $OutputPath"
    }

    $logdata = [ordered]@{
        "DBServerInstance" = $DBServerInstance
        "DBName" = $DBName
        "DBConnectionEncrypt" = $DBConnectionEncrypt
        "ConnectionString" = (MaskPasswordInConnectionString -ConnectionString $ConnectionString)
        "OutputPath" = $OutputPath
        "ItemCount" = $SqlQueries.Count
        "FilesWritten" = 0
        "ErrorCount" = 0
        "TimestampStart" = (Get-Date).tostring('o')
        "TimestampEnd" = ""
        "Items" = $SqlQueries
    }

    foreach ($item in $SqlQueries) {
        AddRequiredProperties -object $item
        $item.Filepath = Join-Path -Path $OutputPath -ChildPath "$($item.Name).json"

        if ($null -eq $item.Query) {
            $item.Query = GenerateSQLQuery -Name $item.Name -TableName $item.tablename
        }
        elseif ($item.Query -is [array]) {
            $item.Query = $item.Query | Join-String -Separator "`n"
        }
        try {
            $data = ExecuteSQLForJsonQuery -DBServerInstance $DBServerInstance -DBName $DBName -DBConnectionEncrypt $DBConnectionEncrypt -ConnectionString $ConnectionString -SQLForJsonQuery $item.Query
            if ($null -eq $data) {
                # No data, meaning the table is empty. Create JSON with empty array.
                $data = "{ ""$($item.Name)"": [] }" | ConvertFrom-Json
            }
            else {
                # Mask all Encrypted (varbinary) fields as well as the fields already specified in MaskProperties (from sqlqueries.jsonc)
                [array]$varBinaryFields = GetVarBinaryFields -TableName $item.TableName -DBServerInstance $DBServerInstance -DBName $DBName -DBConnectionEncrypt $DBConnectionEncrypt -ConnectionString $ConnectionString 
                [array]$item.MaskProperties = $($item.MaskProperties; $varBinaryFields) | Sort-Object -Unique
                if ($null -ne $item.MaskProperties) {
                    MaskProperties -Properties $item.MaskProperties -Items $data.($Item.Name)
                }
            }
            $data | ConvertTo-Json -Depth 10 | Set-Content -Path $item.Filepath
            $logdata.FilesWritten = $logdata.FilesWritten + 1
        }
        catch {
            $logdata.ErrorCount = $logdata.ErrorCount + 1
            AddException -object $item -ErrorRecord $_
            Write-Error "An error occured when executing query for $($item.name): $($item.ExceptionMessage). See $logfile for details."
        }
    }
    $logdata.TimestampEnd = (get-date).tostring('o')

    # Write logdata to file as json (and ignore 'depth exceeded' warnings when converting to json)
    $logdata | ConvertTo-Json -Depth 4 -WarningAction SilentlyContinue | Set-Content -Path $logfile
    return $logdata.FilesWritten
}

$RequiredProperties = @(
    "Name",
    "Query",
    "TableName",
    "MaskProperties",
    "Filepath"
)

# Add missing properties to the given object and initialize them with null.
function AddRequiredProperties {
    param(
        [Parameter(Mandatory)]
        [Object] $object
    )
    foreach ($property in $RequiredProperties) {
        if ($object.PSobject.Properties.Name -notcontains $property) {
            Add-Member -InputObject $object -MemberType NoteProperty -Name $property -Value $null
        }
    }
}

# Add a few properties to the given object with info about the given exception
function AddException {
    param(
        [Parameter(Mandatory)]
        [Object] $object,

        [Parameter(Mandatory)]
        [Object] $ErrorRecord
    )
    Add-Member -InputObject $object -MemberType NoteProperty -Name "ExceptionMessage" -Value $ErrorRecord.Exception.Message
    Add-Member -InputObject $object -MemberType NoteProperty -Name "ExceptionType" -Value $ErrorRecord.Exception.GetType().Name
    Add-Member -InputObject $object -MemberType NoteProperty -Name "Exception" -Value $ErrorRecord
}

# Generate a straightforward SQL query that returns JSON data
function GenerateSQLQuery {
    param(
        # strict parameter validation to prevent sql injection
        [Parameter(Mandatory)]
        [ValidatePattern("^[a-zA-Z_][a-zA-Z0-9_]*$")]
        [string] $Name,

        # strict parameter validation to prevent sql injection
        [Parameter(Mandatory)]
        [ValidatePattern("^[a-zA-Z_][a-zA-Z0-9_@$#]*$")]
        [string] $TableName
    )

    return "SELECT * FROM [$TableName] FOR JSON PATH, ROOT ('$Name')"
}

# Execute SQL Query, which must return JSON data ("for json"). Return the objects converted from json.
function ExecuteSQLForJsonQuery {
    param (
        [Parameter()]
        [string] $DBServerInstance,

        [Parameter()]
        [string] $DBName,

        [Parameter()]
        [ValidateSet("", "Strict", "Mandatory", "Optional")]
        [string] $DBConnectionEncrypt,

        [Parameter()]
        [string] $ConnectionString,

        [Parameter(Mandatory)]
        [string] $SQLForJsonQuery
    )
    if ($ConnectionString) {
        $data = Invoke-SqlCmd -ConnectionString $ConnectionString -Query $SQLForJsonQuery -AbortOnError
    }
    else {
        $data = Invoke-SqlCmd -ServerInstance $DBServerInstance -Database $DBName -Encrypt $DBConnectionEncrypt -Query $SQLForJsonQuery -AbortOnError
    }

    if ($null -eq $data) {
        $result = $null
    }
    elseif ($data.length -eq 1) {
        $result = $data[0] | ConvertFrom-Json
    }
    elseif ($data.ItemArray.Length -ge 1) {
        $result = $data.ItemArray | Join-String -Separator "" | ConvertFrom-Json
    }
    else {
        throw "Could not determine how to parse the data. Expecting a string value formatted as json."
    }
    return $result
}


# Returns the list of VarBinary fields in the given table. 
# In a passwordstate database, columns of type VarBinary are encrypted (according to ClickStudio Support)
# (I wouldn't expect that the Hash and GUID columns are encrypted, btw.)
function GetVarBinaryFields {
    param (
        [Parameter()]
        [string] $DBServerInstance,

        [Parameter()]
        [string] $DBName,

        [Parameter()]
        [ValidateSet("", "Strict", "Mandatory", "Optional")]
        [string] $DBConnectionEncrypt,

        [Parameter()]
        [string] $ConnectionString,

        [Parameter(Mandatory)]
        [string] $TableName
    )
    $query = @"
SELECT col.name 
FROM sys.columns col
JOIN sys.tables tab ON tab.object_id = col.object_id
JOIN sys.types typ ON typ.user_type_id = col.user_type_id
WHERE 
    tab.name = '$TableName'
    AND typ.name = 'varbinary'
"@
    if ($ConnectionString) {
        $data = Invoke-SqlCmd -ConnectionString $ConnectionString -Query $query -AbortOnError
    }
    else {
        $data = Invoke-SqlCmd -ServerInstance $DBServerInstance -Database $DBName -Encrypt $DBConnectionEncrypt -Query $query -AbortOnError
    }

    if ($null -eq $data) {
        $result = $null
    }
    else {
        $result = $data.ItemArray
    }
    return $result

}

# For each item in the array, replace the values of specified properties by a fixed value
function MaskProperties {
    param (
        # List of properties to be masked
        [Parameter(Mandatory)]
        [Array] $Properties,

        # list of items for which given properties are to be masked.
        [Parameter(Mandatory)]
        [Array] $Items
    )

    foreach ($item in $Items) {
        foreach ($property in $Properties) {
            # Only non-empty values are masked
            if ($item.$property) {
                $item.$property = "********"
            }
        }
    }
}

# returns the given connection string with password replaced by asterisks
function MaskPasswordInConnectionString {
    param (
        [Parameter()]
        [string] $ConnectionString
    )
    $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $ConnectionString
    # if the connection string contains a password, then replace it.
    if ($csb["Password"]) {
        $csb["Password"] = "********"
        return $csb.ConnectionString
    }
    else {
        # if it doesn't contain a password, return the original input.
        return $ConnectionString
    }
}

return Main
