
<#
.SYNOPSIS
  Reads input from console for serial number, and if the serial number is found marks the device is audited in Snipe-IT
  If there are zero, or more than one device found then the code errors

.DESCRIPTION

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
    Serial from Powershell Console
    
.OUTPUTS
    Device marked as Audited in Snipe-IT
  
.NOTES
  Version:        1.0
  Author:         Justin Simmonds
  Creation Date:  2022-08-19
  Purpose/Change: Initial script development
  
.EXAMPLE
  
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Import Modules
Import-Module "$PSScriptRoot/Config.ps1" -Force #Contains protected data (API Keys, URLs etc)

#----------------------------------------------------------[Declarations]----------------------------------------------------------
#Script Variables - Declared to stop it being generated multiple times per run
$snipeRetrieval = $false
$snipeResult = $null #Blank Snipe result

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Log ($logMessage)
{
    Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage"
}


#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

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
    Write-Host "Please Enter Serial Number" -ForegroundColor Green
    $deviceSerial = Read-Host

    if ([string]::IsNullOrWhiteSpace($deviceSerial))
    {
        Write-Host "No Serial Number entered, please enter serial number" -ForegroundColor Red
        Continue
    }
    elseif ($deviceSerial -ieq "Exit")
    {
        Write-Host "Exit Requested, exiting" -ForegroundColor Green
        exit
    }
    try 
    {
        $snipeResult = $null #Blank Snipe result
        $snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/byserial/$deviceSerial" -Method GET -Headers $snipeHeaders
        $deviceName = $null

        if ($null -ne $snipeResult)
        {
            #Covert from result to JSON content
            if ($snipeResult.total -eq 1)
            {

                Write-Log "Sucessfully retrieved device information for $deviceSerial from Snipe-IT"
               
                $snipeResult = $snipeResult.rows[0]
                
                $snipePost = $null
                $snipePost = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/audit" -Method POST -Headers $snipeHeaders -ContentType 'application/json' -Body ('{"asset_tag":"'+($snipeResult.asset_tag)+'"}')
                if ($snipePost.status -eq "success")
                {
                    Write-Log "Sucessfully recorded audit for device with $deviceSerial in Snipe-IT"
                }
                else 
                {
                    Write-Host "Audit for device with $deviceSerial in Snipe-IT failed with the error $($snipePost.messages)"  -ForegroundColor Magenta
                    [System.Media.SystemSounds]::Exclamation.Play()
                }
                
            }
            elseif (($snipeResult.total -eq 0) -or ([string]::IsNullOrWhiteSpace($snipeResult.total) -and ($snipeResult.status -eq "error" -and $snipeResult.messages -eq "Asset does not exist.")))
            {
                Write-Host "Device $deviceSerial does not exist in Snipe-IT, Ignoring"  -ForegroundColor Magenta
                [System.Media.SystemSounds]::Exclamation.Play()
            }
            else 
            {
                Write-Host "More than one device with $deviceSerial exists in Snipe-IT, Ignoring" -ForegroundColor Magenta
                [System.Media.SystemSounds]::Exclamation.Play()
            }
            
        }
        else 
        {
            Write-Host "Cannot retrieve device $deviceSerial from Snipe-IT due to unknown error"  -ForegroundColor Magenta
            [System.Media.SystemSounds]::Exclamation.Play()
        }
    }
    catch 
    {
        Write-Host $_.Exception
        exit
    }
}