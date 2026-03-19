$adUsers = Get-ADUser -SearchBase "OU=Students,OU=Users,OU=Western Port Secondary College,DC=Curric,DC=Western-Port-SC,DC=wan" -Filter 'Description -like "*ORE*"' -Properties Description,GivenName,Surname
$usersNotInGroup = @()
$usersInGroup = @()

foreach ($user in $adUsers) {
    $groupMembership = Get-ADPrincipalGroupMembership $user
    if (-not ($groupMembership.Name -contains "ACL_STUDENT_AUP_RETURNED")) {
        $usersNotInGroup += [PSCustomObject]@{
            GivenName = $user.GivenName
            Surname = $user.Surname
            SamAccountName = $user.SamAccountName
        }
    }
    else {
        $usersInGroup += [PSCustomObject]@{
            GivenName = $user.GivenName
            Surname = $user.Surname
            SamAccountName = $user.SamAccountName
        }
    }
}

# Display results
$usersNotInGroup | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath "UsersNotInGroup.csv"
$usersInGroup | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath "UsersInGroup.csv"