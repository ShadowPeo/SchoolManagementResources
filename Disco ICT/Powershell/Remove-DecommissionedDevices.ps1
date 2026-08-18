#Requires -Modules ActiveDirectory, SqlServer

<#
    Removes AD computer objects and decommissions the matching Snipe-IT asset for every device
    marked as decommissioned in the Disco database.

    Designed to run as a PowerShell Universal script - all inputs are variables at the top so
    they can be bound to PSU variables/secrets. If run outside PSU, replace the <<PLACEHOLDER>>
    values directly.
#>

# ----- Variables -----

$SqlServerInstance     = '<<DISCO_SQL_SERVER>>'
$SqlDatabase           = 'Disco'
$SqlUseIntegratedAuth  = $false                # $true = current identity, $false = use SqlUsername/SqlPassword
$SqlUsername           = '<<DISCO_SQL_USERNAME>>'
$SqlPassword           = '<<DISCO_SQL_PASSWORD>>'

$ADServer               = '<<AD_SERVER>>'      # domain controller / AD server to query and act against
$ADUseCurrentCredential = $false               # $true = current identity, $false = use ADUsername/ADPassword
$ADUsername             = '<<AD_USERNAME>>'
$ADPassword             = '<<AD_PASSWORD>>'
$ADSearchBases          = @('<<COMPUTER_OU_DISTINGUISHED_NAME>>') | Where-Object { $_ }  # only objects under these OUs can be matched/deleted

if (-not $ADSearchBases) {
    throw "No AD search base configured - set an OU distinguished name in `$ADSearchBases."
}

$SnipeItBaseUrl                = '<<SNIPE_IT_BASE_URL>>'      # e.g. 'https://assets.example.com'
$SnipeItApiToken               = '<<SNIPE_IT_API_TOKEN>>'
$SnipeItDecommissionedStatusId = 0             # status_id of the decommissioned/archived status label in Snipe-IT
$SnipeItRequestDelayMs         = 500           # pause between Snipe-IT API calls to stay under its rate limit
$SnipeItMaxRetries             = 5             # retries on HTTP 429 before giving up on that asset

$DryRun                 = $true                # $true = report only, no deletions/checkins. Set $false to actually action.

# ----------------------------------------------------------------------

$sqlQuery = 'SELECT ComputerName, SerialNumber FROM Devices WHERE DecommissionedDate IS NOT NULL'

$sqlParams = @{
    ServerInstance          = $SqlServerInstance
    Database                = $SqlDatabase
    Query                   = $sqlQuery
    TrustServerCertificate  = $true
}
if (-not $SqlUseIntegratedAuth) {
    $sqlParams['Username'] = $SqlUsername
    $sqlParams['Password'] = $SqlPassword
}

$decommissionedDevices = Invoke-Sqlcmd @sqlParams

$adCredential = $null
if (-not $ADUseCurrentCredential) {
    $securePassword = ConvertTo-SecureString $ADPassword -AsPlainText -Force
    $adCredential = New-Object System.Management.Automation.PSCredential ($ADUsername, $securePassword)
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

foreach ($device in $decommissionedDevices) {
    $computerName = $device.ComputerName
    if ([string]::IsNullOrWhiteSpace($computerName)) {
        continue
    }

    $shortName = $computerName.Substring($computerName.LastIndexOf('\') + 1)

    $adComputer = $null
    foreach ($searchBase in $ADSearchBases) {
        $adParams = @{
            Server      = $ADServer
            Filter      = "Name -eq '$shortName'"
            SearchBase  = $searchBase
            ErrorAction = 'SilentlyContinue'
        }
        if ($adCredential) {
            $adParams['Credential'] = $adCredential
        }

        $adComputer = Get-ADComputer @adParams
        if ($adComputer) {
            break
        }
    }

    if (-not $adComputer) {
        Write-Verbose "Not found in allowed OUs, skipping: $shortName"
        continue
    }

    if ($DryRun) {
        Write-Output "DryRun - would delete: $shortName ($($adComputer.DistinguishedName))"
        continue
    }

    $removeParams = @{
        Identity    = $adComputer.DistinguishedName
        Server      = $ADServer
        Confirm     = $false
        ErrorAction = 'Stop'
    }
    if ($adCredential) {
        $removeParams['Credential'] = $adCredential
    }

    try {
        Remove-ADComputer @removeParams
        Write-Output "Deleted: $shortName ($($adComputer.DistinguishedName))"
    }
    catch {
        Write-Error "Failed to delete $shortName : $_"
    }
}

foreach ($device in $decommissionedDevices) {
    $serial = $device.SerialNumber
    if ([string]::IsNullOrWhiteSpace($serial)) {
        continue
    }

    try {
        $searchResult = Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/byserial/$serial" -Method Get
    }
    catch {
        Write-Error "Failed to look up Snipe-IT asset for serial $serial : $_"
        continue
    }

    if (-not $searchResult.rows -or $searchResult.rows.Count -eq 0) {
        Write-Verbose "Not found in Snipe-IT, skipping: $serial"
        continue
    }

    if ($searchResult.rows.Count -gt 1) {
        Write-Output "Multiple Snipe-IT assets found for serial $serial - skipping"
        continue
    }

    $asset = $searchResult.rows[0]

    if ($asset.status.id -eq $SnipeItDecommissionedStatusId) {
        Write-Verbose "Already decommissioned in Snipe-IT, skipping: $serial"
        continue
    }

    if ($DryRun) {
        Write-Output "DryRun - would checkin/decommission in Snipe-IT: $serial (asset id $($asset.id))"
        continue
    }

    try {
        if ($asset.assigned_to) {
            Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($asset.id)/checkin" -Method Post -Body '{}' | Out-Null
        }

        $statusBody = @{ status_id = $SnipeItDecommissionedStatusId } | ConvertTo-Json
        Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($asset.id)" -Method Patch -Body $statusBody | Out-Null

        Write-Output "Decommissioned in Snipe-IT: $serial (asset id $($asset.id))"
    }
    catch {
        Write-Error "Failed to decommission Snipe-IT asset for serial $serial : $_"
    }
}
