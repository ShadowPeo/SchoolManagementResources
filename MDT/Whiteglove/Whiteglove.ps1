param 
    (
        #School Details
        [string]$mode = "", #Used to define where in the process the script is starting from
        [int]$restarts = 0 #Used to define where in the process the script is starting from
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

Write-Host $MyInvocation.InvocationName.Parameters

$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#Length of time between retries
$retryPeriod = 6

#Snipe-IT Details
$snipeRetrivalMaxAttempts = 10 #It will attempt to retrieve the record every 60 seconds, so this is equivilent to minutes

#Confirmation Details
$confirmationMaxAttempts = 30


#Script Variables - Declared to stop it being generated multiple times per run
$snipeRetrieval = $false
$snipeResult = $null #Blank Snipe result

#Whiteglove Success Criteria
$successAppType = "APPX"
$successApp = "CompanyPortal"
$successFile = $null

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

function Set-RegistryKey 
{
    param (
        [Parameter(Mandatory=$true)][string]$registryPath,
        [Parameter(Mandatory=$true)][string]$name,
        [Parameter(Mandatory=$true)][string]$value,
        [Parameter(Mandatory=$true)][string]$type
    )

    if(!(Test-Path $registryPath))
    {
        New-Item -Path $registryPath -Force | Out-Null
    }
    New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType $type -Force | Out-Null

}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

#Ensure script is running from C:\Scripts

if($PSScriptRoot -ne "C:\Scripts\WhiteGlove")
{
    if (!(Test-Path -Path "C:\Scripts" -PathType Container))
    {
        New-Item -Path "C:\Scripts\" -ItemType Directory
    }

    Copy-Item -Path $PSScriptRoot -Destination 'C:\Scripts' -Recurse -Force

    #T#Start-Process "powershell.exe" -ArgumentList "-NoExit -ExecutionPolicy Bypass -File C:\Scripts\WhiteGlove\$($MyInvocation.MyCommand.Name) -Mode $mode" -PassThru
    #T#exit
}

#Check to see if this is a MDT Run
if (-not [string]::IsNullOrWhiteSpace($TSEnv:TASKSEQUENCEID))
{
    $script:taskSequence = $true
}

#Check location of script is C:\ProgramData\Whiteglove as PSScriptRoot, if not then copy to that location, and restart the script with provided flags from this run

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

    $userTitle = Invoke-RestMethod $psuURI/user/get/title/$($snipeResult.assigned_to.username)
    
    if ($null -ne $userTitle -and ($userTitle -eq "Student" -or $userTitle -eq "Future Student"))
    {
        Write-Log "User is a $userTitle, Continuing"
        #T#$workingPassword = Invoke-RestMethod $psuURI/user/reset/stupass/$($snipeResult.assigned_to.username)
        #T#Set-RegistryKey -registryPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultUserName" -Value ((Invoke-RestMethod $psuURI/user/get/username/$($snipeResult.assigned_to.username)).samaccountname) -type "String"
        #T#Set-RegistryKey -registryPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultPassword" -Value $workingPassword -type "String"
        #T#Set-RegistryKey -registryPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultDomainName" -Value "CURRIC" -type "String"
        #T#Set-RegistryKey -registryPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "AutoLogonCount" -Value 0 -type "String"
        #T#Set-RegistryKey -registryPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "AutoAdminLogon" -Value 1 -type "String"

        #Set the script to run on login with the -StageTwo flag
        $taskAction = New-ScheduledTaskAction `
            -Execute 'powershell.exe' `
            -Argument '-ExecutionPolicy Bypass -File C:\Scripts\WhiteGlove\Whiteglove.ps1 -mode=StageTwo' `
            -WorkingDirectory 'C:\Scripts'


        $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User "CURRIC\($snipeResult.assigned_to.username)).samaccountname)"

        # Register the scheduled task
        Register-ScheduledTask `
            -TaskName 'WhiteGlove' `
            -Action $taskAction `
            -Trigger $taskTrigger

        
        if ($script:taskSequence -ne $true)
        {
            #T#Restart-Computer
        }

    }
    else #if ($null -eq $userTitle)
    {
        Write-Log "Unable to find a valid user or title for $($snipeResult.assigned_to.name)"
        #TODO Wait for Title
    }
}

$appCheckSuccess = $null
if ($mode = "StageTwo")# -or $StageTwo)
{
    
    #T#Remove-Item "$PSScriptRoot\Config.ps1" -Force
    
    
    #Check if the logged in user matches the assigned user
    
    $checkTimes = 0
    while($appCheckSuccess -ne $true)
    {
        if ($successAppType -eq "APPX" -and $null -ne $successApp)
        {
            Write-Log "Running APPX Check"
            Import-Module -Name Appx | Out-Null
            if ($null -ne (Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName | Where-Object Name -match $successApp))
            {
                $appCheckSuccess = $true
                Write-Log "Whiteglove Success, cleaning up script"
            }
        }
        elseif ($successAppType -eq "APPX" -and $null -eq $successApp)
        {
            Write-Log "Success Type is set to file, but there is no file set, Pausng"
            Write-Host "Success Type is set to file, but there is no file set, Pausng"
            Pause
        }

        if ($successAppType -eq "FILE" -and $null -ne $successFile)
        {
            Write-Log "Running File Check"
            if (Test-Path -Path $successFile)
            {
                $appCheckSuccess = $true
                Write-Log "Whiteglove Success, cleaning up script"
            }
        }
        elseif ($successAppType -eq "FILE" -and $null -eq $successFile)
        {
            Write-Log "Success Type is set to file, but there is no file set, Pausng"
            Write-Host "Success Type is set to file, but there is no file set, Pausng"
            Pause
        }
        $appCheckSuccess = $false

        if($appCheckSuccess)
        {

            #Remote Scheduled Task
            Write-Log "Unregister Scheduled Task"
            Unregister-ScheduledTask -TaskName "WhiteGlove" -Confirm:$false

            #Remove Registry Keys
            Write-Log "Removing Registry Keys"
            #T#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultUserName"
            #T#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultPassword"
            #T#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "DefaultDomainName"
            #T#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "AutoLogonCount"
            #T#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -name "AutoAdminLogon"

            #Remove All Scripts from the directory
            WRite-Log "Self Destructing Script"
            #t#Remove-Item -Path $PSScriptRoot -Recurse -Force

            #Shutdown PC
            Write-Log "Shutting Down PC"
            #T#Stop-Computer -Confirm:$false

        }
        else
        {
            Write-Log "App not located waiting $retryPeriod seconds"
            Start-Sleep -Second $retryPeriod
            
            $checkTimes++
            
            if ($checkTimes -gt $confirmationMaxAttempts)
            {
                Restart-Computer -Confirm:$false
            }
        }

    }
    
}

#^Lookup Assignment in Snipe
    #*If not assigned, do loop until X iterations (minutes) are complete or is assigned, check every Y minutes - Loop Done, Exit/Remdiation not done
        #If X is hit then put script into first logon (or perhaps startup) to run again
            #If this first startup and X expires then ask for username to assign (needs to accept both SAM account name and UPN) or type shared to setup as a shared device (deletes script from login)
                #Assign Device in Snipe after ensuring it exists in AD, may need to force a sync
#^Lookup User in AD, Ensure exists (should if they are in Snipe), need to lookup based upon UPN as that is the Snipe Username, allow for using SAMAccountName as well though)
    #^Ensure User is Student (or Future Student) DONE
    #^Reset Password to known password (Dinopass) DONE

#Add Script to firstlogin/startup to continue from here

#Loop   
    #Check for something that can determain if Intune login completed - APPX Done, Executible and file not done
    #^If Exists, remove registry keys, scheduled task and shutdown exiting loop
        #^Else Sleep X, and wait for loop to run again
            #^If Loop as run for more than X minutes then restart

            