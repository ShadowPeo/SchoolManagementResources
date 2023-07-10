
#Modules
Import-Module "$PSScriptRoot/Config.ps1" -Force #Contains protected data (API Keys, URLs etc)
$devices = Import-CSV "$PSScriptRoot/Devices.csv"
#----------------------------------------------------------[Declarations]----------------------------------------------------------
#Script Variables - Declared to stop it being generated multiple times per run
$snipeRetrieval = $false
$snipeResult = $null #Blank Snipe result

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Log ($logMessage)
{
    Write-Host "$(Get-Date -UFormat '+%Y-%m-%d %H:%M:%S') - $logMessage"
}


#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion

    $checkURL=$snipeURL.Substring((Select-String 'http[s]:\/\/' -Input $snipeURL).Matches[0].Length)

    if ($checkURL.IndexOf('/') -eq -1)
    {
        #Test ICMP connection
        if ((Test-Connection $checkURL))
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

    for ($i=00;$i-lt$devices.Length;$i++)
    {

        try 
        {
            $snipeResult = $null #Blank Snipe result
            $snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/bytag/$($devices[$i].'Asset ID')" -Method GET -Headers $snipeHeaders

            if ($snipeResult.status -ne "error")
            {
                Write-Log "Sucessfully retrieved device information for $deviceSerial from Snipe-IT"
                $devices[$i].Serial = $snipeResult.serial
                if (-not [string]::IsNullOrWhiteSpace($devices[$i].User))
                {
                    $snipeHeaders.Add("content-type", "application/json")
                    $snipeID = $null
                    $snipeID = $snipeResult.ID
                    if (-not [string]::IsNullOrWhiteSpace($snipeResult.assigned_to))
                    {
                        #$snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/$snipeID/checkin" -Method POST -Headers $snipeHeaders
                        if ($snipeResult.Status -eq "success")
                        {
                            Write-Log "Checked in $($devices[$i].'Asset ID')"
                        }
                        else {
                            Write-Log "Error Checking in $($devices[$i].'Asset ID')"
                        }
                    }
                    $snipeBody = $null
                    $snipeBody = 
                    @{
                        "checkout_to_type"="user";
                        "status_id"=5;
                        "assigned_user"="class.00a@mwps.vic.edu.au";
                    }
                    
                    <#Invoke-WebRequest -Uri "$snipeURL/api/v1/hardware/$snipeID/checkout" -Method POST -Headers $snipeHeaders -Body $snipeBody

                    #$snipeResult = Invoke-RestMethod -Uri "$snipeURL/api/v1/hardware/$snipeID/checkout" -Method POST -Headers $snipeHeaders  -Body {"checkout_to_type":"user","status_id":5,"assigned_user":"@mwps.vic.edu.au"}'
                    Write-Log "Checked out $($devices[$i].'Asset ID')"
                    #>
                }
                pause
            }
            else 
            {
                Write-Log "Error retrieving device"
                exit
            }
        }
        catch 
        {
            Write-Log $_.Exception
            exit
        }

    }

    #$devices | Export-CSV -Force -Encoding ASCII -Path "$PSScriptRoot/DevicesOutput.csv"