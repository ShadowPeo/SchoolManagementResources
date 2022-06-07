# Detection
try {

    # check the reg key for the taskbar teams app icon
    # Reg2CI (c) 2021 by Roger Zander
    if ( (Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarMn' -ErrorAction Stop ) -eq 0 ) { $RegCompliance = $true }
    else { $RegCompliance = $false } 

    # check if the teams app is installed
    if ($null -eq (Get-AppxPackage -Name MicrosoftTeams) ) { $AppCompliance = $true }
    else { $AppCompliance = $false }
    
    # evaluate the compliance
    if ($RegCompliance -and $AppCompliance -eq $true) {

        Write-Host "Success, app/reg removed"
        exit 0
    }
    else {
        Write-Host "Failure, app/reg detected"
        exit 1
    }
   
    
}
catch {
    $errMsg = _.Exception.Message
    Write-Host $errMsg
    exit 1
}