Import-Module "$PSScriptRoot\Config.ps1"

$checkURL=$snipeURL.Substring((Select-String 'http[s]:\/\/' -Input $snipeURL).Matches[0].Length)

if ($checkURL.IndexOf('/') -eq -1)
{
    #Test ICMP connection
    if ((Test-Connection -TargetName $checkURL))
    {
        Write-Log "Successfully to Snipe-IT server at address $checkURL"
    }
    else 
    {
        Write-Log "Cannot connect to Snipe-IT server at address $checkURL exiting"
        exit
    }
}

#Create Snipe Headers
$snipeHeaders=@{}
$snipeHeaders.Add("accept", "application/json")
$snipeHeaders.Add("Authorization", "Bearer $snipeAPIKey")


$serialNumbers =  Import-CSV "$PSScriptRoot\Serials.csv"
for ($i=0; $i -lt $serialNumbers.Count; $i++)
{
    
    try 
    {
        $snipeResult = $null #Blank Snipe result
        $snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/byserial/$($serialNumbers[$i])" -Method GET -Headers $snipeHeaders

        if ($null -ne $snipeResult)
        {
            #Covert from result to JSON content
            if ($snipeResult.total -eq 1)
            {
                
                $snipeResult = $snipeResult.rows[0]
                Write-Output $snipeResult
                #$SerialsNumbers.AssetTag = $snipeResult.
                
            }
            else 
            {
                Write-Log "More than one device with $deviceSerial exists in Snipe-IT, Exiting"
                exit
            }
            
        }
        else 
        {
            Write-Log "Cannot retrieve device $deviceSerial from Snipe-IT due to unknown error, exiting"
            exit
        }
    }
    catch 
    {
        Write-Log $_.Exception
        exit
    }
}