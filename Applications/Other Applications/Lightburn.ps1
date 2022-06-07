$productName = "LightBurn" #Name of the Product
$tryNetworkCache = $true #Try the network cache for a copy of this file?


##Product URL Information
$latestURI = "https://github.com/LightBurnSoftware/deployment/releases/latest"

#Network Cache Information
$cacheSMB = "<<CACHEADDRESS>>" #No Trailing Slash

#Local Client Cache Path
$localCachePath = "C:\Cache" #No trailing slash

###################### Working Code ########################

$fileAcquired = $false

if (!(Test-Path $localCachePath -PathType Container))
{
    New-Item -ItemType "Directory" -Path $localCachePath | Out-Null
}

if ($tryNetworkCache -eq $true)
{
    if (Test-Path $cacheSMB)
    {
        try
        {
            Copy-Item -Source "$cacheSMB\$productName-Current.exe" -Destination "$localCachePath\$productName-Current.exe"
            if (Test-Path $localCachePath\$productName-Current.exe)
            {
                $fileAcquired = $true
            }
        }
        catch
        {
            throw $_
        }
    }
    
}

if ($fileAcquired -eq $false)
{
    $versionURL = $null
    try 
    {
        $request = Invoke-WebRequest -Method Head -Uri $latestURI
        if ($request.BaseResponse.ResponseUri -ne $null) {
            # This is for Powershell 5
            $versionURL = $request.BaseResponse.ResponseUri.AbsoluteUri
        }
        elseif ($request.BaseResponse.RequestMessage.RequestUri -ne $null) {
            # This is for Powershell core
            $versionURL = $request.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
        }
 
        $retry = $false
    }
    catch {
        if (($_.Exception.GetType() -match "HttpResponseException") -and ($_.Exception -match "302")) {
            $latestURI = $_.Exception.Response.Headers.Location.AbsoluteUri
            $retry = $true
        }
        else {
            throw $_
        }
    }
    $version = $versionURL.SubString(($versionURL.LastIndexOf("/"))+1)
    try
    {
        Invoke-WebRequest -Uri "https://github.com/LightBurnSoftware/deployment/releases/download/$version/LightBurn-v$version.exe" -OutFile "$localCachePath\$productName-Current.exe"
        if (Test-Path $localCachePath\$productName-Current.exe)
        {
            $fileAcquired = $true
        }
    }
    catch
    {
        throw $_
    }
}


