#Requires -Modules ActiveDirectory

<#
    Deletes Snipe-IT users who are no longer current, matched to AD by username (UPN).
    Still enabled in AD - left alone.
    No longer exists in AD, or exists but AD's CASES status attribute marks them as left -
    deleted from Snipe-IT (gated by $DryRun).
    Exists in AD but disabled without a "left" CASES status - left alone, but flagged to
    Information for manual review since it doesn't cleanly fit either bucket.
    Usernames in $ExcludedSnipeUsernames (e.g. service accounts) are always skipped.

    Designed to run as a PowerShell Universal script - all inputs are variables at the top so
    they can be bound to PSU variables/secrets. If run outside PSU, replace the <<PLACEHOLDER>>
    values directly.
#>

# ----- Variables -----

$SnipeItBaseUrl            = '<<SNIPE_IT_BASE_URL>>'
$SnipeItApiToken           = '<<SNIPE_IT_API_TOKEN>>'
$SnipeItRequestDelayMs     = 500             # pause between Snipe-IT API calls to stay under its rate limit
$SnipeItMaxRetries         = 5               # retries on HTTP 429 before giving up on that page
$SnipeItUnassignedStatusId = 11              # status_id to set on assets unassigned from an exited user

$ADServer                = '<<AD_SERVER>>'
$ADUseCurrentCredential  = $false
$ADUsername              = '<<AD_USERNAME>>'
$ADPassword              = '<<AD_PASSWORD>>'
$ADCasesStatusAttribute  = 'userCASESStatus'   # TBC - confirm actual AD attribute name
$ADCasesStatusLeftValue  = 'Left'              # TBC - confirm actual value used for exited users
$ADComplianceRetainedOUs = @()                 # OU DNs kept enabled for records-keeping only - treated as exited regardless of Enabled
$ADUsersSearchBase       = ''                  # OU DN to restrict the AD user pull to (should cover $ADComplianceRetainedOUs too). Blank = whole domain

$ExcludedSnipeUsernames = @('sysadmin', 'sa.icttools-ro')  # Snipe-IT usernames to always skip, case-insensitive

$DryRun = $true                # $true = report only, no deletions. Set $false to actually delete.

# ----------------------------------------------------------------------

$adCredential = $null
if (-not $ADUseCurrentCredential) {
    $securePassword = ConvertTo-SecureString $ADPassword -AsPlainText -Force
    $adCredential = New-Object System.Management.Automation.PSCredential ($ADUsername, $securePassword)
}

$adUserParams = @{
    Filter      = '*'
    Server      = $ADServer
    Properties  = 'UserPrincipalName', 'Enabled', $ADCasesStatusAttribute
}
if ($adCredential) {
    $adUserParams['Credential'] = $adCredential
}
if ($ADUsersSearchBase) {
    $adUserParams['SearchBase'] = $ADUsersSearchBase
}

$adUsers = Get-ADUser @adUserParams

$adUsersByUpn = @{}
foreach ($user in $adUsers) {
    if ($user.UserPrincipalName) {
        $inComplianceOU = $false
        foreach ($ou in $ADComplianceRetainedOUs) {
            if ($ou -and $user.DistinguishedName -like "*$ou") {
                $inComplianceOU = $true
                break
            }
        }

        $adUsersByUpn[$user.UserPrincipalName] = [PSCustomObject]@{
            Enabled        = $user.Enabled
            CasesStatus    = $user.$ADCasesStatusAttribute
            InComplianceOU = $inComplianceOU
        }
    }
}

$snipeHeaders = @{
    Authorization = "Bearer $SnipeItApiToken"
    Accept        = 'application/json'
}

function Invoke-SnipeItRequest {
    param(
        [string]$Uri,
        [string]$Method = 'Get',
        [string]$Body = $null
    )

    for ($attempt = 1; $attempt -le $SnipeItMaxRetries; $attempt++) {
        try {
            $requestParams = @{ Uri = $Uri; Headers = $snipeHeaders; Method = $Method }
            if ($Body) {
                $requestParams['Body'] = $Body
                $requestParams['ContentType'] = 'application/json'
            }
            $result = Invoke-RestMethod @requestParams
            Start-Sleep -Milliseconds $SnipeItRequestDelayMs
            return $result
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 429 -and $attempt -lt $SnipeItMaxRetries) {
                $waitSeconds = [math]::Pow(2, $attempt)
                Write-Output "Snipe-IT rate limited, retrying in $waitSeconds seconds (attempt $attempt of $SnipeItMaxRetries)"
                Start-Sleep -Seconds $waitSeconds
                continue
            }
            throw
        }
    }
}

$snipeUsers = @()
$offset = 0
$limit  = 500
do {
    $response = Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/users?limit=$limit&offset=$offset" -Method Get
    $snipeUsers += $response.rows
    $offset += $limit
} while ($offset -lt $response.total)

foreach ($snipeUser in $snipeUsers) {
    $username = $snipeUser.username
    if ([string]::IsNullOrWhiteSpace($username)) {
        Write-Information "Snipe-IT user id $($snipeUser.id) has no username, cannot match against AD - skipping"
        continue
    }

    if ($ExcludedSnipeUsernames -contains $username) {
        Write-Verbose "Excluded, skipping: $username"
        continue
    }

    $adUser = $adUsersByUpn[$username]

    if ($adUser -and $adUser.Enabled -and -not $adUser.InComplianceOU) {
        Write-Verbose "Still enabled in AD, leaving alone: $username"
        continue
    }

    $reason = $null
    if (-not $adUser) {
        $reason = 'no longer exists in AD'
    }
    elseif ($adUser.CasesStatus -eq $ADCasesStatusLeftValue) {
        $reason = "AD CASES status is '$ADCasesStatusLeftValue'"
    }
    elseif ($adUser.InComplianceOU) {
        $reason = 'AD account retained in a compliance/records-keeping OU'
    }

    if (-not $reason) {
        Write-Information "Snipe-IT user '$username' exists in AD but is disabled without a '$ADCasesStatusLeftValue' CASES status - review manually"
        continue
    }

    $userAssets = Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/users/$($snipeUser.id)/assets" -Method Get
    $assetCount = if ($userAssets.rows) { $userAssets.rows.Count } else { 0 }

    if ($DryRun) {
        Write-Output "DryRun - would check in and set status to $SnipeItUnassignedStatusId for $assetCount asset(s), then delete Snipe-IT user: $username (id $($snipeUser.id)) - $reason"
        continue
    }

    foreach ($asset in $userAssets.rows) {
        try {
            Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($asset.id)/checkin" -Method Post -Body '{}' | Out-Null

            $statusBody = @{ status_id = $SnipeItUnassignedStatusId } | ConvertTo-Json
            Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($asset.id)" -Method Patch -Body $statusBody | Out-Null

            Write-Output "Checked in asset $($asset.serial) (asset id $($asset.id)) and set status to $SnipeItUnassignedStatusId - from user: $username"
        }
        catch {
            Write-Error "Failed to check in asset $($asset.serial) for user $username : $_"
        }
    }

    try {
        Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/users/$($snipeUser.id)" -Method Delete | Out-Null
        Write-Output "Deleted Snipe-IT user: $username (id $($snipeUser.id)) - $reason"
    }
    catch {
        Write-Error "Failed to delete Snipe-IT user $username : $_"
    }
}
