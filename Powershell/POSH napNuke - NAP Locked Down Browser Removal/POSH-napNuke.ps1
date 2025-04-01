# ==============================================================================================
# NAME: POSH-napNuke.ps1
# DATE  : 28/03/2025
#
# COMMENT: Attempts to remove all traces of the NAP Lockdown Browser from a system, this script
#          is based of the original napNuke Batch script by Rolfe Hodges
# VERSION: 1, Conversion to Powershell from Batch, added logging and error handling and 
#          self-discovery of the NAP Lockdown Browser installation information where possible
# ==============================================================================================



#Miscellaneous registry keys that are not removed by the uninstaller consinstently
$miscRegistryKeys = @(
    "HKCR:\napldb"
    "HKCU:\SOFTWARE\Janison"
    "HKLM:\SOFTWARE\Classes\napldb"
    "HKEY_USERS:\.DEFAULT\Software\NAP Locked down browser"
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Tracing\SafeExamBrowser_RASAPI32"
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Tracing\SafeExamBrowser_RASMANCS"
)
#NAP Lockdown Browser services that need to be stopped and removed
$services = @(
    "SEBWindowsService", 
    "NAPLDBService"
)

#Registry keys that need to be restored
$touchSettings = @{
    
    "HKCU:\SOFTWARE\Microsoft\Wisp\Touch" = @{
        "TouchGate" = 1
    }

    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad" = @{
        "ThreeFingerSlideEnabled" = 1
        "FourFingerSlideEnabled" = 1
    }
}

# User directories where NAP Lockdown Browser may have created folders
$napAppDirectorys = @(
    "AppData\Local\NAP Locked down browser"
    "AppData\Roaming\NAP Locked down browser"
)

#Find all copies of the NAP Lockdown Browser according to the registry
$installedNAP = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object { ($_.UninstallString -like "*msiexec*") -and ($_.DisplayName -like "NAP*") } | Select-Object DisplayName,DisplayVersion,PSChildName,UninstallString | Sort-Object DisplayName

#Run Registry Resetter if we can find a way to make it work silently
#This script will search for the NAP files in the Program Files directories and run the ReplayRegistryResetter.exe if found
<#
$napFiles = foreach ($basePath in @("${env:ProgramFiles}","${env:ProgramFiles(x86)}")) 
{
    Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -like "NAP*" } |
    Select-Object @{
        Name = 'Location';
        Expression = { $_.FullName }
    }
}

if ($null -ne $napFiles)
{
    foreach ($location in $napFiles)
    {
        Write-Output "Found NAP file at: $($location.Location)"
        if (Test-Path (Join-Path -Path $location.location -ChildPath "ReplayRegistryResetter.exe"))
        {
            #If there is a way to run this silently we need to make this work
            #& $(Join-Path -Path $location.location -ChildPath "ReplayRegistryResetter.exe")
        }
    }
}
#>

#MSI Uninstall
### Code to uninstall the NAP Lockdown Browser
$installedNAP | ForEach-Object {
    $uninstallString = $_.UninstallString
    if ($uninstallString -like "*msiexec*") {
        
        # Uninstall the application using msiexec
        $msiPath = $uninstallString -replace 'msiexec.exe /x ', ''
        Write-Output "Uninstalling NAP Lockdown Browser: $($_.DisplayName)"
        Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /qn" -Wait
        Write-Output "Uninstalled: $($_.DisplayName)"
        Write-Output "Removing Registry key for the installer"
        
        #Remove the registry key for the uninstaller if not cleaned up
        if (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($_.PSChildName)") {
            Remove-Item -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($_.PSChildName)" -Recurse -Force
            Write-Output "Removed registry key: $($_.PSChildName)"
        } else {
            Write-Output "Registry key not found for: $($_.DisplayName)"
        }

    } else {
        Write-Output "Uninstall string not found for: $($_.DisplayName)"
    }
}


#Explicity remote registry items that prevent over the top installs
# Mount HKCR if it doesn't exist
if (!(Test-Path HKCR:)) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
}

Get-ChildItem -Path "HKCR:\Installer\Products" | 
    ForEach-Object {
        $productName = Get-ItemProperty -Path "Registry::$($_.Name)" -Name "ProductName" -ErrorAction SilentlyContinue
        if ($productName -and $productName.ProductName -like "NAP*") {
            #Remove-Item -Path $_.Name -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "Removed registry key: $($_.Name)"
        }
    }

# Clean up miscellaneous registry keys
foreach ($key in $miscRegistryKeys) {
    if (Test-Path $key) {
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Removed registry key: $key"
    } else {
        Write-Output "Registry key not found: $key"
    }
}

# Remove Task Manager and Lock Workstation restrictions
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableTaskMgr" -ErrorAction SilentlyContinue -Force
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableLockWorkstation" -ErrorAction SilentlyContinue -Force

# Check and restore touch settings if they exist

foreach ($path in $touchSettings.Keys) {
    if (Test-Path -Path $path) {
        foreach ($setting in $touchSettings[$path].Keys) {
            try {
                Set-ItemProperty -Path $path -Name $setting -Value $touchSettings[$path][$setting] -Type DWord -Force
                Write-Output "Restored $setting to enabled state"
            }
            catch {
                Write-Output "Failed to set $setting : $_"
            }
        }
    }
    else {
        Write-Output "Registry path not found: $path"
    }
}


# Stop and remove services
foreach ($service in $services) {
    # Try to stop the service gracefully first
    try {
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        Write-Output "Stopped service: $service"
    }
    catch {
        # If service stop fails, force-kill the process
        Get-Process -Name $service -ErrorAction SilentlyContinue | Stop-Process -Force
        Write-Output "Force-killed process: $service"
    }

    # Remove the service
    try {
        $serviceObj = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($serviceObj) {
            #& sc.exe delete $service | Out-Null
            Write-Output "Removed service: $service"
        }
    }
    catch {
        Write-Output "Failed to remove service $service : $_"
    }
}

# Remove the service registry keys
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NAPLDBService" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SEBWindowsService" -Recurse -Force -ErrorAction SilentlyContinue

# Remove folders in all user directories
foreach ($userDir in (Get-ChildItem -Path "C:\Users" -Directory)) 
{
    foreach ($napDir in $napAppDirectorys) 
    {
        $fullPath = Join-Path -Path $userDir.FullName -ChildPath $napDir
        if (Test-Path -Path $fullPath) 
        {
            Remove-Item -Path $fullPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "Removed directory: $fullPath"
        }
    }
    
    foreach ($shortcut in (Get-ChildItem -Path (Join-Path -Path $userDir.FullName -ChildPath "Desktop")  -Filter "NAP*.lnk")) 
    {
        $shortcutPath = $shortcut.FullName
        if (Test-Path -Path $shortcutPath) 
        {
            Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue
            Write-Output "Removed shortcut: $shortcutPath"
        }
    }
}


#Remove various files and folders
Remove-Item -Path "$(${env:ProgramFiles(x86)})\NAP Locked down browser" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Users\Public\Desktop\" -Filter "NAP*.lnk" -Recurse -Force -ErrorAction SilentlyContinue 
Remove-Item -Path "$(Join-Path -Path $env:ALLUSERSPROFILE -ChildPath "Microsoft\Windows\Start Menu\Programs")" -Filter "NAP*.lnk" -Recurse -Force -ErrorAction SilentlyContinue
