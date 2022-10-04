Param 
    (
        [Parameter(Mandatory=$true)][string]$caseID, 
        [string]$serialNumber, 
        [Parameter(Mandatory=$true)][string]$jobNotes,
        [Parameter(Mandatory=$true)][string]$jobTime,
        [switch]$jobCompleted
    )

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

$dbServer = "<<SQLSERVER>>"
$dbName = "Disco"
$dbUser = "<<SQLUSERNAME>>"
$dbUserPassword = "<<SQLUSERPW>>"


#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Log ($logToWrite)
{
    Write-Output $logToWrite >> "C:\PathToLogs\EmailtoJobLog.txt"
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

$jobWarranty = $true

try {
    Import-Module -Name SQLServer
    }
catch 
    {
        Write-Log "Error Importing SQL Module"
    }

try
    {
        $connectionString = "Data Source=$dbServer;Integrated Security=SSPI;Initial Catalog=master; Database = $dbName; User Id=$dbUser; Password=$dbUserPassword;"
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
    }
    catch
    {
        Write-Log "Could not connect to Database Server"
        return 0
    }

    if($connection.State -eq "Open")
    {
        Write-Log "Connection to Database Open"
        
        Write-Log "Working External Case ID: $caseID | Serial Number $serialNumber "

        $caseID = $caseID.Substring($caseID.Length -5)
        $jobTime = ([datetime]::ParseExact($jobTime, "d/MM/yyyy h:mm:ss tt", [cultureinfo]::InvariantCulture)).ToString('yyyy-MM-dd HH:mm:ss.fff')
        $jobNotes = $jobNotes.Replace("'","''")
        Write-Log $jobNotes
        $sqlCommand = "SELECT [JobID] FROM [Disco].[dbo].[JobMetaWarranties] WHERE [ExternalReference] LIKE '%$caseID%';"
        $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
        $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataSet) | Out-Null

        if($dataSet.Tables.JobID.Count -eq 1)
        {
            $jobID = $dataSet.Tables.JobID
        }
        elseif ($dataSet.Tables.JobID.Count -eq 0)
        {
            $sqlCommand = "SELECT [JobID] FROM [Disco].[dbo].[JobMetaNonWarranties] WHERE [RepairerReference] LIKE '%$caseID%';"
            $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
            $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
            $dataset = New-Object System.Data.DataSet
            $adapter.Fill($dataSet) | Out-Null
            if($dataSet.Tables.JobID.Count -eq 1)
            {
                $jobID = $dataSet.Tables.JobID
                $jobWarranty = $false
            }
            else 
            {
                Write-Log "Error Finding Job"
                return 0
            }
        }
        else 
        {
            Write-Log "Error Finding Job to update, multiple jobs with the same ID ($caseID)"
            return 0
        }
        Write-Log "Found Job ID $jobID"
        try
        {
            $sqlCommand = "INSERT INTO JobLogs (JobID,TechUserID,`"Timestamp`",Comments) VALUES ('$jobID', 'CURRIC\edunet', '$jobTime','$jobNotes'); ;"
            $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
            $command.ExecuteNonQuery() | Out-Null

            if ($jobCompleted)
            {
                if($jobWarranty)
                {
                    $sqlCommand = "SELECT * FROM [Disco].[dbo].[JobMetaWarranties] WHERE [JobID] = '$jobID';"
                    $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
                    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
                    $dataset = New-Object System.Data.DataSet
                    $adapter.Fill($dataSet) | Out-Null

                    if([string]::IsNullOrWhiteSpace($dataSet.Tables.ExternalCompletedDate) -or ([datetime]$dataSet.Tables.ExternalCompletedDate -gt [datetime]$jobTime))
                    {
                        $sqlCommand = "UPDATE JobMetaWarranties SET ExternalCompletedDate = '$jobTime' WHERE JobID = '$jobID';"
                        $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
                        $command.ExecuteNonQuery() | Out-Null
                        Write-Log "Marking Repairs Complete"
                    }
                }
                else 
                {
                    $sqlCommand = "SELECT * FROM [Disco].[dbo].[JobMetaNonWarranties] WHERE [JobID] = '$jobID';"
                    $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
                    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
                    $dataset = New-Object System.Data.DataSet
                    $adapter.Fill($dataSet) | Out-Null

                    if([string]::IsNullOrWhiteSpace($dataSet.Tables.RepairerCompletedDate) -or ([datetime]$dataSet.Tables.RepairerCompletedDate -gt [datetime]$jobTime))
                    {
                        $sqlCommand = "UPDATE JobMetaNonWarranties SET RepairerCompletedDate = '$jobTime' WHERE JobID = '$jobID';"
                        $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
                        $command.ExecuteNonQuery() | Out-Null
                        Write-Log "Marking Repairs Complete"
                    }
                }
            }
        }
        catch 
        {
            Write-Log "Error, Cannot insert to Database"
            return 0
        }
        return "1"

        
    }
    
    $connection.Close()
