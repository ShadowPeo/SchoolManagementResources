#requires -version 2
<#
.SYNOPSIS
  Reads Snipe-IT for Device name (based on serial number of device), changes device name to match Snipe-IT

.DESCRIPTION

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
    Serial number of device (pulled from BIOS)
    Data from Snipe-IT
    
    
.OUTPUTS
    Device Name Change
  
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
Import-Module "$PSScriptRoot/DevEnv.ps1" -Force ##Temporary Variables used for development and troubleshooting

#----------------------------------------------------------[Declarations]----------------------------------------------------------

Write-Host $MyInvocation.InvocationName.Parameters

$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#Snipe Variables
$snipeAPIKey = "<<API_KEY>>"
$snipeURL = "<<SNIPE_URI>>" #No trailing /

#Length of time between retries
$retryPeriod = 60

#Snipe-IT Details
$snipeRetrivalMaxAttempts = 10 #It will attempt to retrieve the record every 60 seconds, so this is equivilent to minutes

#Generated Name Variables
$generateSource = "Serial" #Serial (default) for Serial number or UUID for UUID
$generateFrom = "Right" #Which way to trim the identifier from (Start position) the Left or the Right (default) to ensure it does not go over the 15 char max - Reccomend to use Left if using UUID as Right is often a bunch of 0's

#Script Variables - Declared to stop it being generated multiple times per run
$snipeRetrieval = $false
$snipeResult = $null #Blank Snipe result

#-----------------------------------------------------------[Functions]------------------------------------------------------------

#Write Messages to Log
function Write-Log ($logMessage)
{
    Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage"
}

#Get The Device Type Information
Function Get-Chassis
{
  $chassisType = $null
  $baseClass = $null
  $hasBattery = if(Get-WmiObject -Class win32_battery)  {$true} else {$false}

  switch ((Get-WmiObject -Class win32_systemenclosure).chassistypes)
  {
      1 
      { 
        $chassisType = "Other" 
        $baseClass = "Other"
      }
      2 
      { 
        $chassisType = "Unknown" 
        $baseClass = "Unknown"
      }
      3 
      { 
        $chassisType = "Desktop" 
        $baseClass = "Desktop"
      }
      4 
      { 
        $chassisType = "Low Profile Desktop" 
        $baseClass = "Desktop"
      }
      5 
      { 
        $chassisType = "Pizza Box" 
        $baseClass = "Desktop"
      }
      6 
      { 
        $chassisType = "Mini-Tower" 
        $baseClass = "Desktop;Server"
      }
      7 
      { 
        $chassisType = "Tower" 
        $baseClass = "Desktop;Server"
      }
      8 
      { 
        $chassisType = "Portable" 
        $baseClass = "Desktop"
      }
      9 
      { 
        $chassisType = "Laptop" 
        $baseClass = "Laptop"
      }
      10 
      { 
        $chassisType = "Notebook" 
        $baseClass = "Laptop"
      }
      11 
      { 
        $chassisType = "Hand Held" 
        $baseClass = "Handheld"
      }
      12 
      { 
        $chassisType = "Docking Station" 
        $baseClass = "Docking Station"
      }
      13 
      { 
        $chassisType = "All-In-One" 
        $baseClass = "Desktop"
      }
      14 
      { 
        $chassisType = "Sub Notebook" 
        $baseClass = "Laptop"
      }
      15 
      { 
        $chassisType = "Space Saving" 
        $baseClass = "Desktop"
      }
      16 
      { 
        $chassisType = "Lunch Box" 
        $baseClass = "Desktop"
      }
      17 
      { 
        $chassisType = "Main System Chassis" 
        $baseClass = "Server"
      }
      18 
      { 
        $chassisType = "Expansion Chassis" 
        $baseClass = "Server"
      }
      19 
      { 
        $chassisType = "Sub Chassis" 
        $baseClass = "Server"
      }
      20
      { 
        $chassisType = "Bus Expansion Chassis" 
        $baseClass = "Server"
      }
      21 
      { 
        $chassisType = "Peripheral Chassis" 
        $baseClass = "Server"
      }
      22 
      { 
        $chassisType = "Storage Chassis" 
        $baseClass = "Server"
      }
      23 
      { 
        $chassisType = "Rack Mount Chassis" 
        $baseClass = "Server"
      }
      24 
      { 
        $chassisType = "Sealed-Case PC" 
        $baseClass = "Desktop;IoT"
      }
      30 
      { 
        $chassisType = "Tablet" 
        $baseClass = "Tablet"
      }
      31 
      { 
        $chassisType = "Convertible" 
        $baseClass = "Laptop;Tablet"
      }
      32 
      { 
        $chassisType = "Detachable" 
        $baseClass = "Tablet"
      }
      33 
      { 
        $chassisType = "IoT Gateway" 
        $baseClass = "IoT"
      }
      34 
      { 
        $chassisType = "Embedded PC" 
        $baseClass = "Desktop"
      }
      35 
      { 
        $chassisType = "Mini PC" 
        $baseClass = "Desktop"
      }
      36 
      { 
        $chassisType = "Stick PC" 
        $baseClass = "Desktop;IoT"
      }
      default 
      {
        $chassisType = "Unknown" 
        $baseClass = "Unknown"
      }
  }

  return @{chassisType=$chassisType;baseClass=$baseClass;hasBattery=$hasBattery}
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

    #Get Serial Number from BIOS
    $deviceSerial = (Get-CIMInstance Win32_BIOS).SerialNumber

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
        ##DEBUG
        $whileCounter = 100
        if ($whileCounter -ge $snipeRetrivalMaxAttempts)
        {
            $generatedName = $null
            switch -wildcard ((Get-Chassis).baseClass)
            {
                "*Desktop*" {$generatedName = "DT-";break}
                "*Laptop*" {$generatedName = "LT-";break}
                "*Tablet*" {$generatedName = "TAB-";break}
                "*Server*" {$generatedName = "SRV-";break}
                "IoT" {$generatedName = "IOT-";break}
                default {$generatedName = "UNK-"}

            }

            $genTemp = $null

            if ($generateSource -eq "UUID")
            {
                $genTemp = (Get-WmiObject -Class Win32_ComputerSystemProduct).UUID -replace '[^a-zA-Z0-9]', ""
            }
            else 
            {
                $genTemp = $deviceSerial -replace '[^a-zA-Z-0-9]', ""
            }

            $genMax = 15 - ($generatedName.Length)

            if ($genTemp.Length -le $genMax)
            {
                $generatedName += $genTemp
            }
            else
            {
                if ($generateFrom -eq "Left")
                {
                    $generatedName += $genTemp.Substring(0,$genMax)
                }
                else 
                {
                    $generatedName += $genTemp.Substring(($genTemp.Length - $genMax),$genMax)
                }
            }

            Write-Log "Cannot complete lookup at this point for $deviceSerial from Snipe-IT, Ending Automated Run"
            Write-Host "
*************************************************************** 
Cannot Find Valid Device Name in Snipe-IT 
This Could be due to no device in Snipe with the serial number
of $deviceSerial or a blank name field.

Please Select from the following options on how to proceed
[1] Retry to get information from Snipe-IT (default) - will Restart from the start
[2] Enter the desired name (This will update Snipe-IT)
[3] Use the generated name ($generatedName) (This DOES NOT update Snipe-IT)

Please Enter Selection or hit enter to use default option:
***************************************************************" -ForegroundColor Magenta

            $validInput = $false
            while ($validInput -eq $false)
            {
                $input = Read-Host
                
                if ([string]::IsNullOrWhiteSpace($input))
                {
                    $input = 1
                }

                switch ($input)
                {
                    1
                    {
                        $validInput = $true
                        $whileCounter=0
                        Write-Log "Reattempting Snipe-IT Retrieval"
                        break
                    }
                    
                    2   
                    {
                        $validInput = $true
                        Write-Host "Please Input Desired Name. `n --- Note: This will be sent to Snipe-IT and become the devices name in future unless changed" -ForegroundColor Green
                        $validName = $false
                        while($validName -eq $false)
                        {
                            $getName = Read-Host
                            if ($getName.Length -le 15)
                            {
                                if($getName -notmatch '[^a-zA-Z-_0-9]')
                                {
                                    $validName = $true
                                    #Submit to Snipe-IT
                                    #Rename Device
                                    Exit
                                }
                                else 
                                {
                                    Write-Host "Name contains invalid characters, Try Again" -ForegroundColor Red
                                }
                            }
                            else 
                            {
                                Write-Host "Name is To Long, Try Again" -ForegroundColor Red
                            }
                        }

                    }
                    
                    3   
                    {
                        $validInput = $true
                        Write-Host "Renaming the device to $genName. `n --- Note: This will not be sent to Snipe-IT" -ForegroundColor Green
                        #Rename Device
                        Exit
                    }
                    default
                    {
                        Write-Host "Invalid Input, Please Try Again" -ForegroundColor Red
                    }
                }

            }
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
                    if ($whileCounter -lt 1)
                    {
                        Write-Log "Sucessfully retrieved device information for $deviceSerial from Snipe-IT"
                    }
                    
                    $snipeResult = $snipeResult.rows[0]
                    
                    if (-not [string]::IsNullOrWhiteSpace($snipeResult.name))
                    {
                        if (($snipeResult.name).Length -le 15)
                        {
                            $deviceName = $snipeResult.name
                            Write-Log "Device name found in Snipe-IT, setting Devicename to $deviceName"
                        }
                        else
                        {
                            $deviceName = ($snipeResult.name).Substring(0,15)
                            Write-Log "Device name found in Snipe-IT is too long, setting Devicename to $deviceName"
                        }
                        exit
                    }
                    else 
                    {
                        Write-Log "Device name not found in Snipe-IT, field is blank"
                    }

                    
                }
                elseif (($snipeResult.total -eq 0) -or ([string]::IsNullOrWhiteSpace($snipeResult.total) -and ($snipeResult.status -eq "error" -and $snipeResult.messages -eq "Asset does not exist.")))
                {
                    Write-Log "Device $deviceSerial does not exist in Snipe-IT, Waiting"
                    Start-Sleep -Seconds $retryPeriod
                    $whileCounter++
                }
                else 
                {
                    Write-Log "More than one device with $deviceSerial exists in Snipe-IT, Exiting"
                    Pause
                    exit
                }
                
            }
            else 
            {
                Write-Log "Cannot retrieve device $deviceSerial from Snipe-IT due to unknown error"
                $whileCounter = 9999
                exit
            }
        }
        catch 
        {
            Write-Log $_.Exception
            exit
        }
    }
