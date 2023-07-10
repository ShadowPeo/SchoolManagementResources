Param 
    (
        [string]$deploymentPath = "D:\Deployment",  #No Trailing Slash
        [string]$exportGroup, 
        [string]$exportPath = "C:\Temp",
        [switch]$listGroups
    )


if ([string]::IsNullOrWhiteSpace($deploymentPath))
{
    Write-Host "No Deployment Path (Path to MDT Deployment Share) Provided, Exiting"
    exit 99
}
else
{
    [xml]$driverGroupDoc = Get-Content -Path "$deploymentPath\Control\DriverGroups.xml"
    $driverGroups = $driverGroupDoc.groups.group
}



if($listGroups)
{
    foreach ($groupName in $driverGroups.Name)
    {
        Write-Host $groupName
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($exportGroup) -and -not [string]::IsNullOrWhiteSpace($exportPath))
{
    
    Write-Host "Exporting to $exportPath"

    [xml]$driverDoc = Get-Content -Path "$deploymentPath\Control\Drivers.xml"
    $drivers = $driverDoc.drivers.driver

    $exportGroupObject = $driverGroups | Where-Object name -eq $exportGroup

    $exportArray = @()

    foreach ($driverMember in $exportGroupObject.Member)
    {
        $currentDriver = $null
        $currentDriver = $drivers | Where-Object guid -eq $driverMember
        $driverPath = $null
        $driverPath = "$deploymentPath$(($currentDriver.Source).SubString(1))"
        $driverPath = ($driverPath.Substring(0,$driverPath.LastIndexOf("\"))).ToString()
        if ($exportArray -notcontains $driverPath)
        {
            Write-Host "Exporting $($currentDriver.Name)"
            Copy-Item -Path $driverPath -Destination "$exportPath\$exportGroup" -Recurse -Force
            $exportArray += $driverPath
        }
    

    }
}
else
{
    Write-Host "No Deployment Group or Export Path (Path to put the driver folders) Provided, Exiting"
    exit 99
}