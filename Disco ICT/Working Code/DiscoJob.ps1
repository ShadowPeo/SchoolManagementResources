using namespace System.Collections.Generic;
using namespace System.Net.Http;

# if anything goes wrong, stop immediately
$ErrorActionPreference = 'Stop';

# import the Http Client
Add-Type -AssemblyName 'System.Net.Http';

# specify job details
$job = [Dictionary[string,string]]::new();

# device and/or user name is required (one or both)
# device serial number
$job['DeviceSerialNumber'] = 'RBNXLP00B457456';
# user name in DOMAIN\username format
$job['UserId'] = '{DOMAIN\username}';

# job type. One of: HMisc, HNWar, HWar, SApp, SImg, SOS, UMgmt (See JobTypes database table for detail)
$job['Type'] = 'HMisc';

# optional comments
$job['Comments'] = 'This device was disabled due to non-audit compliance.
This job was created with automation';

# whether the device is held
$job['DeviceHeld'] = $false;

# quick log options
$job['QuickLog'] = $false;

$form = [List[KeyValuePair[string, string]]]::new();
$form.AddRange($job);
@( # specify job sub types. See JobSubTypes database table for sub types associated with the job type
    'Audit'
) |% { $form.Add([KeyValuePair[string,string]]::new('SubTypes', $job['Type'] + '_' + $_)) };

# prepare the http request body
$body = [FormUrlEncodedContent]::new($form);

$handler = [HttpClientHandler]::new();
$handler.AllowAutoRedirect = $false; # dont follow redirects
$handler.UseDefaultCredentials = $true; # use integrated authentication
$client = [HttpClient]::new($handler);

# specify the Disco ICT server
$client.BaseAddress = 'http://disco:9292/';

# call the Create Job method, posting the job details
$result = $client.PostAsync('/Job/Create', $body);
$result.Wait(); # Wait for the async operation to complete
$response = $result.Result;

$response.EnsureSuccessStatusCode() | Out-Null;

# extract the job number from the response
$contentTask = $response.Content.ReadAsStringAsync();
$contentTask.Wait();
$resultBody = $contentTask.Result;
$jobId = ([regex]"'\/Job\/Show\/(\d+)'").Match($resultBody).Groups[1].Value;

Write-Host "Created job #$($jobId)";
Write-Host "$($client.BaseAddress)Job/Show/$($jobId)"

$client.Dispose();