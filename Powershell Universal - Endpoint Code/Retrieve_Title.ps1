
# Enter your script to process requests.

if ([string]::IsNullOrWhiteSpace($userid) -or $userID -eq ":userid")
{
    return "ERROR - No User ID Provided"
}

$adUsers = @()

if ([System.Web.HttpUtility]::UrlDecode($userid) -match "^\w+([-+.']\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$")
{
    $userid = [System.Web.HttpUtility]::UrlDecode($userid)
    $adUser = $null
    
    $adUser = get-aduser -filter "userPrincipalName -eq `"$userid`"" -Properties Title | select samaccountname, Title
    $adUsers += $adUser.SAMAccountName

    #Validate against Primary Email
    $adUser = $null
    $adUser = get-aduser -filter "mail -eq `"$userid`"" -Properties Title | select samaccountname, Title
    
    if ($adUsers -notcontains $adUser.SAMAccountName)
    {
        $adUsers += $adUser.SAMAccountName
    }

}
else 
{
    $adUser = get-aduser -filter "SAMaccountname -eq `"$userid`""  -Properties Title | select samaccountname, Title
    $adUsers += $adUser.SAMAccountName
}

if ($adUsers.Count -eq 1)
{
    return $adUser.title
}
elseif ($adUsers.Count -eq 0)
{
    return $null
}
else
{
    return $adUsers.Count
}
