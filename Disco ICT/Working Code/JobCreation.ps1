# if anything goes wrong, stop immediately
$ErrorActionPreference = 'Stop';

# specify job details
$job = @{
    # device and/or user name is required (one or both)
    # device serial number
    'DeviceSerialNumber' = 'RBNXLP00B457456'
    # user name in DOMAIN\username format
#    'UserId' = '{DOMAIN\username}'
    # job type. One of: HMisc, HNWar, HWar, SApp, SImg, SOS, UMgmt (See JobTypes database table for detail)
    'Type' = 'HMisc'
    # optional comments
    'Comments' = 'This device was disabled due to non-audit compliance.
This job was created with automation'
    # whether the device is held
    'DeviceHeld' = $false
    # quick log options
    'QuickLog' = $false
}

# prepare the form data including sub types
$formData = @{}
$job.Keys | ForEach-Object { $formData[$_] = $job[$_] }

# specify job sub types. See JobSubTypes database table for sub types associated with the job type
@('Audit') | ForEach-Object { 
    $formData["SubTypes"] = $job['Type'] + '_' + $_
}

# specify the Disco ICT server and endpoint
$uri = 'http://disco:9292/Job/Create'

# call the Create Job method, posting the job details
$result = Invoke-WebRequest -Uri $uri -Method POST -Body $formData -UseDefaultCredentials -MaximumRedirection 0

# extract the job number from the response
$resultBody = $result.Content
$jobId = ([regex]"'\/Job\/Show\/(\d+)'").Match($resultBody).Groups[1].Value;

Write-Host "Created job #$($jobId)";
Write-Host "http://disco:9292/Job/Show/$($jobId)"