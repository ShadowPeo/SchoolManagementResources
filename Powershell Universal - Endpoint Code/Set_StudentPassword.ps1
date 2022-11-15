
# Enter your script to process requests.
$creds = $Secret:StudentPasswordReset

if ([string]::IsNullOrWhiteSpace($userid) -or $userID -eq ":userid")
{
    return "ERROR - No User ID Provided"
}



$adUsers = @()

if ([System.Web.HttpUtility]::UrlDecode($userid) -match "^\w+([-+.']\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$")
{
    $userid = [System.Web.HttpUtility]::UrlDecode($userid)
    $adUser = $null
    
    $adUser = get-aduser -filter "userPrincipalName -eq `"$userid`""

    if($null -ne $adUser)
    {
        $adUsers += $adUser.SAMAccountName
    }
    
    #Validate against Primary Email
    $adUser = $null
    $adUser = get-aduser -filter "mail -eq `"$userid`""
    
    if($null -ne $adUser -and $adUsers -notcontains $adUser.SAMAccountName)
    {
        $adUsers += $adUser.SAMAccountName
    }
    
}
else 
{
    $adUser = get-aduser -filter "SAMaccountname -eq `"$userid`""
    $adUsers += $adUser.SAMAccountName
}

if ($adUsers.Count -eq 1)
{
    $password = Invoke-RestMethod  -UseBasicParsing "http://www.dinopass.com/password/strong"
    Set-ADAccountPassword -Identity ($adUsers[0]) -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $password -Force) -Credential $creds -server 10.124.224.137
    return $password
}
elseif ($adUsers.Count -eq 0)
{
    return $null
}
else
{
    return $adUsers.Count
}
