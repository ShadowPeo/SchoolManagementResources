param 
    (
        #School Details
        [string]$mode = "FirstRun" #Used to define where in the process the script is starting from
    )

#requires -version 2
<#
.SYNOPSIS
  Reads Snipe-IT for assigned user, and sets up the laptop for that user if they are a current or future student (resets password) by ensuring that InTune is syncing

.DESCRIPTION

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
    Serial number of device (pulled from BIOS)
    Data from Snipe-IT
    Data from Active Directory
    
.OUTPUTS
    Laptop sync to Intune if assigned, if not script to do it on first login
  
.NOTES
  Version:        1.0
  Author:         Justin Simmonds
  Creation Date:  2022-10-05
  Purpose/Change: Initial script development
  
.EXAMPLE
  
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = "SilentlyContinue"

#Dot Source required Function Libraries

#Modules
Import-Module "$PSScriptRoot/Config.ps1" -Force #Contains protected data (API Keys, URLs etc)
Import-Module "$PSScriptRoot/DevEnv.ps1" -Force ##Temporary Variables used for development and troubleshooting

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#Length of time between retries
$retryPeriod = 6

#Snipe-IT Details
$snipeRetrivalMaxAttempts = 10 #It will attempt to retrieve the record every 60 seconds, so this is equivilent to minutes

#Active Directory Details
$adRetrivalMaxAttempts = 10 #It will attempt to retrieve the record every 60 seconds, so this is equivilent to minutes

#Script Variables - Declared to stop it being generated multiple times per run
$snipeRetrieval = $false
$snipeResult = $null #Blank Snipe result
$adRetrieval = $false
$adUser = $null

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Log ($logMessage)
{
    Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage"
}

function Set-Startup ($mode)
{
    #Copy script to C:\Scripts (Create directory if it does not exist)
    #Add Script to Scheduled task (removing old one if it exists) with the correct mode flag set
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

#Do this segment only if the script has not set paramters up
if ($mode -eq "FirstRun" -or $mode -eq "SubRun")
{
    #Get Serial Number from BIOS
    #T#$deviceSerial = (Get-CIMInstance Win32_BIOS).SerialNumber

    $checkURL=$snipeURL.Substring((Select-String 'http[s]:\/\/' -Input $snipeURL).Matches[0].Length)

    if ($checkURL.IndexOf('/') -eq -1)
    {
        #Test ICMP connection
        if ((Test-Connection -TargetName $checkURL))
        {
            Write-Log "Successfully to Snipe-IT server at address $checkURL"
        }
        else 
        {
            Write-Log "Cannot connect to Snipe-IT server at address $checkURL exiting"
            exit
        }
    }

    #Create Snipe Headers
    $snipeHeaders=@{}
    $snipeHeaders.Add("accept", "application/json")
    $snipeHeaders.Add("Authorization", "Bearer $snipeAPIKey")

    $whileCounter = 0 #Counter to ensure that the task does not repeat too many times, as defined by the variable above

    while (-not $snipeRetrieval)
    {
        if ($whileCounter -ge $snipeRetrivalMaxAttempts)
        {
            Write-Log "Cannot complete lookup at this point for $deviceSerial from Snipe-IT, Ending Automated Run"
            Exit ##TEMP UNTIL EXIT CODE DONE
        }

        try 
        {
            $snipeResult = $null #Blank Snipe result
            $snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/byserial/$deviceSerial" -Method GET -Headers $snipeHeaders

            if ($null -ne $snipeResult)
            {
                #Covert from result to JSON content
                if ($snipeResult.total -eq 1)
                {
                    if ($whileCounter -lt 1)
                    {
                        Write-Log "Sucessfully retrieved device information for $deviceSerial from Snipe-IT"
                    }
                    
                    $snipeResult = $snipeResult.rows[0]
                    
                    if ($snipeResult.assigned_to.type -eq "user")
                    {
                        Write-Log "Device $deviceSerial is Assigned to $($snipeResult.assigned_to.name) ($($snipeResult.assigned_to.username))"
                        $snipeRetrieval = $true
                    }
                    else 
                    {
                        Write-Log "Device $deviceSerial is not assigned to a User, Waiting"
                        Start-Sleep -Seconds $retryPeriod
                        $whileCounter++
                    }
                    
                }
                elseif ($snipeResult.total -eq 0)
                {
                    Write-Log "Device $deviceSerial does not exist in Snipe-IT, Waiting"
                    Start-Sleep -Seconds $retryPeriod
                    $whileCounter++
                }
                else 
                {
                    Write-Log "More than one device with $deviceSerial exists in Snipe-IT, Exiting"
                    exit
                }
                
            }
            else 
            {
                Write-Log "Cannot retrieve device $deviceSerial from Snipe-IT due to unknown error, exiting"
                exit
            }
        }
        catch 
        {
            Write-Log $_.Exception
            exit
        }
    }

<#
    $whileCounter = 0 #Counter to ensure that the task does not repeat too many times, as defined by the variable above

    while (!$adRetrieval)
    {
        $userID = $snipeResult.assigned_to.username
        
        if ($whileCounter -ge $adRetrivalMaxAttempts)
        {
            Write-Log "Cannot complete AD lookup at this point for $userID, Ending Automated Run"
            Exit
        }

        try 
        {

            if ($snipeResult.StatusCode -eq 200)
            {
                #Covert from result to JSON content
                $snipeResult = ConvertFrom-JSON($snipeResult.Content)

                if ($snipeResult.total -eq 1)
                {
                    if ($whileCounter -lt 1)
                    {
                        Write-Log "Sucessfully retrieved device information for $deviceSerial from Snipe-IT"
                    }
                    
                    $snipeResult = $snipeResult.rows[0]
                    
                    if ($snipeResult.assigned_to.type -eq "user")
                    {
                        Write-Log "Device $deviceSerial is Assigned to $($snipeResult.assigned_to.name) ($($snipeResult.assigned_to.username))"
                        $adRetrieval = $true
                    }
                    else 
                    {
                        Write-Log "Device $deviceSerial is not assigned to a User, Waiting"
                        Start-Sleep -Seconds $retryPeriod
                        $whileCounter++
                    }
                    
                }
                elseif ($snipeResult.total -eq 0)
                {
                    Write-Log "Device $deviceSerial does not exist in Snipe-IT, Waiting"
                    Start-Sleep -Seconds $retryPeriod
                    $whileCounter++
                }
                else 
                {
                    Write-Log "More than one device with $deviceSerial exists in Snipe-IT, Exiting"
                    exit
                }
                
            }
            else 
            {
                Write-Log "Cannot retrieve user $deviceSerial from ActiveDirectory due to unknown error, exiting"
                exit
            }
        }
        catch 
        {
            Write-Log $_.Exception
            exit
        }
    }
#>
}


#Lookup Assignment in Snipe - DONE
    #If not assigned, do loop until X iterations (minutes) are complete or is assigned, check every Y minutes - Loop Done, Exit/Remdiation not done
        #If X is hit then put script into first logon (or perhaps startup) to run again
            #If this first startup and X expires then ask for username to assign (needs to accept both SAM account name and UPN) or type shared to setup as a shared device (deletes script from login)
                #Assign Device in Snipe after ensuring it exists in AD, may need to force a sync
#Lookup User in AD, Ensure exists (should if they are in Snipe), need to lookup based upon UPN as that is the Snipe Username, allow for using SAMAccountName as well though)
    #Ensure User is Student (or Future Student)
    #Reset Password to known password (Dinopass)

#Add Registry Keys for auto-login
#HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon AutoAdminLogon REG_SZ 1 
#HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon AutoLogonCount
#HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon - DefaultDomainName REG_SZ  CURRIC 
#HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon - DefaultPassword  REG_SZ  <<PASSWORD>>
#HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon - DefaultUserName  REG_SZ  <<USERNAME (SAM ACCOUNT NAME)>>

#Add Script to firstlogin/startup to continue from here

#Loop   
    #Check for something that can determain if Intune login completed
    #If Exists, remove registry keys, scheduled task and shutdown exiting loop
        #Else Sleep X, and wait for loop to run again
            #If Loop as run for more than X minutes then restart