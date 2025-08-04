# Install required modules if not already installed
Import-Module Microsoft.Graph

# Connect to Microsoft Graph
Connect-MgGraph -Scopes @(
    "User.Read.All",
    "Device.Read.All",
    "DeviceManagementManagedDevices.Read.All"
)

# Function to get device information from both sources
function Get-DeviceLastSeenDates {
    param(
        [Parameter(Mandatory = $false)]
        [int]$DaysBack = 30
    )

    # Get date for filtering
    $filterDate = (Get-Date).AddDays(-$DaysBack)

    # Get Entra ID devices
    $entraDevices = Get-MgDevice -All | Select-Object DisplayName, 
        @{Name='EntraLastSeenDate';Expression={$_.ApproximateLastSignInDateTime}},
        DeviceId

    # Get Intune devices
    $intuneDevices = Get-MgDeviceManagementManagedDevice -All | Select-Object DeviceName,
        @{Name='IntuneLastSeenDate';Expression={$_.LastSyncDateTime}},
        AzureADDeviceId

    # Combine the results
    
    $results = $entraDevices | ForEach-Object {
        $entraDevice = $_
        $intuneDevice = $intuneDevices | Where-Object { $_.AzureADDeviceId -eq $entraDevice.DeviceId }

        [PSCustomObject]@{
            DeviceName = $entraDevice.DisplayName
            EntraLastSeen = $entraDevice.EntraLastSeenDate
            IntuneLastSeen = $intuneDevice.IntuneLastSeenDate
            DaysSinceEntraSeen = if ($entraDevice.EntraLastSeenDate) {
                [math]::Round((New-TimeSpan -Start $entraDevice.EntraLastSeenDate -End (Get-Date)).TotalDays, 1)
            } else { "Never" }
            DaysSinceIntuneSeen = if ($intuneDevice.IntuneLastSeenDate) {
                [math]::Round((New-TimeSpan -Start $intuneDevice.IntuneLastSeenDate -End (Get-Date)).TotalDays, 1)
            } else { "Never" }
        }
    }

    return $results | Sort-Object DeviceName
}

# Get and display the results
$devices = Get-DeviceLastSeenDates -DaysBack 30
$devices | Format-Table -AutoSize

# Export to CSV if needed
$devices | Export-Csv -Path "DeviceLastSeen_$(Get-Date -Format 'yyyyMMdd').csv" -NoTypeInformation