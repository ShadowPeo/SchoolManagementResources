# Remediation

try {

    # remove the taskbar icon
    # Reg2CI (c) 2021 by Roger Zander
    if ((Test-Path -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced") -ne $true) {
        New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force -ErrorAction Stop 
    }
    New-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarMn' -Value 0 -PropertyType DWord -Force -ErrorAction Stop
    

    # uninstall the teams consumer app
    Get-AppxPackage -Name MicrosoftTeams | Remove-AppxPackage -ErrorAction stop

    # as nothing errored out, we will report success
    Write-Host "Success, regkey set and app uninstalled"
    exit 0
}

catch {
    $errMsg = _.Exception.Message
    Write-Host $errMsg
    exit 1
}