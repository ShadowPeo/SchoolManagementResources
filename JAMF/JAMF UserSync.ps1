#Import JAMF Module
#Import-Module JamfPSPro
Import-Module "$PSSCRIPTROOT/Modules/JAMF.ps1" -Force

#Import Config
Import-Module "$PSScriptRoot/Config/config.ps1"

#Get the credentials for the JAMF Server
$token = Get-jamfToken -tennantURL $tennantURL # -user <USER> -pass <PASS>

#Get all users from JAMF
$jamfUsers = Get-jamfUsers

$nextUser = (($jamfUsers.id | measure -Maximum).Maximum)+1
#Remove users where they do not match the correct username (domain)
foreach ($user in ($jamfUsers | Where-Object name -notlike "*@DOMAIN"))
{
    try
    {
        #Remove-Jamf -Component users -Select ID -Params $user.id -ErrorVariable $outputError
    }
    catch {
        #Write-Host "Failed to remove $($user.name)"
    }
    #pause
}

#Get staff and student users from AD
$adUsers = Get-ADUser -SearchBase "STAFF OU DN" -Filter * -Properties mail,department,employeeType,displayName,title,otherMailbox,physicalDeliveryOfficeName
$adUsers += Get-ADUser -SearchBase "STUDENT OU DN" -Filter * -Properties mail,department,employeeType,displayName,title,otherMailbox,msDS-cloudExtensionAttribute1,physicalDeliveryOfficeName

#Filter AD users for blank email, and users in the exited, exiting, inactive and generic accounts OUs
$adCreate = $adUsers | Where-Object mail -ne $null | Where-Object DistinguishedName -NotLike "*OU=Exited*"  | Where-Object DistinguishedName -NotLike "*OU=Exiting*"  | Where-Object DistinguishedName -NotLike "*OU=Inactive*" | Where-Object DistinguishedName -NotLike "*OU=Generic Accounts*"  | Sort-Object mail



#Check for accounts to create
foreach ($adUser in $adCreate)
{
    if ((($jamfUsers | Where-Object name -like "*@DOMAIN").name -notcontains $adUser.mail) -and -not [string]::IsNullOrWhiteSpace($adUser.mail))
    {
        Write-Host "Need to create account for $($adUser.mail)|$($adUser.Department)"

        $body="
            <user>
                <name>$($adUser.UserPrincipalName)</name>
	            <full_name>$($adUser.displayName)</full_name>
	            <email>$($adUser.mail)</email>
	            <position>$($adUser.title)</position>
                <extension_attributes>
                    <extension_attribute>
                    <name>Graduation Year</name>
                    <value>$($adUser.'msDS-cloudExtensionAttribute1')</value>
                    </extension_attribute>
                    <extension_attribute>
                    <name>Homegroup</name>
                    <value>$($adUser.'physicalDeliveryOfficeName')</value>
                    </extension_attribute>
                    <extension_attribute>
                    <name>Education Email</name>
                    <value>$($adUser.otherMailbox[0])</value>
                    </extension_attribute>
                </extension_attributes>
            </user>
        "
        
        if ((New-jamfUser -userID $nextUser -body $body) -eq 201)
        {
            Write-Host "Successfully created account for $($adUser.mail)"
            $nextUser++
        }

    }
}

#Remove Old Accounts

foreach($jamfUser in ($jamfUsers | Sort-Object name | Where-Object name -like "*@DOMAIN"))
{
    if ($adUsers.userPrincipalName -notcontains $jamfUser.name)
    {
        $username = $null
        $username = $jamfUser.name 

        #Check to ensure this is no a service account
        if (-not (Get-ADUser -Filter {UserPrincipalName -eq $username}))
        {
            Write-Host "Need to remove account for $($jamfUser.name) they do not exist in AD"
            #Check if user still has devices assigned, if the do ignore, else remove
            $userTemp = $null
            $userTemp = Get-jamfUserDetail -userID $jamfUser.id
            if (($userTemp.links.computers.Length -eq 0 -or $userTemp.links.computers.IsEmpty) -and ($userTemp.links.mobile_devices.Length -eq 0 -or $userTemp.links.mobile_devices.IsEmpty))
            {
                Write-Host "$($userTemp.full_name) has no assigned devices, removing"
                $response = Remove-jamfUser -userID $jamfUser.id
                if ($response)
                {
                    Write-Host "Successfully removed user $($userTemp.full_name)"
                }

            }
            else
            {
                Write-Host "$($userTemp.full_name) has a device assigned, please remove the device"
            }

        }
        
        
    }
}


#Merge in Graduation Year, Homegroup, Education Email