
$csvStudent = "<<eduhub-path>>\CasesStudents.csv"
$csvFamilies = "<<eduhub-path>>\CasesFamilies.csv"
$csvStaff = "<<eduhub-path>>\CasesStaff.csv"
$csvOutput = "Temp.csv"

##TODO: Check if Staff, Student or Parent Files are more recent than the output of this script, if the output file does not exist, create, if and of the input files are NEWER than the output file create

$outputData = @()


##Students
$importedStudents = Import-CSV -Path $csvStudent
$importedFamilies = Import-CSV -Path $csvFamilies

foreach ($student in ($importedStudents))
{
    $tempAD = $null
    $detEmail = $null
    $tempParentEmail = $null

    if ($student.STATUS -ne "LEFT" -and $student.STATUS -ne "INAC")
    {
        
        $tempAD = Get-ADUser -Identity $student.SIS_ID -Properties *
        foreach ($email in $tempAD.otherMailbox)
        {
            if ($email -ilike "*@schools.vic.edu.au")
            {
                $detEmail = $email
            }
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($student.FAMILY))
    {
        $tempFamily=$null
        $tempFamily = $importedFamilies | Where-Object SIS_ID -eq $student.FAMILY

        if ($student.CONTACT_A -eq "B" -and (-not [string]::IsNullOrWhiteSpace($tempFamily.E_MAIL_B)))
        {
            
            $tempParentEmail = $tempFamily.E_MAIL_B
        }
        else {
            $tempParentEmail = $tempFamily.E_MAIL_A
        }

    }


    $tempObject = $null
    $tempObject = [PSCustomObject]@{

        "User Id" = $student.SIS_ID
        "User Type" = $tempAD.Title
        "CASES Status" = $student.STATUS
        "DET Email" = $detEmail
        "School Year" = $student.SCHOOL_YEAR
        "Class" = $student.HOME_GROUP
        "Parent Email*" = $tempParentEmail
    
    }
    
    $outputData += $tempObject


}

$importedStaff = Import-Csv -Path $csvStaff

foreach ($staffMember in ($importedStaff | Where-Object {$_.'STATUS' -ne "LEFT" -and $_.'STATUS' -ne "INAC" -and $_.SIS_ID -inotlike "CRT*"}))
{
    $tempAD = $null
    $tempUserID = $null
    if (-not [string]::IsNullOrWhiteSpace($staffMember.SIS_EMPNO))
    {
        $tempAD = Get-ADUser -Identity $staffMember.SIS_EMPNO -Properties *
        $tempUserID = $staffMember.SIS_EMPNO
    }
    else
    {
        $tempAD = Get-ADUser -Identity $staffMember.SIS_ID -Properties *
        $tempUserID = $staffMember.SIS_EMPNO
    }
    #Iterate to next loop if the userID is unknown at this point (avoids invalid rows)
    if ([string]::IsNullOrWhiteSpace($tempUserID))
    {
        Continue
        
    }
    $detEmail = $null
    foreach ($email in $tempAD.otherMailbox)
    {
        if ($email -ilike "*@education.vic.gov.au")
        {
            $detEmail = $email
        }
    }


    $tempObject = $null
    $tempObject = [PSCustomObject]@{

        "User Id" = $tempUserID
        "User Type" = "Staff"
        "CASES Status" = $staffMember.STATUS
        "Title" = $tempAD.Title
        "DET Email" = $detEmail
        "Front Desk" = "<<frontdesk-email>>"
    
    }
    
    $outputData += $tempObject

}

$outputData | Export-Csv -Path $csvOutput -Encoding utf8