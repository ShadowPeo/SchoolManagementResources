
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

Import-Module "$PSScriptRoot\Config.ps1" -Force #Contains protected data (API Keys, URLs etc)
Import-Module "$PSScriptRoot\DiscoICT.ps1" -Force

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Write-Host "$PSScriptRoot\Config.ps1"

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

function Exit-Program
{
    if ($csvOutput.Count -ge 1)
    {
        $csvOutput | Export-Csv -Path $csvFile -Encoding ascii -Append
    }
    exit
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
$csvOutput = @()
$csvFile = "$PSScriptRoot/audit-output.csv"
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
    if ((Test-Connection $checkURL))
    {
        Write-Log "Successfully to Snipe-IT server at address $checkURL" -ForegroundColor Green
        Connect-SnipeitPS -url $snipeURL -apiKey $snipeAPIKey
    }
    else 
    {
        Write-Log "Cannot connect to Snipe-IT server at address $checkURL exiting" -ForegroundColor Red
        Exit-Program
    }
}

if (-not (Test-Path $fileLocationMap))
{
    Write-Log "Location Mapping file does not exist, please create it" -ForegroundColor Red
    Exit-Program
}
else 
{
    $validLocations = Import-CSV $fileLocationMap
    Write-Log "Locations Imported" -ForegroundColor Green
}

while ([string]::IsNullOrWhiteSpace($currentLocation))
{
    Write-Log "Please Enter Location" -ForegroundColor Yellow
    $readData = $null
    $readData = Read-Host
    
    if ($readData -inotlike "DEPLOY*" -and $readData -ine "EXIT" -and $readData -ine "CHECKIN"  -and !([string]::IsNullOrWhiteSpace($readData)))
    {
        $currentLocation = Set-CurrentLocation($readData)
        if ($null -ne $currentLocation)
        {
            Write-Log "Location set to $($currentLocation.name)" -ForegroundColor Green
        }
        else 
        {
            Write-Log "Invalid location, please try again or update location file" -ForegroundColor Red
        }
    }
    elseif ($readData -ilike "DEPLOY*")
    {
        $currentLocation = "DEPLOYMENT"
        Write-Log "Deployment Mode Active" -ForegroundColor Green
    }
    elseif ($readData -ieq "Exit")
    {
        Write-Log "Exit Requested, exiting" -ForegroundColor Green
        Exit-Program
    }
    elseif ($readData -ieq "Checkin")
    {
        $currentLocation = "CHECKIN"
        Write-Log "Checkin Mode Active" -ForegroundColor Green
    }
    else {
        Write-Log "Unhandled Error" -ForegroundColor Red
    }
}

$exitRun = $false

while (-not $exitRun)
{
    Write-Log "Please Enter Serial Number, Asset Code or Location Code." -ForegroundColor Yellow
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
    elseif($readData -ilike "DEPLOY*")
    {
        $currentLocation = "DEPLOYMENT"
        Write-Log "Deployment Mode Active" -ForegroundColor Green
    }
    elseif ($readData -ieq "Exit")
    {
        Write-Log "Exit Requested, exiting" -ForegroundColor Green
        Exit-Program
    }
    elseif ($readData -ieq "Checkin")
    {
        $currentLocation = "CHECKIN"
        Write-Log "Checkin Mode Active" -ForegroundColor Green
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
            if ($snipeDevice.assigned_to -ne $null)
            {
                $snipeAssignedUser = $snipeDevice.assigned_to.name
                $snipeAssignedID = ($snipeDevice.assigned_to.username).Substring(0,7)
            }

            $snipeDevice = $null

            if ($currentLocation -eq "DEPLOYMENT")
            {
                $userState = $null
                $userState = Get-userState -snipeUser (Get-snipeAssignedUser -deviceID $snipeAsset -snipeURL $snipeURL -snipeHeaders $snipeHeaders) -discoUser (Get-discoDeviceAssignedUser -discoURL $discoURL -deviceID $serialNumber)
                if ($userState -ne "Matched")
                {
                    if($userState -eq "Unassigned")
                    {
                        Write-Log "Device $snipeAsset|$serialNumber is unassigned, please type User ID (samAccountName or UPN) to assign it or type cancel" -ForegroundColor Yellow
                        $assignSuccess = $null
                        while($null -eq $assignSuccess)
                        {
                            $readData = Read-Host
                            if ($readData -ieq "CANCEL")
                            {
                                Write-Log "Assigning of device canceled" -ForegroundColor Green
                                $assignSuccess = "Cancel"
                            }
                            
                            $tempAD = $null
                            
                            if ($readData -like "*@*")
                            {
                                Write-Log "Assigning to user based on UPN $readData" -ForegroundColor Green
                                $tempAD = Get-ADUser -Filter "userPrincipalName -eq '$readData'"
                            }
                            else 
                            {
                                Write-Log "Assigning to user based on samAccountName $readData" -ForegroundColor Green
                                $tempAD = Get-ADUser -identity $readData
                            }

                            if ($null -ne $tempAD)
                            {

                            }
                            else 
                            {
                                Write-Log "User not found in AD, please enter a valid user or type cancel to not assign the asset" -ForegroundColor Red
                                $assignSuccess = "Cancel"
                            }

                            <#TODO
                            Validate AD User
                                If Valid Validate Snipe User, else Snipe cannot be valid
                                    If not Valid but in Disco offer to do AD sync (is this possible)
                            If Both Valid
                                Assign in Disco (as it reads AD)
                                Assign in Snipe, Checkin if required
                            MOVE ENTIRE TO FUNCTION TO SHARE WITH UNMATCHED
                            #>
                        }
                        if ($assignSuccess -eq "Cancel")
                        {
                            continue
                        }
                    }

                }

                #$snipeLocationResult = Set-SnipeitAsset -id $snipeID -customfields @{ 'location_id' = $($currentLocation.snipeid) }  ##Set Location to blank (or deployed if cannot set blank)
                #$snipeStatusResult = Set-SnipeitAsset -id $snipeID -status_id $snipeStorageLabelID   ##Set this as to in storage or deployed
                #Set-discoLocation -deviceID $serialNumber -deviceLocation "Deployed - $(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S')" -discoURL $discoURL    
                
            }
            elseif ($currentLocation -eq "CHECKIN") 
            {

                
                $tempData = [PSCustomObject]@{
                    Date = Get-Date -format 'yyyy-MM-dd' 
                    Time = Get-Date -format 'HH:mm:ss'
                    'Asset Tag' = $snipeAsset
                    'Serial Number' = $serialNumber
                    'Assigned User Name' = $snipeAssignedUser
                    'Assigned User ID' = $snipeAssignedID
                    'Checkin User' = $env:USERNAME
                    Bag = Get-returnCheck -check "Bag"
                    Charger = Get-returnCheck -check "Charger"
                    Eduskin = Get-returnCheck -check "Eduskin"
                    Stylus = Get-returnCheck -check "Stylus"
                    'Charger Serial' = $null
                    'Charger Asset' = $null
                    'Charger User' = $null
                    Laptop = Get-returnCheck -check "Laptop"
                    Keyboard = Get-returnCheck -check "Keyboard"
                    Screen = Get-returnCheck -check "Screen"
                    Notes = ""
                }
                
                foreach ($header in ($tempData | get-member -type properties | % name))
                {
                    if ($tempData.$header -like "*|*" -and $header -ine "Notes" -and $header -ine "Charger")
                    {
                        $tempData.Notes += "$header - $($tempData.$header.Split('|')[1])|"
                        $tempData.$header = $tempData.$header.Split('|')[0]
                    }

                }

                if ($tempData.Charger -like "Wrong*")
                {
                    $tempData.'Charger Serial' = $tempData.Charger.Split('|')[1]
                    $tempData.Charger = "Wrong"
                    $tempData.'Charger Asset' = $tempData.'Charger Serial'.Split('/')[1]
                    $tempData.'Charger Serial' = $tempData.'Charger Serial'.Split('/')[0]
                    $tempData.'Charger User' = $tempData.'Charger Asset'.Split(' - ')[1]
                    $tempData.'Charger Asset' = $tempData.'Charger Asset'.Split(' - ')[0]
                }

                $tempData | Export-Csv -Path $auditFile -Append -NoTypeInformation

                Write-Log "Checkin Complete, Next Asset Please" -ForegroundColor Green
            }
            else 
            {
                $snipeLocationResult = Set-SnipeitAsset -id $snipeID -customfields @{ 'location_id' = $($currentLocation.snipeid) }  ##Set Location to blank (or deployed if cannot set blank)
                $snipeStatusResult = Set-SnipeitAsset -id $snipeID -status_id $snipeStorageLabelID   ##Set this as to in storage or deployed
                Set-discoLocation -deviceID $serialNumber -deviceLocation $currentLocation.name -discoURL $discoURL
                $tempData = $null
                $tempData = [PSCustomObject]@{
                    Date = Get-Date -format 'yyyy-MM-dd' 
                    Time = Get-Date -format 'HH:mm:ss'
                    Asset = $snipeAsset
                    Serial = $serialNumber
                    Location = $currentLocation.name
                }
                $csvOutput += $tempData
    
            }

            if ($auditOnSet)
            {
               #Set-snipeAudit -deviceID $snipeAsset -deviceLocation $currentLocation.snipeid -snipeURL $snipeURL -snipeHeaders $snipeHeaders
            }
        }
        else {
            Write-Log "Error Retrieving Device, ignoring" -ForegroundColor Red
            Continue
        }



    }
}
