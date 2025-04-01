function Write-StatusMessage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Configuration
$config = @{
    compassUri = "<<COMPASS_URI>>" # Replace with your Compass URI
    UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
    TimeoutSec = 30
}


try {
    # Setup web request parameters
    $params = @{
        Uri = "https://status.compass.education/components.json"
        Method = "GET"
        UserAgent = $config.UserAgent
        TimeoutSec = $config.TimeoutSec
    }


    try {
             
        Write-StatusMessage "Fetching Compass login page..." "Yellow"
        $response = Invoke-WebRequest -Uri "https://$($config.compassUri).compass.education/login.aspx" -Method "GET" -UserAgent $config.UserAgent -TimeoutSec $config.TimeoutSec
    
        # Extract server group using regex pattern
        $response.Content -match '<div class="siteInfo\s*">[^/]*/\s*(ME[0-9A-Z]+)' | Out-Null
        $serverGroup = $Matches[1]
    
        if ($serverGroup) 
        {
            Write-StatusMessage "Server Group has been found to be $serverGroup" "Green"
        } else {
            Write-StatusMessage "Server group not found in the page content" "Red"
            exit 1
        }
    }
    catch {
        Write-StatusMessage "Error accessing Compass login page: $_" "Red"
        exit 1
    }

    Write-StatusMessage "Fetching Compass status data..." "Yellow"
    $response = Invoke-RestMethod @params

    # Create array to hold service objects
    $serviceTable = @()

    # Process each component and create custom objects
    foreach ($component in $response.components) {

        
        $statusNumber = switch ($component.status) {
            'operational' { "0" }
            'degraded_performance' { "1" }
            'partial_outage' { "2" }
            'major_outage' { "3" }
            default { "4" }
        }
        
        $groupNameParts = $component.group.name -split '-'
        if(-not [string]::IsNullOrWhiteSpace($groupNameParts[2])) {
            $groupName = $groupNameParts[2].Trim()
        }
        else {
            $groupName = $component.group.name
        }

        
        if ([string]::IsNullOrEmpty($component.group)) {
            $nameParts = $component.name -split '-'
            if(-not [string]::IsNullOrWhiteSpace($nameParts[2])) {
                $groupName = $nameParts[2].Trim()
            }
            else {
                $groupName = $component.name
            }
            $component.name = "Summary"
            
        } 

        $serviceTable += [PSCustomObject]@{
            Group = $groupName
            Service = $component.name
            Description = $component.description
            statusID = $statusNumber
            Status = $component.status
        }
    }

    # Display grouped tables
    $groupedServices = $serviceTable | Sort-Object Service | Group-Object Group

    foreach ($group in $groupedServices) {
        Write-StatusMessage "`nGroup: $($group.Name)" "Cyan"
        $group.Group | Format-Table -Property Service, @{
            Name = 'Status'
            Expression = { 
                $color = switch ($_.statusNumber) {
                    '0' { 'Green' }
                    '1' { 'Yellow' }
                    '2' { 'Yellow' }
                    '3' { 'Red' }
                    default { 'Gray' }
                }
                Write-Host $_.StatusSymbol -ForegroundColor $color -NoNewline
                " $($_.Status)"
            }
        } -AutoSize
    }

    # Export to CSV if needed
    $csvPath = ".\compass-status.csv"
    $serviceTable | Export-Csv -Path $csvPath -NoTypeInformation
    Write-StatusMessage "`nStatus data exported to: $csvPath" "Green"
}
catch {
    Write-StatusMessage "Error: $_" "Red"
    exit 1
}