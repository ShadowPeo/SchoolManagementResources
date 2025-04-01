<#
.SYNOPSIS
  Provides functions for DiscoICT in Powershell

.DESCRIPTION

.NOTES
  Version:        1.0
  Author:         Justin Simmonds
  Creation Date:  2023-11-01
  Purpose/Change: Initial script development
 
#>

#Sets the location of a device in Disco 
function Set-discoLocation()
{
    Param 
    (
        [Parameter(Mandatory=$true)][string]$deviceID,
        [Parameter(Mandatory=$true)][string]$deviceLocation,
        [Parameter(Mandatory=$true)][string]$discoURL 
        #[Parameter(Mandatory=$true)][hashtable]$discoCreds ##Add support for specified credentials
    )

    $discoPost = $null
    
    if (-not [string]::IsNullOrWhiteSpace($deviceLocation))
    {
        $discoPost = Invoke-WebRequest -Uri "$discoURL/API/Device/UpdateLocation/$($deviceID)?redirect=False&Location=$([URI]::EscapeUriString($deviceLocation))" -UseDefaultCredentials -AllowUnencryptedAuthentication
    }
    else
    {
        Write-Log "Error no location supplied for Disco or Location Blank, ignoring"
        Continue
    }

    if ($discoPost.Content -eq '"OK"')
    {
        Write-Log "Successfully set the location for device $deviceID in Disco" -ForegroundColor Green
    }
    elseif ($discoPost.Content -eq '"Error: Invalid Serial Number or Device Profile Id"')
    {
        Write-Log "Error: Device $deviceID does not exist in Disco" -ForegroundColor Red
    }
    else 
    {
        Write-Log "Unknown error logging $deviceID's location in Disco, Continuing" -ForegroundColor Red
    }
       
}

#Gets the assigned user or outputs unassigned
function Get-discoDeviceAssignedUser() {
 
    param(
        [Parameter(Mandatory=$true)][string]$deviceID,
        [Parameter(Mandatory=$true)][string]$discoURL 
        #[Parameter(Mandatory=$true)][hashtable]$discoCreds ##Add support for specified credentials
    )
 
    $Request = Invoke-RestMethod -UseBasicParsing -Uri "$discoURL/Device/Show/$deviceID" -UseDefaultCredentials -AllowUnencryptedAuthentication
 
    if ($Request -match '<div id="Device_Show_User_Id" title="Id">(?<userid>.*)</div>') {
 
        $assignedUser = $matches.userid
        return $assignedUser
 
    }
    else { 
        return "Unassigned" 
    }
}