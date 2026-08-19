#Requires -Modules ActiveDirectory, SqlServer

<#
    Writes-only companion to Compare-DiscoSnipeAssignedUser.ps1 - intended to run frequently
    (e.g. every ~30 minutes via a PowerShell Universal workflow) to keep Disco and Snipe-IT
    assignments converging, without generating a report every run. All actions gated by $DryRun:

    - Any assignment where the user's CASES Status is 'LEFT' and the user no longer exists in AD
      (accounts are retained ~30 days after exit, so still existing in AD means it's too soon) is
      unassigned in both Disco and Snipe-IT.
    - Any mismatch where the Disco assignment is strictly newer than Snipe-IT's is applied to
      Snipe-IT: checked in first if currently assigned to someone else (Snipe-IT refuses to check
      an asset out while it's still checked out), then checked out to the Disco-assigned user.
    - Any Snipe-IT asset sitting at "Deployed" with nobody assigned has its status reverted to
      "Available".

    Designed to run as a PowerShell Universal script - all inputs are variables at the top so
    they can be bound to PSU variables/secrets. If run outside PSU, replace the <<PLACEHOLDER>>
    values directly.
#>

# ----- Variables -----

$SqlServerInstance     = '<<DISCO_SQL_SERVER>>'
$SqlDatabase           = 'Disco'
$SqlUseIntegratedAuth  = $false
$SqlUsername           = '<<DISCO_SQL_USERNAME>>'
$SqlPassword           = '<<DISCO_SQL_PASSWORD>>'

$ADServer              = '<<AD_SERVER>>'
$ADUseCurrentCredential = $false
$ADUsername            = '<<AD_USERNAME>>'
$ADPassword            = '<<AD_PASSWORD>>'
$ADUserSearchBase      = ''                    # optional - restrict the AD user pull to an OU, blank = whole domain

$SnipeItBaseUrl           = '<<SNIPE_IT_BASE_URL>>'
$SnipeItApiToken          = '<<SNIPE_IT_API_TOKEN>>'
$SnipeItRequestDelayMs    = 500          # pause between Snipe-IT API calls to stay under its rate limit
$SnipeItMaxRetries        = 5            # retries on HTTP 429 before giving up on that page
$SnipeItDeployedStatusId  = 4            # status_id considered "Deployed" in Snipe-IT
$SnipeItAvailableStatusId = 2            # status_id to revert a Deployed-but-unassigned asset to

$DryRun = $true                # $true = report only, no writes. Set $false to actually action.

# ----------------------------------------------------------------------

$sqlQuery = @'
SELECT
    dua.[DeviceSerialNumber],
    dua.[AssignedUserId],
    dua.[AssignedDate],
    ud.[Value] AS CasesStatus
FROM [Disco].[dbo].[DeviceUserAssignments] dua
LEFT JOIN [Disco].[dbo].[UserDetails] ud
    ON dua.[AssignedUserId] = ud.[UserId]
    AND ud.[Key] = 'CASES Status'
WHERE dua.[UnassignedDate] IS NULL
'@

$sqlConnectionParams = @{
    ServerInstance          = $SqlServerInstance
    Database                = $SqlDatabase
    TrustServerCertificate  = $true
}
if (-not $SqlUseIntegratedAuth) {
    $sqlConnectionParams['Username'] = $SqlUsername
    $sqlConnectionParams['Password'] = $SqlPassword
}

$discoDevices = Invoke-Sqlcmd @sqlConnectionParams -Query $sqlQuery

$adCredential = $null
if (-not $ADUseCurrentCredential) {
    $securePassword = ConvertTo-SecureString $ADPassword -AsPlainText -Force
    $adCredential = New-Object System.Management.Automation.PSCredential ($ADUsername, $securePassword)
}

$adUserParams = @{
    Filter      = '*'
    Server      = $ADServer
    Properties  = 'UserPrincipalName', 'ProxyAddresses'
}
if ($adCredential) {
    $adUserParams['Credential'] = $adCredential
}
if ($ADUserSearchBase) {
    $adUserParams['SearchBase'] = $ADUserSearchBase
}

$adUsers = Get-ADUser @adUserParams

$adUsersBySam = @{}
$adUsersByProxyAddress = @{}
foreach ($user in $adUsers) {
    if ($user.SamAccountName -and $user.UserPrincipalName) {
        $adUsersBySam[$user.SamAccountName] = $user.UserPrincipalName
    }

    foreach ($proxyAddress in $user.ProxyAddresses) {
        $colonIndex = $proxyAddress.IndexOf(':')
        $address = if ($colonIndex -ge 0) { $proxyAddress.Substring($colonIndex + 1) } else { $proxyAddress }
        if ($address) {
            $adUsersByProxyAddress[$address] = $user.SamAccountName
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

function ConvertTo-SnipeItDateTime {
    param($Value)

    if (-not $Value) {
        return $null
    }
    if ($Value -is [string]) {
        return [datetime]$Value
    }
    if ($Value.PSObject.Properties['datetime']) {
        return [datetime]$Value.datetime
    }
    if ($Value.PSObject.Properties['date']) {
        return [datetime]$Value.date
    }
    return $null
}

$snipeAssets = @()
$offset = 0
$limit  = 500
do {
    $response = Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware?limit=$limit&offset=$offset" -Method Get
    $snipeAssets += $response.rows
    $offset += $limit
} while ($offset -lt $response.total)

$snipeUsers = @()
$offset = 0
$limit  = 500
do {
    $response = Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/users?limit=$limit&offset=$offset" -Method Get
    $snipeUsers += $response.rows
    $offset += $limit
} while ($offset -lt $response.total)

$snipeUserIdsByUsername = @{}
foreach ($snipeUser in $snipeUsers) {
    if ($snipeUser.username) {
        $snipeUserIdsByUsername[$snipeUser.username] = $snipeUser.id
    }
}

$snipeAssetsBySerial = @{}
$duplicateSnipeSerials = @{}
foreach ($asset in $snipeAssets) {
    if ([string]::IsNullOrWhiteSpace($asset.serial)) {
        continue
    }

    if ($snipeAssetsBySerial.ContainsKey($asset.serial)) {
        $duplicateSnipeSerials[$asset.serial] = $true
        continue
    }

    $assignedUpn = $null
    if ($asset.assigned_to -and $asset.assigned_to.type -eq 'user') {
        $assignedUpn = $asset.assigned_to.username
    }

    $assignDate = ConvertTo-SnipeItDateTime $asset.last_checkout

    $snipeAssetsBySerial[$asset.serial] = [PSCustomObject]@{
        Id          = $asset.id
        IsAssigned  = [bool]$asset.assigned_to
        AssignedUpn = $assignedUpn
        AssignDate  = $assignDate
    }
}

$leftUserSerials = @{}
foreach ($device in $discoDevices) {
    if ($device.CasesStatus -ne 'LEFT') {
        continue
    }

    $serial = $device.DeviceSerialNumber
    if ([string]::IsNullOrWhiteSpace($serial)) {
        continue
    }

    $userRaw = $device.AssignedUserId
    $sam = $null
    if ($userRaw) {
        $sam = $userRaw.Substring($userRaw.LastIndexOf('\') + 1)
    }

    if (-not $sam -or $adUsersBySam.ContainsKey($sam)) {
        continue
    }

    $leftUserSerials[$serial] = $true

    if ($DryRun) {
        Write-Output "DryRun - would unassign serial $serial in Disco and Snipe-IT (CASES status LEFT, user '$sam' no longer in AD)"
        continue
    }

    $escapedSerial = $serial -replace "'", "''"
    $escapedUserId = $userRaw -replace "'", "''"
    $unassignQuery = "UPDATE [Disco].[dbo].[DeviceUserAssignments] SET [UnassignedDate] = GETDATE() WHERE [DeviceSerialNumber] = '$escapedSerial' AND [AssignedUserId] = '$escapedUserId' AND [UnassignedDate] IS NULL"

    try {
        Invoke-Sqlcmd @sqlConnectionParams -Query $unassignQuery
        Write-Output "Unassigned in Disco: serial $serial (CASES status LEFT, user '$sam' no longer in AD)"
    }
    catch {
        Write-Error "Failed to unassign serial $serial in Disco : $_"
    }

    $snipeAsset = $snipeAssetsBySerial[$serial]
    if ($snipeAsset -and $snipeAsset.IsAssigned) {
        try {
            Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($snipeAsset.Id)/checkin" -Method Post -Body '{}' | Out-Null
            Write-Output "Unassigned in Snipe-IT: serial $serial (asset id $($snipeAsset.Id))"
        }
        catch {
            Write-Error "Failed to unassign serial $serial in Snipe-IT : $_"
        }
    }
}

foreach ($device in $discoDevices) {
    $serial = $device.DeviceSerialNumber
    if ([string]::IsNullOrWhiteSpace($serial)) {
        continue
    }

    if ($leftUserSerials.ContainsKey($serial) -or $duplicateSnipeSerials.ContainsKey($serial)) {
        continue
    }

    $snipeAsset = $snipeAssetsBySerial[$serial]
    if (-not $snipeAsset) {
        continue
    }

    $discoSamRaw = $device.AssignedUserId
    $discoSam = $null
    if ($discoSamRaw) {
        $discoSam = $discoSamRaw.Substring($discoSamRaw.LastIndexOf('\') + 1)
    }

    $discoUpn = if ($discoSam) { $adUsersBySam[$discoSam] } else { $null }
    $snipeUpn = $snipeAsset.AssignedUpn

    if ($discoUpn -eq $snipeUpn) {
        continue
    }
    if ($discoSam -and $snipeUpn -and $adUsersByProxyAddress[$snipeUpn] -eq $discoSam) {
        continue
    }

    $discoAssignDate = if ($device.AssignedDate) { [datetime]$device.AssignedDate } else { [datetime]::MinValue }
    $snipeAssignDate = if ($snipeAsset.AssignDate) { $snipeAsset.AssignDate } else { [datetime]::MinValue }

    if ($discoAssignDate -le $snipeAssignDate) {
        continue
    }

    if (-not $discoUpn) {
        Write-Information "Serial $serial - Disco assignment is newer but Disco's sAMAccountName '$discoSam' could not be resolved to an AD user - cannot assign in Snipe-IT"
        continue
    }

    $snipeUserId = $snipeUserIdsByUsername[$discoUpn]
    if (-not $snipeUserId) {
        Write-Information "Serial $serial - Disco assignment is newer but no Snipe-IT user found for '$discoUpn' - cannot assign"
        continue
    }

    if ($DryRun) {
        Write-Output "DryRun - would assign serial $serial to '$discoUpn' in Snipe-IT (Disco assign date $discoAssignDate is more recent than Snipe-IT $snipeAssignDate)"
        continue
    }

    try {
        if ($snipeAsset.IsAssigned) {
            Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($snipeAsset.Id)/checkin" -Method Post -Body '{}' | Out-Null
        }

        $checkoutBody = @{
            status_id        = $SnipeItDeployedStatusId
            checkout_to_type = 'user'
            assigned_user    = $snipeUserId
        } | ConvertTo-Json
        Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($snipeAsset.Id)/checkout" -Method Post -Body $checkoutBody | Out-Null
        Write-Output "Assigned in Snipe-IT: serial $serial to '$discoUpn' (Disco assign date $discoAssignDate is more recent than Snipe-IT $snipeAssignDate)"
    }
    catch {
        Write-Error "Failed to assign serial $serial to '$discoUpn' in Snipe-IT : $_"
    }
}

foreach ($asset in $snipeAssets) {
    if (-not $asset.status -or $asset.status.id -ne $SnipeItDeployedStatusId -or $asset.assigned_to) {
        continue
    }

    if ($DryRun) {
        Write-Output "DryRun - would revert status to $SnipeItAvailableStatusId for Deployed-but-unassigned Snipe-IT asset: $($asset.serial) (asset id $($asset.id))"
        continue
    }

    try {
        $statusBody = @{ status_id = $SnipeItAvailableStatusId } | ConvertTo-Json
        Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($asset.id)" -Method Patch -Body $statusBody | Out-Null
        Write-Output "Reverted status to $SnipeItAvailableStatusId for Deployed-but-unassigned Snipe-IT asset: $($asset.serial) (asset id $($asset.id))"
    }
    catch {
        Write-Error "Failed to revert status for Snipe-IT asset $($asset.serial) : $_"
    }
}
