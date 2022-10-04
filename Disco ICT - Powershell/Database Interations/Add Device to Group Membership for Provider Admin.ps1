
#requires -version 2
<#
.SYNOPSIS
  Reads Disco Database for a specific job queue ID, retrieves all devices with that queue ID being open, adds those devices to a group for the service techs to be able to login with local administrator rights
  if no Queue ID or name is specified, it works based off the Job Types

.DESCRIPTION

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
    Data from Disco Database
    
.OUTPUTS
    Adding/Removing group memberships in AD
  
.NOTES
  Version:        1.0
  Author:         Justin Simmonds
  Creation Date:  2022-08-19
  Purpose/Change: Initial script development
  
.EXAMPLE
  
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = "SilentlyContinue"

#Dot Source required Function Libraries
. "$PSScriptRoot\Modules\Logging.ps1"

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#Script Variables - Declared to stop it being generated multiple times per run



#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Get-ServiceDevices
{

}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

Import-Module -Name SQLServer


    $sqlServerInstance = "<<SQLSERVER>>"
    $sqlServerUserId = "<<DA USERNAME>>"
    $sqlServerUserPassword = "<<PASSWORD>>"
    $searchCriteria = $null
    $dataset = $null

    if (-not $SerialNumber -and -not $AssetNumber -and -not $ComputerName -and -not $UserID)
    {
        throw "No Search Criteria Provided, Exiting"
    }

    if (-not [string]::IsNullOrEmpty($SerialNumber))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[SerialNumber] = '$SerialNumber'"
    }

    if (-not [string]::IsNullOrEmpty($AssetNumber))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[AssetNumber] = '$AssetNumber'"
    }

    if (-not [string]::IsNullOrEmpty($ComputerName))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[ComputerName] LIKE '%$ComputerName%'"
    }

    if (-not [string]::IsNullOrEmpty($UserID))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[AssignedUserId] LIKE '%$UserID%'"
    }
    $searchCriteria
    try
    {
        $connectionString = "Data Source=$sqlServerInstance;Integrated Security=SSPI;Initial Catalog=master; Database = Disco; User Id=$sqlServerUserId; Password=$sqlServerUserPassword;"
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
    }
    catch
    {
        throw "Could not connect to Database Server"
    }

    if($connection.State -eq "Open")
    {
        $sqlCommand = "SELECT [SerialNumber],[AssetNumber],[ComputerName],[AssignedUserId],[LastNetworkLogonDate] FROM [Disco].[dbo].[Devices]  WHERE $searchCriteria;"
        $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
        $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataSet) | Out-Null
    }
    
    $connection.Close()
    $dataSet.Tables | FT
