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

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#Script Variables - Declared to stop it being generated multiple times per run



#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Log ($logMessage)
{
    Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage"
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

#Lookup Assignment in Snipe
    #If not assigned, do loop until X minutes or is assigned, check every Y minutes
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
