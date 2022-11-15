
$adUsers = @()

if ([System.Web.HttpUtility]::UrlDecode($userid) -match "^\w+([-+.']\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$")
{
    $userid = [System.Web.HttpUtility]::UrlDecode($userid)
    $adUser = $null
    
    $adUser = get-aduser -filter "userPrincipalName -eq `"$userid`"" | select samaccountname
    $adUsers += $adUser.SAMAccountName

    #Validate against Primary Email
    $adUser = $null
    $adUser = get-aduser -filter "mail -eq `"$userid`"" | select samaccountname
    
    if ($adUsers -notcontains $adUser.SAMAccountName)
    {
        $adUsers += $adUser.SAMAccountName
    }

}
else 
{
    $adUser = get-aduser -filter "SAMaccountname -eq `"$userid`"" | select samaccountname
    $adUsers += $adUser.SAMAccountName
}

if ($adUsers.Count -eq 1)
{
    return $adUser
}
elseif ($adUsers.Count -eq 0)
{
    return $null
}
else
{
    return $adUsers.Count
}
