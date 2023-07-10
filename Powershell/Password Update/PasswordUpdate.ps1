
<#
.SYNOPSIS
  Reads a CSV containing current passwords, and updates the complext password using the base password and the complexity prefix, outputs the data to a CSV to be reimported into Keepass

.DESCRIPTION

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
    CSV containing current usernames and the base passwords
    Data from Active Directory
    
.OUTPUTS
    CSV containing a list of current students with their base passwords, pulled from Dinopass and updated if not in the export
  
.NOTES
  Version:        1.0
  Author:         Justin Simmonds
  Creation Date:  2023-01-15
  Purpose/Change: Initial script development
  
.EXAMPLE
  
#>
#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Modules
Import-Module ActiveDirectory

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Complexity Prefix
$prefix="23$"

#-----------------------------------------------------------[Functions]------------------------------------------------------------
function Get-Password
{
    Param(
            [string]$userBirthdate,
            [string]$pwType
         )

    try 
    {
        if ( $pwType -ieq "Simple")
        {
            return Invoke-RestMethod -UseBasicParsing "http://www.dinopass.com/password"
        }
        else
        {
            return Invoke-RestMethod  -UseBasicParsing "http://www.dinopass.com/password/strong"
        }
    }
    catch
    {
        if ($userBirthdate -ne $null -and $userBirthdate -ne "")
        {
            return "Western@" + (Get-Date -date $userBirthdate -format ddMM)
        }
        else
        {
            return "Western@" + (Get-Random -Minimum 1000 -Maximum 9999)
        }
        
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

$adStudents = (Get-ADUser -Server "<<DOMAIN_CONTROLLER>>" -SearchBase "<<OU_STUDENTS>>" -Filter * -Properties otherMailbox | Sort-Object samAccountName)
$keepassStudents = (Import-CSV Passwords.csv | Sort-Object samAccountName)


for ($i=0;$i-lt$adStudents.Length;$i++)
{
    if ($keepassStudents.samAccountName -contains $adStudents[$i].samAccountName)
    {
        if ($adStudents[$i].DistinguishedName -match "<<OU_EXITING_STUDENTS>>")
        {
            Write-Host "$($adStudents[$i].samAccountName) Exiting, Ignored" -ForegroundColor Magenta
        }
        else 
        {
            Write-Host "$($adStudents[$i].samAccountName) Match Found"
            $tempUser = $null
            $tempUser = $keepassStudents | Where-Object samAccountName -eq $adStudents[$i].SamAccountName
            Write-Host "$($tempUser.samAccountName) | $($adStudents[$i].SamAccountName)"
            Set-ADAccountPassword -Identity $adStudents[$i].DistinguishedName -NewPassword (ConvertTo-SecureString -AsPlainText "$prefix$($tempUser.Password)" -Force)
        }
        
    }
    else 
    {
        $tempPassword = $null
        $tempPassword = Get-Password -pwType "Simple"
        
        $tempUser = New-Object PSObject
        $tempUser | Add-Member -type NoteProperty -Name 'samAccountName' -Value ($adStudents[$i].samAccountName).ToUpper()
        
        
        if (-not ([string]::IsNullOrWhiteSpace(($adStudents[$i].otherMailbox[0]))))
        {
            $tempUser | Add-Member -type NoteProperty -Name 'eduPass' -Value (($adStudents[$i].otherMailbox[0]).SubString(0,($adStudents[$i].otherMailbox[0]).IndexOf("@"))).ToUpper()
        }
        else
        {
            $tempUser | Add-Member -type NoteProperty -Name 'eduPass' -Value ""
        }

        
        $tempUser | Add-Member -type NoteProperty -Name 'username' -Value "NEW:$($tempUser.samAccountName)/$($tempUser.eduPass)"
        $tempUser | Add-Member -type NoteProperty -Name 'Password' -Value $tempPassword

        $keepassStudents += $tempUser
        $tempPassword = "$prefix$tempPassword"
        Write-Host "$($adStudents[$i].samAccountName) No Match Found" -ForegroundColor Red
        Write-Host "$($adStudents[$i].samAccountName) Password set to $tempPassword" -ForegroundColor Red
        Set-ADAccountPassword -Identity $adStudents[$i].DistinguishedName -NewPassword (ConvertTo-SecureString -AsPlainText "$prefix$tempPassword" -Force)
    }
}

$keepassStudents | Export-Csv -Path "keepassoutput.csv" -Encoding ASCII