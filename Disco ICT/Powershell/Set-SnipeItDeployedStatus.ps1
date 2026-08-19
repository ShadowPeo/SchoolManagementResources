<#
    One-off (but re-runnable) Snipe-IT cleanup: finds every asset sitting in "Ready to Deploy"
    status that is actually checked out - to a user, a location, or another asset, it doesn't
    matter which - and corrects its status to "Deployed". Snipe-IT only, no Disco/AD involved.

    Designed to run as a PowerShell Universal script - all inputs are variables at the top so
    they can be bound to PSU variables/secrets. If run outside PSU, replace the <<PLACEHOLDER>>
    values directly.
#>

# ----- Variables -----

$SnipeItBaseUrl                = '<<SNIPE_IT_BASE_URL>>'
$SnipeItApiToken               = '<<SNIPE_IT_API_TOKEN>>'
$SnipeItRequestDelayMs         = 500           # pause between Snipe-IT API calls to stay under its rate limit
$SnipeItMaxRetries             = 5             # retries on HTTP 429 before giving up on that page
$SnipeItReadyToDeployStatusIds = @(1, 2)       # status_id(s) considered "Ready to Deploy" in Snipe-IT
$SnipeItDeployedStatusId       = 4             # status_id to set on assets found checked out

$DryRun = $true                # $true = report only, no status changes. Set $false to actually action.

# ----------------------------------------------------------------------

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

$snipeAssets = @()
$offset = 0
$limit  = 500
do {
    $response = Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware?limit=$limit&offset=$offset" -Method Get
    $snipeAssets += $response.rows
    $offset += $limit
} while ($offset -lt $response.total)

foreach ($asset in $snipeAssets) {
    if (-not $asset.status -or $asset.status.id -notin $SnipeItReadyToDeployStatusIds) {
        continue
    }

    if (-not $asset.assigned_to) {
        continue
    }

    if ($DryRun) {
        Write-Output "DryRun - would set status to Deployed for asset $($asset.serial) (asset id $($asset.id)), checked out to '$($asset.assigned_to.name)' ($($asset.assigned_to.type))"
        continue
    }

    try {
        $statusBody = @{ status_id = $SnipeItDeployedStatusId } | ConvertTo-Json
        Invoke-SnipeItRequest -Uri "$SnipeItBaseUrl/api/v1/hardware/$($asset.id)" -Method Patch -Body $statusBody | Out-Null
        Write-Output "Set status to Deployed for asset $($asset.serial) (asset id $($asset.id)), checked out to '$($asset.assigned_to.name)' ($($asset.assigned_to.type))"
    }
    catch {
        Write-Error "Failed to update status for asset $($asset.serial) : $_"
    }
}
