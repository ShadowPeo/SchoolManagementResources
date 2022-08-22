Import-Module -Name SQLServer

function Get-DeviceLastSeen {

    Param 
    (
        [string]$SerialNumber, 
        [string]$AssetNumber, 
        [string]$ComputerName,
        [string]$UserID
    )

    $sqlServerInstance = "<<SQLSERVER>>"
    $sqlServerUserId = "<<DA USERNAME>>"
    $sqlServerUserPassword = "<<PASSWORD>>"
    $searchCriteria = $null
    $dataset = $null

    if (-not $SerialNumber -and -not $AssetNumber -and -not $ComputerName -and -not $UserID)
    {
        throw "No Search Criteria Provided, Exiting"
    }

    if (-not [string]::IsNullOrEmpty($SerialNumber))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[SerialNumber] = '$SerialNumber'"
    }

    if (-not [string]::IsNullOrEmpty($AssetNumber))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[AssetNumber] = '$AssetNumber'"
    }

    if (-not [string]::IsNullOrEmpty($ComputerName))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[ComputerName] LIKE '%$ComputerName%'"
    }

    if (-not [string]::IsNullOrEmpty($UserID))
    {
        if (-not [string]::IsNullOrEmpty($searchCriteria))
        {
            $searchCriteria += " AND "
        }
        $searchCriteria += "[AssignedUserId] LIKE '%$UserID%'"
    }
    $searchCriteria
    try
    {
        $connectionString = "Data Source=$sqlServerInstance;Integrated Security=SSPI;Initial Catalog=master; Database = Disco; User Id=$sqlServerUserId; Password=$sqlServerUserPassword;"
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
    }
    catch
    {
        throw "Could not connect to Database Server"
    }

    if($connection.State -eq "Open")
    {
        $sqlCommand = "SELECT [SerialNumber],[AssetNumber],[ComputerName],[AssignedUserId],[LastNetworkLogonDate] FROM [Disco].[dbo].[Devices]  WHERE $searchCriteria;"
        $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
        $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataSet) | Out-Null
    }
    
    $connection.Close()
    $dataSet.Tables | FT
}
