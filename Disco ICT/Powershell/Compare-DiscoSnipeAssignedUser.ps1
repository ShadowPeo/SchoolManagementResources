#Requires -Modules ActiveDirectory, SqlServer

<#
    Read-only companion to Set-DiscoSnipeAssignments.ps1 - intended to run about once a day and
    report on the current state, rather than every ~30 minutes like the change script. Makes no
    writes to Disco, Snipe-IT, or AD.

    Compares the assigned user on each device between Disco and Snipe-IT, matched by serial number.
    Disco stores sAMAccountName, Snipe-IT stores UPN, so the full AD user list is pulled once to
    translate between the two.

    - Matches (direct, or via a legacy AD proxyAddress covering a preferred-name change) go to the
      Verbose stream.
    - Mismatches go to the Information stream with a recommendation for which system to update,
      based on whichever side has the more recent assignment date.
    - Also flags every Snipe-IT asset sitting at "Deployed" but checked out to a non-user (room/
      other asset) as skipped, and silently ignores Deployed assets assigned to a user with no
      active Disco assignment record (Disco isn't the source of truth for every asset Snipe-IT
      tracks).

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

$SnipeItBaseUrl          = '<<SNIPE_IT_BASE_URL>>'
$SnipeItApiToken         = '<<SNIPE_IT_API_TOKEN>>'
$SnipeItRequestDelayMs   = 500          # pause between Snipe-IT API calls to stay under its rate limit
$SnipeItMaxRetries       = 5            # retries on HTTP 429 before giving up on that page
$SnipeItDeployedStatusId = 4            # status_id considered "Deployed" in Snipe-IT

# ----------------------------------------------------------------------

$sqlQuery = 'SELECT [DeviceSerialNumber], [AssignedUserId], [AssignedDate] FROM [Disco].[dbo].[DeviceUserAssignments] WHERE [UnassignedDate] IS NULL'

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

$discoDevicesBySerial = @{}
foreach ($device in $discoDevices) {
    if ($device.DeviceSerialNumber) {
        $discoDevicesBySerial[$device.DeviceSerialNumber] = $device
    }
}

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
$adUsersByUpn = @{}
$adUsersByProxyAddress = @{}
foreach ($user in $adUsers) {
    if ($user.SamAccountName -and $user.UserPrincipalName) {
        $adUsersBySam[$user.SamAccountName] = $user.UserPrincipalName
        $adUsersByUpn[$user.UserPrincipalName] = $user.SamAccountName
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
        [string]$Method = 'Get'
    )

    for ($attempt = 1; $attempt -le $SnipeItMaxRetries; $attempt++) {
        try {
            $result = Invoke-RestMethod -Uri $Uri -Headers $snipeHeaders -Method $Method
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
        AssignedUpn = $assignedUpn
        AssignDate  = $assignDate
    }
}

foreach ($device in $discoDevices) {
    $serial = $device.DeviceSerialNumber
    if ([string]::IsNullOrWhiteSpace($serial)) {
        continue
    }

    if ($duplicateSnipeSerials.ContainsKey($serial)) {
        Write-Output "Multiple Snipe-IT assets found for serial $serial - skipping"
        continue
    }

    $snipeAsset = $snipeAssetsBySerial[$serial]
    if (-not $snipeAsset) {
        Write-Information "No matching Snipe-IT asset found for serial $serial"
        continue
    }

    $discoSamRaw = $device.AssignedUserId
    $discoSam = $null
    if ($discoSamRaw) {
        $discoSam = $discoSamRaw.Substring($discoSamRaw.LastIndexOf('\') + 1)
    }

    $discoUpn = $null
    if ($discoSam) {
        $discoUpn = $adUsersBySam[$discoSam]
        if (-not $discoUpn) {
            Write-Information "Serial $serial - AD user not found for Disco sAMAccountName '$discoSam'"
        }
    }

    $snipeUpn = $snipeAsset.AssignedUpn

    if ($discoUpn -eq $snipeUpn) {
        Write-Verbose "Match - serial $serial assigned to '$discoUpn' in both Disco and Snipe-IT"
        continue
    }

    if ($discoSam -and $snipeUpn -and $adUsersByProxyAddress[$snipeUpn] -eq $discoSam) {
        Write-Verbose "Match (via legacy proxyAddress) - serial $serial - Snipe-IT username '$snipeUpn' is a former alias of Disco's assigned user '$discoUpn' (likely a preferred-name change Snipe-IT hasn't picked up)"
        continue
    }

    $discoAssignDate = if ($device.AssignedDate) { [datetime]$device.AssignedDate } else { [datetime]::MinValue }
    $snipeAssignDate = if ($snipeAsset.AssignDate) { $snipeAsset.AssignDate } else { [datetime]::MinValue }

    if ($discoAssignDate -gt $snipeAssignDate) {
        $recommendation = "recommend updating Snipe-IT to '$discoUpn' (Disco assign date $discoAssignDate is more recent than Snipe-IT $snipeAssignDate)"
    }
    elseif ($snipeAssignDate -gt $discoAssignDate) {
        $snipeSam = if ($snipeUpn) { $adUsersByUpn[$snipeUpn] } else { $null }
        $recommendation = "recommend updating Disco to '$snipeSam' (Snipe-IT assign date $snipeAssignDate is more recent than Disco $discoAssignDate)"
    }
    else {
        $recommendation = 'assign dates are equal or unknown on both sides - cannot recommend a direction'
    }

    Write-Information "Mismatch - serial $serial - Disco: '$discoUpn' vs Snipe-IT: '$snipeUpn' - $recommendation"
}

foreach ($asset in $snipeAssets) {
    if (-not $asset.status -or $asset.status.id -ne $SnipeItDeployedStatusId -or -not $asset.assigned_to) {
        continue
    }

    if ($asset.assigned_to.type -ne 'user') {
        Write-Verbose "Deployed and checked out to a non-user ($($asset.assigned_to.type)), skipping: $($asset.serial)"
        continue
    }

    if (-not $discoDevicesBySerial.ContainsKey($asset.serial)) {
        continue
    }
}
