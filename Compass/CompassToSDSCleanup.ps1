<#
.SYNOPSIS

.DESCRIPTION

.PARAMETER CSVPath

.EXAMPLE

.NOTES
Requires the Active Directory module for PowerShell.
#>
#[CmdletBinding()]
#Param (
#    [Parameter(Mandatory = $true, HelpMessage = "The path to the CSV file containing user data.")]
#    [string]$CSVPath
#)

$CSVPath = "$PSScriptRoot"

# Import the CSV files
# Define CSV files to import
$csvFiles = @{
    'Users' = 'users.csv'
    'Enrollments' = 'enrollments.csv'
    'Courses' = 'courses.csv'
    'Classes' = 'classes.csv'
    'Demographics' = 'demographics.csv'
    'Roles' = 'roles.csv'
}

#Array to fix invalid course IDs
$invalidCourseIDs = @{
    "GLOABL" = "GLOBAL"
    "PR" = "PE"
    "LIB" = "LIBRARY"

}

# Create empty hash table for imported data
$ImportedData = @{}

# Import all CSV files
foreach ($file in $csvFiles.GetEnumerator()) {
    try {
        $filePath = Join-Path -Path $CSVPath -ChildPath $file.Value
        $ImportedData[$file.Key] = Import-Csv -Path $filePath
        Write-Verbose "Successfully imported $($file.Value)"
    }
    catch {
        Write-Error "Failed to import $($file.Value): $($_.Exception.Message)"
        return
    }
}

# Assign to individual variables for backward compatibility
$Users = $ImportedData['Users'] | Select-Object sourcedId, username
$Enrollments = $ImportedData['Enrollments']
$Demographics = $ImportedData['Demographics'] | Select-Object @{Name='userSourcedId';Expression={$_.userSourceID}}, * -ExcludeProperty userSourceID
$Roles = $ImportedData['Roles'] | Select-Object @{Name='userSourcedId';Expression={$_.userSourceID}}, * -ExcludeProperty userSourceID
$Courses = $ImportedData['Courses']
$Classes = $ImportedData['Classes'] | Select-Object * -ExcludeProperty code

# Get the current year
$CurrentYear = Get-Date -Format "yyyy"

# Create an array to store the updated users
$UpdatedUsers = @()

# Loop through each user in the CSV
foreach ($User in $Users) {
    # Check if the user exists in Active Directory
    try {
        $ADUser = Get-ADUser -Filter "samAccountName -eq '$($User.username)'" -Properties mail, userCASESStatus -ErrorAction Stop
    }
    catch {
        Write-Warning "User $($User.username) not found in Active Directory. Dropping user."
        continue # Skip to the next user
    }

    # Check if the userCASESStatus is not "LEFT" (Assuming you have a CASESStatus field)
    if ($ADUser.userCASESStatus -ne "LEFT" -and -not [string]::IsNullOrEmpty($ADUser.mail)) { #
        # Update the username with the userPrincipalName attribute from Active Directory
        $User.username = ($ADUser.UserPrincipalName).ToLower()
        # Add the updated user to the array
        $UpdatedUsers += $User
    }
    else {
        Write-Warning "User $($User.username) has a CASES status of LEFT or no email address. Dropping user."
    }
}

# Remove users from files where the user no longer exists in the users file

# Filter enrollments
$Enrollments = $Enrollments | Where-Object {
    $UpdatedUsers.sourcedID -contains $_.userSourcedId
}

# Filter demographics
$Demographics = $Demographics | Where-Object {
    $UpdatedUsers.sourcedID -contains $_.userSourcedID
}

# Filter roles
$Roles = $Roles | Where-Object {
    $UpdatedUsers.sourcedID -contains $_.userSourcedID
}

# Loop through each course in the CSV and update the title
foreach ($Course in $Courses) {


    if ($Course.title -match '^(FOUN|[1-6])(.+)$')
    {
        $yearIdentifier = $matches[1]
        $className = ($matches[2]).ToUpper()
        if ($invalidCourseIDs.ContainsKey($className)) {
            $className = $invalidCourseIDs[$className]
            $course.title = $course.Title -replace $matches[2], $className
        }
    }
    elseif ($Course.sourcedId -match '^(FOUN|[1-6])(.+)$')
    {
        $yearIdentifier = $matches[1]
        $className = $course.title
        if ($invalidCourseIDs.ContainsKey($className)) {
            $className = $invalidCourseIDs[$className]
            $course.title = $course.Title -replace $matches[2], $className
        }
        $course.title = "$yearIdentifier$className"
    }

    $Course.sourcedId = ("$($Course.title)-$CurrentYear").ToUpper()

    if ($Course.title -match '^(FOUN|[1-6])(.+)$') {
        
        # Format the title with proper spacing and year
        $formattedTitle = if ($yearIdentifier -eq 'FOUN') {
            "Foundation $className-$CurrentYear"
        } else {
            "Year 0$yearIdentifier $className-$CurrentYear"
        }
        
        $Course.title = $formattedTitle

        # Ensure sourcedId starts with year identifier
        if (-not ($Course.sourcedId -match "^$yearIdentifier")) {
            $Course.sourcedId = "$yearIdentifier$($Course.sourcedId)"
        }
    }
    
}

# Get unique objects based on the updated title
$UniqueCourses = $Courses | Select-Object sourcedId, orgSourcedId, title | Get-Unique -AsString

foreach ($Class in $Classes) {
    if ($Class.courseSourcedId -match '(\d+|FOUN)([^_]+)') {
        $yearIdentifier = $matches[1]
        $subject = ($matches[2]).ToUpper()
        if ($subject -eq 'LIB') {
            $subject = 'LIBRARY'
        }

        $class.courseSourcedId = "$yearIdentifier$subject-$currentYear"

        # Validate courseSourcedId exists in UniqueCourses
        if (-not ($UniqueCourses.sourcedId -contains $class.courseSourcedId)) {
            Write-Warning "Course ID '$($class.courseSourcedId)' not found in Courses list"
        }
    }
        if ($Class.title -match '((?:\d{2}|0F)[A-Z])') {
            $classCode = $matches[1]
        }
        $class.sourcedId = ("$CurrentYear-$subject-$classCode").ToUpper()
        $class.title = "Class $classCode $subject $CurrentYear"

}

foreach ($enrollment in $Enrollments)
{
    if ($enrollment.classSourcedId -match '((?:\d{2}|0F)[A-Z])') {
        $classCode = $matches[1]
    }

    if ($enrollment.classSourcedId -match '(\d+|FOUN)([^_]+)') {
        $yearIdentifier = $matches[1]
        $subject = ($matches[2]).ToUpper()
        if ($subject -eq 'LIB') {
            $subject = 'LIBRARY'
        }

        if ($enrollment.sourcedID -match '((?:\d{2}|0F)[A-Z])') {
            $classCode = $matches[1]
        }

        $enrollment.classSourcedId = "$currentYear-$subject-$currentYear"

    }

    
    $enrollment.classSourcedId = ("$CurrentYear-$subject-$classCode").ToUpper()

    # Validate classSourcedId exists in Classes
    if (-not ($classes.sourcedId -contains $enrollment.classSourcedId)) {
        Write-Warning "Class ID '$($enrollment.classSourcedId)' not found in Classes list"
    }

    
}

# Convert demographics birthDate to YYYY-MM-DD format
ForEach ($demographicsUser in $Demographics) {
    $demographicsUser.birthDate = Get-Date -Date $demographicsUser.birthDate -Format "yyyy-MM-dd"
}

# Convert roles for Prep/Foundation/0 to Kindergarten as per US Standard
foreach ($role in $Roles) {
    if ($role.grade -eq '0') {
        $role.grade = 'kg'
    }
}

# Export the updated users to a new CSV file
$UpdatedUsers | Export-Csv -Path (Join-Path -Path $CSVPath -ChildPath "users.csv") -NoTypeInformation
Write-Host "Updated users exported to: $(Join-Path -Path $CSVPath -ChildPath "users.csv")"

# Export the updated courses to a new CSV file
$UniqueCourses | Export-Csv -Path (Join-Path -Path $CSVPath -ChildPath "courses.csv") -NoTypeInformation
Write-Host "Updated courses exported to: $(Join-Path -Path $CSVPath -ChildPath "courses.csv")"

# Export the updated courses to a new CSV file 
$Classes | Export-Csv -Path (Join-Path -Path $CSVPath -ChildPath "classes.csv") -NoTypeInformation
Write-Host "Updated classes exported to: $(Join-Path -Path $CSVPath -ChildPath "classes.csv")"

# Export the filtered enrollments to a new CSV file
$Enrollments | Export-Csv -Path (Join-Path -Path $CSVPath -ChildPath "enrollments.csv") -NoTypeInformation
Write-Host "Enrollments exported to: $(Join-Path -Path $CSVPath -ChildPath "enrollments.csv")"

# Export the filtered demographics to a new CSV file
$Demographics | Export-Csv -Path (Join-Path -Path $CSVPath -ChildPath "demographics.csv") -NoTypeInformation
Write-Host "Filtered demographics exported to: $(Join-Path -Path $CSVPath -ChildPath "demographics.csv")"

# Export the filtered roles to a new CSV file
$Roles | Export-Csv -Path (Join-Path -Path $CSVPath -ChildPath "roles.csv") -NoTypeInformation
Write-Host "Filtered roles exported to: $(Join-Path -Path $CSVPath -ChildPath "roles.csv")"