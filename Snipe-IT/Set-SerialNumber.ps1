<#
.SYNOPSIS
  Scans asset tag and serial number to update devices in Snipe-IT and log for Disco import

.DESCRIPTION
  This script allows scanning of an asset tag to identify a device, then scanning
  the serial number to update that device in Snipe-IT. All serial numbers are logged
  to a variable that can be exported to CSV for manual import into Disco ICT.

.INPUTS
    Asset Tag and Serial Number from console input

.OUTPUTS
    Updated device in Snipe-IT
    CSV export of serial numbers for Disco import

.NOTES
  Version:        1.0
  Author:         Justin Simmonds
  Creation Date:  2024-12-17
  Purpose/Change: Initial script development

.EXAMPLE
  .\Set-SerialNumber.ps1

.EXAMPLE
  # For PowerShell Universal
  Set-DeviceSerialNumber -AssetTag "ICT-12345" -SerialNumber "ABC123XYZ"

#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#----------------------------------------------------------[Declarations]----------------------------------------------------------

# Snipe-IT Configuration - Set these variables
$snipeAPIKey = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiIyNiIsImp0aSI6IjRkOGQ2MjdhNDJlYzk5ZTU5ZDBmZjQxMGY0OGVmMjQ1N2Q1M2FlM2YzN2JlZjAxMTIwYjRhNDc2ZDQxMjljYmIwMDYwYmVjNTNkNDhlY2IxIiwiaWF0IjoxNzY1OTI1NjU3LjExMjU4OCwibmJmIjoxNzY1OTI1NjU3LjExMjU5MiwiZXhwIjoyMzk3MDc3NjU3LjA5NjI4LCJzdWIiOiIxNzAwIiwic2NvcGVzIjpbXX0.MnhpXsCfzBYy7_yCtxd7VvkHvOVOwg5kizHPNZTXh22YDNrtdbTcT8kFoiONf0VG8wyjfFniAgQJeSmcJz9qVfpzY6LAOVraLoAkjVy5iH8uDZ2k-j23nU6LKamBQTMLLEsPfUFqfjQdvNsjmMQ6NiGcAsJuH2m4Vi3pyBT3yaobon-VAgq9OiNSkxdPdNagS4kj3-79NMHhGa-w7XWJl-FtO-xwi5Q_PpJyLBfLugiIx59q-bCkk_DGd_vvN9jPMa5pBx1IIoJN4HLLFYaxbeMaGcynZINZsJ7FbeCazbHHLWGMB67V_pmWX1EROpdRZwaqv2uDXDnA0d-kEXS76y0jnxVompKU0j01ATk3TGTtcLGmTsEmdk4Mp8lDC8WcSD5BfLEF1i_Q_vVzhTqdHmxC-v9_evEYnPb2ocn82UBdZn0kDen_sGIv4Fv6dsOvRFHf3wBwzzpVjQkQb8zzO4E2va8xwHgyXrh6ynbeaCip27Ue1yRxLdglUoy7rNgcB7_bEWrBblCKr7CpK7UBwt8r0PkXt7JekaajdrYoJyrWclQ1O-EPtPKYUbNtkxFeJJIkhoerXV_W1nT8E0VWIPMuvooUcv3hb9dy7-cNWlX470-xqddVe4qPBidU-ZDiFX1Pr6Q-xx0wKEtX-K0MpA0D7tSGOUHfihNldqC2l4U"  # Replace with your Snipe-IT API Key
$snipeURL = "https://assets.westernportsc.vic.edu.au"  # Replace with your Snipe-IT URL (no trailing /)
$deviceNamePrefix = "Y500W"  # Prefix for device names (will be formatted as PREFIX-SERIALNUMBER)

# Script Variables
$serialLog = @()
$exportPath = "$PSScriptRoot/serial_updates_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Log {
    Param (
        [Parameter(Mandatory=$true)][string]$logMessage,
        [System.ConsoleColor]$ForegroundColor
    )

    if ($null -eq $ForegroundColor) {
        Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage"
    }
    else {
        Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage" -ForegroundColor $ForegroundColor
    }
}

function Get-SnipeDeviceByAssetTag {
    Param (
        [Parameter(Mandatory=$true)][string]$assetTag,
        [Parameter(Mandatory=$true)][string]$snipeURL,
        [Parameter(Mandatory=$true)][hashtable]$snipeHeaders
    )

    try {
        $snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/bytag/$assetTag" -Method GET -Headers $snipeHeaders

        if ($null -ne $snipeResult) {
            # Check if the response is an error
            if ($snipeResult.status -eq "error") {
                Write-Log "Device with asset tag $assetTag does not exist in Snipe-IT" -ForegroundColor Red
                return $null
            }
            # If we have an ID field, the asset was found successfully
            elseif ($null -ne $snipeResult.id) {
                Write-Log "Successfully retrieved device information for asset tag $assetTag from Snipe-IT" -ForegroundColor Green
                return $snipeResult
            }
            else {
                Write-Log "Unexpected response from Snipe-IT for asset tag $assetTag" -ForegroundColor Red
                return $null
            }
        }
        else {
            Write-Log "Cannot retrieve device with asset tag $assetTag from Snipe-IT" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Log "Error retrieving device: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Set-SnipeDeviceSerialNumber {
    Param (
        [Parameter(Mandatory=$true)][string]$deviceID,
        [Parameter(Mandatory=$true)][string]$serialNumber,
        [Parameter(Mandatory=$true)][string]$snipeURL,
        [Parameter(Mandatory=$true)][hashtable]$snipeHeaders
    )

    try {
        $body = @{
            serial = $serialNumber
        } | ConvertTo-Json

        $snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/$deviceID" -Method PATCH -Headers $snipeHeaders -ContentType 'application/json' -Body $body

        if ($snipeResult.status -eq "success") {
            Write-Log "Successfully updated serial number to $serialNumber for device ID $deviceID" -ForegroundColor Green
            return $true
        }
        else {
            Write-Log "Failed to update serial number: $($snipeResult.messages)" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Log "Error updating device: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Add-SerialToLog {
    Param (
        [Parameter(Mandatory=$true)][string]$assetTag,
        [Parameter(Mandatory=$true)][string]$serialNumber,
        [Parameter(Mandatory=$true)][string]$deviceName,
        [Parameter(Mandatory=$true)][ref]$logArray
    )

    $logEntry = [PSCustomObject]@{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        AssetTag = $assetTag
        SerialNumber = $serialNumber
        DeviceName = $deviceName
    }

    $logArray.Value += $logEntry
    Write-Log "Added serial number $serialNumber to export log" -ForegroundColor Green
}

function Export-SerialLog {
    Param (
        [Parameter(Mandatory=$true)][array]$logArray,
        [Parameter(Mandatory=$true)][string]$exportPath
    )

    if ($logArray.Count -gt 0) {
        try {
            $logArray | Export-Csv -Path $exportPath -NoTypeInformation -Force
            Write-Log "Exported $($logArray.Count) serial number(s) to $exportPath" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Log "Error exporting to CSV: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Log "No serial numbers to export" -ForegroundColor Yellow
        return $false
    }
}

function Set-DeviceSerialNumber {
    <#
    .SYNOPSIS
    Main function to set serial number on a device (designed for PSU)

    .PARAMETER AssetTag
    The asset tag of the device to update

    .PARAMETER SerialNumber
    The new serial number to set
    #>
    Param (
        [Parameter(Mandatory=$true)][string]$assetTag,
        [Parameter(Mandatory=$true)][string]$serialNumber
    )

    # Create Snipe Headers
    $snipeHeaders = @{}
    $snipeHeaders.Add("accept", "application/json")
    $snipeHeaders.Add("Authorization", "Bearer $snipeAPIKey")

    # Get device by asset tag
    $device = Get-SnipeDeviceByAssetTag -assetTag $assetTag -snipeURL $snipeURL -snipeHeaders $snipeHeaders

    if ($null -eq $device) {
        return $false
    }

    # Update serial number
    $success = Set-SnipeDeviceSerialNumber -deviceID $device.id -serialNumber $serialNumber -snipeURL $snipeURL -snipeHeaders $snipeHeaders

    if ($success) {
        # Add to log
        Add-SerialToLog -assetTag $assetTag -serialNumber $serialNumber -deviceName $device.name -logArray ([ref]$script:serialLog)
        return $true
    }

    return $false
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

# Validate Snipe-IT connection
$checkURL = $snipeURL.Substring((Select-String 'http[s]:\/\/' -Input $snipeURL).Matches[0].Length)

if ($checkURL.IndexOf('/') -eq -1) {
    if (Test-Connection -TargetName $checkURL -Count 1 -Quiet) {
        Write-Log "Successfully connected to Snipe-IT server at address $checkURL" -ForegroundColor Green
    }
    else {
        Write-Log "Cannot connect to Snipe-IT server at address $checkURL, exiting" -ForegroundColor Red
        exit
    }
}

# Create Snipe Headers
$snipeHeaders = @{}
$snipeHeaders.Add("accept", "application/json")
$snipeHeaders.Add("Authorization", "Bearer $snipeAPIKey")

Write-Log "Serial Number Update Tool - Scan Asset Tag then Serial Number" -ForegroundColor Cyan
Write-Log "Type 'export' to export logged serial numbers to CSV" -ForegroundColor Cyan
Write-Log "Type 'exit' to quit" -ForegroundColor Cyan
Write-Log "----------------------------------------" -ForegroundColor Cyan

$exitRun = $false

while (-not $exitRun) {
    Write-Log "Please scan or enter Asset Tag" -ForegroundColor Yellow
    $assetTagInput = Read-Host

    # Handle blank input
    if ([string]::IsNullOrWhiteSpace($assetTagInput)) {
        Write-Log "Blank input detected, ignoring" -ForegroundColor Red
        Continue
    }

    # Handle exit command
    if ($assetTagInput -ieq "exit") {
        Write-Log "Exit requested" -ForegroundColor Green

        # Prompt for export before exiting
        if ($serialLog.Count -gt 0) {
            Write-Log "You have $($serialLog.Count) serial number(s) logged. Export to CSV? (Y/N)" -ForegroundColor Yellow
            $exportChoice = Read-Host
            if ($exportChoice -ieq "Y" -or $exportChoice -ieq "Yes") {
                Export-SerialLog -logArray $serialLog -exportPath $exportPath
            }
        }

        $exitRun = $true
        Continue
    }

    # Handle export command
    if ($assetTagInput -ieq "export") {
        Export-SerialLog -logArray $serialLog -exportPath $exportPath
        Continue
    }

    # Get device by asset tag
    $device = Get-SnipeDeviceByAssetTag -assetTag $assetTagInput -snipeURL $snipeURL -snipeHeaders $snipeHeaders

    if ($null -eq $device) {
        Continue
    }

    # Display current device information
    Write-Log "----------------------------------------" -ForegroundColor Cyan
    Write-Log "Device Found:" -ForegroundColor Green
    Write-Log "  Asset Tag: $($device.asset_tag)" -ForegroundColor White
    Write-Log "  Name: $($device.name)" -ForegroundColor White
    Write-Log "  Current Serial: $($device.serial)" -ForegroundColor White
    Write-Log "  Model: $($device.model.name)" -ForegroundColor White
    Write-Log "----------------------------------------" -ForegroundColor Cyan

    # Prompt for serial number
    Write-Log "Please scan or enter Serial Number (or press Enter to cancel)" -ForegroundColor Yellow
    $serialInput = Read-Host

    # Handle blank input (cancel)
    if ([string]::IsNullOrWhiteSpace($serialInput)) {
        Write-Log "Serial number entry cancelled" -ForegroundColor Yellow
        Continue
    }

    # Update serial number
    $success = Set-SnipeDeviceSerialNumber -deviceID $device.id -serialNumber $serialInput -snipeURL $snipeURL -snipeHeaders $snipeHeaders

    if ($success) {
        # Add to log - construct device name as PREFIX-SERIALNUMBER
        $constructedDeviceName = "$deviceNamePrefix-$($serialInput.ToUpper())"
        Add-SerialToLog -assetTag $device.asset_tag -serialNumber $serialInput -deviceName $constructedDeviceName -logArray ([ref]$serialLog)
        Write-Log "Total serial numbers logged: $($serialLog.Count)" -ForegroundColor Cyan
    }

    Write-Host "" # Blank line for readability
}

Write-Log "Script completed" -ForegroundColor Green
