Import-Module "$PSScriptRoot/Modules/JAMF.ps1"
Import-Module "$PSScriptRoot/Config/config.ps1"


$token = Get-jamfToken -tennantURL $tennantURL #-user $jamfUser -pass $jamfPass

$iPadsTemp = (Get-jamfMobileDevices).results | Where-Object -FilterScript {($_.model -like "iPad*") -and -not [string]::IsNullOrWhiteSpace($_.username) -and -not [string]::IsNullOrWhiteSpace($_.name)} | Sort-Object username
$iPadsBYOD = $iPadsTemp | Where-Object name -like "iPadB*" | Sort-Object username | Select-Object username
$iPadsAllocated = $iPadsTemp | Where-Object username -like "class.*@$upnDomain" | Sort-Object username | Select-Object name, username
$students = Import-CSV -Path $studentCSV | Select-Object *, @{n='INT_YEAR';e={[int]$_.School_Year}},@{label="Homegroup";expression={$($_."HOME_GROUP")}} | Where-Object {($_.INT_YEAR -gt 0) -and ($_.INT_YEAR -le 5)}

$studentsNoiPad = @()
$studentsExited = @()
$homegroupNumbers = @()


if (-not (Test-Path -Path "$PSScriptRoot/Working"))
{
    New-Item -Path "$PSScriptRoot/Working" -ItemType Directory
}

foreach ($student in $Students)
{
    if ($iPadsBYOD.Username -notcontains ("$($student.SIS_ID)$upnDomain") -and $student.STATUS -eq "ACTV")
    {
        $studentsNoiPad += $student
        #Write-Host "$($student.SIS_ID) does not have an iPad | $($student.Homegroup)"
    }
    elseif ($iPadsBYOD.Username -contains ("$($student.SIS_ID)$upnDomain") -and $student.STATUS -eq "LEFT")
    {
        $studentsExited += $student
        #Write-Host "$($student.SIS_ID) Has Left the School - iPads needs to be Removed"
    }
}

$homeGroups = $studentsNoiPad.Homegroup | Sort-Object | Get-Unique 

foreach ($homegroup in $homeGroups)
{
    $requiredCount = $null
    $requiredCount = $studentsNoiPad | Where-Object Homegroup -eq $homeGroup
    if ($null -ne $requiredCount.Count)
    {
        $requiredCount = [Math]::Round([Math]::Ceiling($requiredCount.Count)/$requiredRatio)
    }
    else 
    {
        $requiredCount = 1
    }

    $currentlyAllocated = $null
    $currentlyAllocated = ($ipadsAllocated | Where-Object username -eq "class.$homegroup$upnDomain")
    if ([string]::IsNullOrWhiteSpace($currentlyAllocated) -and [string]::IsNullOrWhiteSpace($currentlyAllocated.Count))
    {
        $currentlyAllocated = 0
    }
    elseif(-not [string]::IsNullOrWhiteSpace($currentlyAllocated) -and [string]::IsNullOrWhiteSpace($currentlyAllocated.Count))
    {
        $currentlyAllocated = 1
    }
    else
    {
        $currentlyAllocated = $currentlyAllocated.Count
    }

    $tempHash = $null
    $tempHash = New-Object PSObject -property @{
        Homegroup=$homegroup
        iPadsRequired=$requiredCount
        iPadsCurrentlyAllocated=$currentlyAllocated
        difference = [double]$($requiredCount - $currentlyAllocated)
        changed=if($currentlyAllocated -ne $requiredCount){$true}else{$false}
     }
    $homegroupNumbers += $tempHash
}

#Check against previous allocations
if ((Test-Path "$PSScriptRoot/Working/PreviousRequired.csv"))
{
    $previousRequired = Import-Csv -Path "$PSScriptRoot/Working/PreviousRequired.csv"

    foreach ($homegroup in $homegroupNumbers)
    {
        if (($previousRequired.Homegroup -contains $homegroup.Homegroup) -and (($previousRequired | Where-Object homegroup -eq $homegroup.Homegroup | Select-Object iPadsRequired).iPadsRequired) -ne $homegroup.iPadsRequired)
        {
            $homegroup.changed = $true
        }
    }
}

if ($changeRequired -eq $true -or ($homegroupNumbers.changed -contains $true))
{
    Write-Host "The following homegroups require the indicated amount of shared devices, if they are not shown then they require none`nthis shows the changed numbers only"
    $homegroupNumbers | Select-Object Homegroup,iPadsRequired,iPadsCurrentlyAllocated,difference | Format-Table

    #Export to CSV
    $homegroupNumbers | Select-Object Homegroup,iPadsRequired | Export-Csv -Path "$PSScriptRoot/Working/PreviousRequired.csv" -Encoding ASCII -NoTypeInformation
}
else 
{
    Write-Host "No classes require allocation changes"
}


if(-not [string]::IsNullOrWhiteSpace($studentsExited) -and $studentsExited.Count -eq 0)
{
    Write-Host "The Following Students have left and need to have their iPads removed from the system"
    $studentsExited.SIS_ID | Format-Table
}
else 
{
    Write-Host "No devices to remove"
}