function Convert-StatusMessage ($statusCode)
{
    switch ($statusCode)
    {
    200	{"Request successful"}
    201	{"Request to create or update resource successful"}
    202	{"The request was accepted for processing, but the processing has not completed"}
    204	{"Request successful. Resource successfully deleted"}
    400	{"Bad request. Verify the syntax of the request, specifically the request body"}
    401	{"Authentication failed. Verify the credentials being used for the request"}
    403	{"Invalid permissions. Verify the account being used has the proper permissions for the resource you are trying to access"}
    404	{"Resource not found. Verify the URL path is correct"}
    409	{"The request could not be completed due to a conflict with the current state of the resource"}
    412	{"Precondition failed. See error description for additional details"}
    413	{"Payload too large"}
    414	{"Request-URI too long"}
    500	{"Internal server error. Retry the request or contact support if the error persists"}
    503	{"Service unavailable"}
    }
}

class JamfServer
{
    # Class properties
    [string]    $jamfURL
    [string]    $jamfToken
    [hashtable] $jamfHeaders
}

function Get-jamfToken()
{
    param (
        [Parameter(mandatory=$true)][string]$tennantURL,
        [Parameter()][string]$user,
        [Parameter()][string]$pass
    )

    $url = "https://$tennantURL/api/v1/auth/token"
    $validCreds = $false
    while ($validCreds -eq $false)
    {
        if ($null -eq $apiCreds -and ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) -or (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass) -and $failure -ge 1))
        {
            #$apiCreds = Get-Credential -Message 
            if($apiCreds = $host.ui.PromptForCredential('Credentials Required', "Please Insert API User Credentials for $tennantURL",'', ''))
            {

            }
            else
            {
                exit
            }
        }
        
        if ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1)
        {
            if ($null -ne $apiCreds)
            {
                $user = $apiCreds.Username
                $pass = $apiCreds.GetNetworkCredential().Password
            }

            $Headers = @{
                Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($user):$($pass)")))"
            }

            try 
            {
                $call = Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json;charset=UTF-8" -Headers $Headers

                if ($null -ne $call)
                {
                    $validCreds = $true
                }

            }
            catch 
            {
                if (($_ | ConvertFrom-Json).httpStatus -eq 401)
                {
                    Write-Host "Invalid Credentials, please try again"
                    $apiCreds = $null
                    $failure = 1
                }
                else 
                {
                    Write-Host "An error with a status code of $(($_ | ConvertFrom-Json).httpStatus) was returned, meaning that $(Convert-StatusMessage ($_ | ConvertFrom-Json).httpStatus)"   
                    exit
                }

            }
        }
        else 
        {
            
        }
    }

    $script:jamfServer = New-Object JamfServer -Property @{
        jamfURL = $tennantURL
        jamfToken = $call.token
        jamfHeaders = @{
            Authorization = "Bearer $($call.token)"
        }
    }

    return $call.token
}

function Get-jamfMobileDevices 
{
    param (
        [Parameter()][int]$page,
        [Parameter()][int]$pageSize = 10000 #Set to 10000 by default to do a single retrival for all but the largest deployments
    )

    $url = "https://$($script:jamfServer.jamfURL)/api/v2/mobile-devices?page-size=$pagesize"
    
    $apiQuery = Invoke-RestMethod -Method Get -Uri $url -Headers $script:jamfServer.jamfHeaders -ContentType "application/json;charset=UTF-8"
    
    return $apiQuery
    
}

function Get-jamfSingleMobileDevice
{
    param (
        [Parameter(Mandatory=$true)][int]$deviceID
    )

    $url = "https://$($script:jamfServer.jamfURL)/api/v2/mobile-devices/$deviceID"
    
    
    $apiQuery = Invoke-RestMethod -Method Get -Uri $url -Headers $script:jamfServer.jamfHeaders -ContentType "application/json;charset=UTF-8"
    
    return $apiQuery

}

function Get-jamfSingleMobileDeviceDetail
{
    param (
        [Parameter(Mandatory=$true)][int]$deviceID
    )

    $url = "https://$($script:jamfServer.jamfURL)/api/v2/mobile-devices/$deviceID/detail"
    
    $apiQuery = Invoke-RestMethod -Method Get -Uri $url -Headers $script:jamfServer.jamfHeaders -ContentType "application/json;charset=UTF-8"
    
    return $apiQuery

}
function Get-jamfUsers
{
    param (
        [Parameter()][int]$page,
        [Parameter()][int]$pageSize = 10000 #Set to 10000 by default to do a single retrival for all but the largest deployments
    )

    $url = "https://$($script:jamfServer.jamfURL)/JSSResource/users"

    $headers = @{
        Authorization = "Bearer $($script:jamfServer.jamfToken)"
        Accept = "application/json"
    }
    
    $apiQuery = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ContentType "application/json;charset=UTF-8"
    
    return $apiQuery.Users
    
}

#Get detailed user information
function Get-jamfUserDetail
{
    param (
        [Parameter(Mandatory=$true)][int]$userID
    )

    $apiQuery = Invoke-RestMethod -Method Get -Uri "https://$($script:jamfServer.jamfURL)/JSSResource/users/id/$userID" -Headers $script:jamfServer.jamfHeaders -ContentType "application/json;charset=UTF-8"

    if (-not [string]::IsNullOrWhiteSpace($apiQuery))
    {
        return $apiQuery.user
    }
    else 
    {
        return "Error"
    }
    
}

function New-jamfUser {

    param (
        [Parameter(mandatory=$true)][int]$userID,
        #[Parameter(mandatory=$true)][string]$username,
        #[Parameter(mandatory=$true)][string]$email,
        #[Parameter()][string]$phone,
        #[Parameter()][string]$position,
        #[Parameter()][string]$realName,
        #[Parameter()][string]$department,
        #[Parameter()][string]$building,
        #[Parameter()][string]$room,
        [Parameter()][string]$body
    )

    if (-not (Test-Path variable:script:jamfServer))
    {
        Write-Host "No Jamf Server Object Found, please provide a valid URL and Token"
        exit
    }

    $url = "https://$($script:jamfServer.jamfURL)/JSSResource/users/id/$userID"
    
    $headers = @{
        Authorization = "Bearer $($script:jamfServer.jamfToken)"
        Accept = "application/json"
    }
    
    try 
    {
        $apiQuery = Invoke-WebRequest -Method Post -Uri $url -Headers $headers -ContentType "application/xml;charset=UTF-8" -Body $body
        return $apiQuery.StatusCode

    }
    catch 
    {
        <#Do this if a terminating exception happens#>
    }
}

#Get detailed user information
function Remove-jamfUser
{
    param (
        [Parameter(Mandatory=$true)][int]$userID
    )

    $apiQuery = Invoke-RestMethod -Method DELETE -Uri "https://$($script:jamfServer.jamfURL)/JSSResource/users/id/$userID" -Headers $script:jamfServer.jamfHeaders -ContentType "application/json;charset=UTF-8"

    if (-not [string]::IsNullOrWhiteSpace($apiQuery) -and $apiQuery.id -eq $userID)
    {
        return $true
    }
    else 
    {
        return $false
    }
    
}