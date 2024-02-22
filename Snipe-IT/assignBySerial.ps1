

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

.NOTES

Sends Location (ID) to SNIPE
Sends Status to SNIPE

  
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------


#----------------------------------------------------------[Declarations]----------------------------------------------------------
#Script Variables - Declared to stop it being generated multiple times per run
$currentLocation = $null
$fileLocationMap = "$PSScriptRoot/locations.csv"
$validLocations = $null
$auditOnSet = $true
$assetPrefix = "ICT-"
$discoURL = "http://disco:9292"  #default disco URL
$auditFile = "$PSScriptRoot/audit.csv"
$snipeStorageLabelID=20
$snipeDeployedLabelID=4
$requiredModules = @(
    [PSCustomObject]@{
        module = "SnipeitPS"
        version = ""},
    [PSCustomObject]@{
        module = "ActiveDirectory"
        version = ""}
)

#-----------------------------------------------------------[Modules]------------------------------------------------------------

Import-Module "$PSScriptRoot/Config.ps1" -Force #Contains protected data (API Keys, URLs etc)
Import-Module "$PSScriptRoot/DiscoICT.ps1" -Force

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Log 
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$logMessage, 
        [System.ConsoleColor]$ForegroundColor
    )

    if ($null -eq $ForegroundColor)
    {
        Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage"
    }
    else {
        Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage" -ForegroundColor $ForegroundColor
    }
    
}

function Add-Module ($m) {

    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $m}) {
        write-host "Module $m is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
            Import-Module $m # -Verbose
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                Install-Module -Name $m -Force -Verbose -Scope CurrentUser
                Import-Module $m # -Verbose
            }
            else {

                # If the module is not imported, not available and not in the online gallery then abort
                write-host "Module $m not imported, not available and not in an online gallery, exiting."
                EXIT 1
            }
        }
    }
}

function Set-CurrentLocation ($locationCode)
{
    if($validLocations.barcode -contains $locationCode)
    {
        return $validLocations | Where-Object barcode -eq $locationCode
    }
    else 
    {
        return $null
    }
}

function Get-returnCheck
{
    param(
        [Parameter(Mandatory=$true)][string]$check
    )
    
    $validRead = $false
    $tempRead = $null

    while ($validRead -eq $false)
    {
        if ($check -ine "Charger")
        {
            $readTemp = Read-Host "Is the $check returned and undamaged - Please type *(Y)es/(N)o/(D)amaged"
        }
        else
        {
            $readTemp = Read-Host "Is the $check returned and undamaged - Please type *(Y)es/(N)o/(D)amaged/(W)rong"
        }

        if ($("N","NO") -contains $readTemp.ToUpper())
        {
            $tempRead = "No"
            $validRead = $true
        }
        elseif ($("Y","YES") -contains $readTemp.ToUpper() -or [string]::IsNullOrWhiteSpace($readTemp))
        {
            $tempRead = "Yes"
            $validRead = $true
        }
        elseif ($("W","WRONG") -contains $readTemp.ToUpper())
        {
            Write-Host "Please enter serial number on charger"
            $chargerDetails = $null
            $chargerDetails = (Read-Host).Trim()
            $tempSnipe = $null
            $tempSnipe = Get-SnipeitAsset -serial $chargerDetails
            if ($null -ne $tempSnipe)
            {
                $tempRead = "Wrong|$($tempSnipe.serial)/$($tempSnipe.asset_tag) - $($tempSnipe.assigned_to.name) ($(($tempSnipe.assigned_to.username).Substring(0,7)))"
            }
            else 
            {
                $tempRead = "Wrong|$chargerDetails"
            }
            
            $validRead = $true

        }
        elseif ($("D","DAMAGED") -contains $readTemp.ToUpper())
        {
            Write-Host "Please enter a description of the damage"
            $damageDetails = $null
            $damageDetails = Read-Host
            $tempRead = "Damaged|$damageDetails"
            
            $validRead = $true

        }
        else 
        {
            Write-Log "Invalid input" -ForegroundColor Red
            $validRead = $false
        }
    }
    
    return $tempRead
}

function Get-userState
{

    param(
        [PSCustomObject]$snipeUser,
        [string]$discoUser
    )

    $returnCode = $null
    if ($null -eq $snipeUser)
    {
        Write-Log "Device not assigned in Snipe-IT" -ForegroundColor Magenta
        $returnCode += "|SnipeIT:Unassigned"
    }
    elseif ($snipeUser.type -eq "user")
    {
        Write-Log "Device Assigned in Snipe to $($snipeUser.type) $($snipeUser.Username)" -ForegroundColor Green
    }
    elseif ($snipeUser.type -eq "asset")
    {
        Write-Log "Asset is assigned to another Asset in Snipe please ensure you wish to continue" -ForegroundColor Magenta
        $returnCode += "|SnipeIT:Asset"
    }
    elseif ($snipeUser.type -eq "location")
    {
        Write-Log "Asset is assigned to another Asset in Snipe please ensure you wish to continue" -ForegroundColor Magenta
        $returnCode += "|SnipeIT:Location"
    }
    if ($discoUser -eq "Unassigned")
    {
        Write-Log "Device not assigned in Disco ICT" -ForegroundColor Magenta
        $returnCode += "|Disco:Unassigned"
    }
    else {
        Write-Log "Device assigned to $discoUser in Disco ICT" -ForegroundColor Green
    }
    if($null -eq $snipeUser -and $discoUser -eq "Unassigned")
    {
        return "Unassigned"
    }
    elseif ($discoUser -ne "Unassigned" -and $snipeUser.type -eq "user")
    {
        $tempAD = $null
        $tempAD = Get-ADUser -Filter "userPrincipalName -eq '$($snipeUser.username)'"

        if ($null -eq $tempAD)
        {
            Write-Log "Error retrieving user from AD, Continuing" -ForegroundColor -Red
            $returnCode += "|Snipe:ADError"

        }elseif ($tempAD.samAccountName -eq $discoUser)
        {
            return "Matched"
        }
        else {
            Write-Log "Users in Snipe ($($tempAD.samAccountName)) and Disco ($discoUser) do not match, please correct"
            return "Umatched"
        }
    }
    return $returnCode
}

function Get-snipeUser 
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$username,
        [Parameter(Mandatory=$true)][string]$snipeURL,
        [Parameter(Mandatory=$true)][hashtable]$snipeHeaders
    )
    
    try 
        {
            $snipeResult = $null #Blank Snipe result
                $snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/users?username=$([URI]::EscapeUriString($username))&deleted=false" -Method GET -Headers $snipeHeaders

            if ($null -ne $snipeResult)
            {
                #Covert from result to JSON content
                if ($snipeResult.total -eq 1)
                {

                    Write-Log "Sucessfully retrieved user information for $username from Snipe-IT" -ForegroundColor Green
                
                    return $snipeResult.rows[0]
                    
                }
                elseif (($snipeResult.total -eq 0) -or ([string]::IsNullOrWhiteSpace($snipeResult.total) -and ($snipeResult.status -eq "error" -and $snipeResult.messages -eq "User does not exist.")))
                {
                    
                    #TODO: Write Code here to do sync if possible, will need to loop entire section
                    Write-Log "User $username does not exist in Snipe-IT"  -ForegroundColor Magenta
                    return $null
                }
                else 
                {
                    Write-Log "More than one user with $username exists in Snipe-IT" -ForegroundColor Magenta
                    return $null
                }
                
            }
            else 
            {
                Write-Log "Cannot retrieve user $username from Snipe-IT due to unknown error"  -ForegroundColor Magenta
                return $null
            }
           
        }
        catch 
        {
            Write-Log $_.Exception
            return $null
        }

}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

$checkURL=$snipeURL.Substring((Select-String 'http[s]:\/\/' -Input $snipeURL).Matches[0].Length)

foreach ($module in $requiredModules)
{
    Add-Module -m $module.module
   <# if ($null -ne (Get-Module -ListAvailable -Name $module.module)) 
    {
        if ($module.version -eq )
        Write-Host "Module exists"
    } 
    else {
        Write-Host "Module does not exist"
    }#>
}

if ($checkURL.IndexOf('/') -eq -1)
{
    #Test ICMP connection
    if ((Test-Connection -TargetName $checkURL))
    {
        Write-Log "Successfully to Snipe-IT server at address $checkURL" -ForegroundColor Green
        Connect-SnipeitPS -url $snipeURL -apiKey $snipeAPIKey
    }
    else 
    {
        Write-Log "Cannot connect to Snipe-IT server at address $checkURL exiting" -ForegroundColor Red
        exit
    }
}

if (-not (Test-Path $fileLocationMap))
{
    Write-Log "Location Mapping file does not exist, please create it" -ForegroundColor Red
    exit
}
else 
{
    $validLocations = Import-CSV $fileLocationMap
    Write-Log "Locations Imported" -ForegroundColor Green
}


$exitRun = $false

while (-not $exitRun)
{
    Write-Log "Please Enter Serial Number or Asset Code" -ForegroundColor Yellow
    $readData = Read-Host
    $serialNumber, $snipeAsset, $snipeID, $snipeDevice = $null
    
    if ([string]::IsNullOrWhiteSpace($readData))
    {
        Write-Log "Blank input detected, ignoring" -ForegroundColor Red
        Continue
    }

    if (Set-CurrentLocation($readData) -neq $null)
    {
        $currentLocation = Set-CurrentLocation($readData)
        Write-Log "Location set to $($currentLocation.name)"
    }
    elseif ($readData -ieq "Exit")
    {
        Write-Log "Exit Requested, exiting" -ForegroundColor Green
        exit
    }
    else 
    {
        if (($readData.ToUpper()).StartsWith($assetPrefix))
        {
            Write-Log "Asset Code Detected $readData"
            $snipeDevice = Get-SnipeitAsset -asset_tag $readData
        }
        else 
        {
            Write-Log "Failed all other checks, assuming Serial number $readData"
            $snipeDevice = Get-SnipeitAsset -serial $readData
        }
        
        if ($null -ne $snipeDevice)
        {
            $snipeID = $snipeDevice.id
            $snipeAsset = $snipeDevice.asset_tag
            $serialNumber = $snipeDevice.serial
            $snipeAssignedUser = $null
            $snipeAssignedID = $null

            $assignStop = $false

            while ($assignStop -eq $false)
            {
                $assignData = $null

                Write-Log "Please Enter Serial Number or Asset Code for items to assign to this device" -ForegroundColor Yellow
                $assignData = Read-Host

                if ([string]::IsNullOrWhiteSpace($assignData))
                {
                    Write-Log "Blank input detected exiting" -ForegroundColor Red
                    $assignStop = $true
                    Continue
                }

                $assignDevice = $null
                if (($assignData.ToUpper()).StartsWith($assetPrefix))
                {
                    Write-Log "Asset Code Detected $assignData"
                    $assignDevice = Get-SnipeitAsset -asset_tag $assignData
                }
                else 
                {
                    Write-Log "Failed all other checks, assuming Serial number $assignData"
                    $assignDevice = Get-SnipeitAsset -serial $assignData
                }
                
            }

            
        }
        else {
            Write-Log "Error Retrieving Device, ignoring" -ForegroundColor Red
            Continue
        }



    }
}
