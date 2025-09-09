Import-Module ActiveDirectory
Import-Module SQLServer

# Import configuration
$config = Import-PowerShellDataFile -Path "$PSScriptRoot\Config.psd1"

# Database connection parameters from config
$server = $config.server
$database = $config.database
$studentSearchBase = $config.studentSearchBase
$connectionString = "Server=$server;Database=$database;Integrated Security=True;TrustServerCertificate=True;"

# Script-specific parameters
$tableName = "Students"

# Get active students from database
$activeStudentsQuery = @"
SELECT SIS_ID 
FROM $tableName
WHERE STATUS IN ('ACTV', 'FUT', 'LVNG') AND DET_ID IS NULL;
"@

$activeStudents = Invoke-Sqlcmd -ConnectionString $connectionString -Query $activeStudentsQuery
<#
# Create filter for AD query
$sidFilter = "(samAccountName=$($activeStudents[0].SIS_ID))"
foreach ($student in $activeStudents | Select-Object -Skip 1) {
    $sidFilter += " -or (samAccountName -eq '$($student.SIS_ID)')"
}

<#
# Get AD users matching active students
$adUsers = Get-ADUser -SearchBase $studentSearchBase -Filter $sidFilter -Properties otherMailbox |
    Where-Object { $null -ne $_.otherMailbox }

Write-Host "Found $($adUsers.Count) AD users out of $($activeStudents.Count) active students"

#>
# Create SQL Connection
<#$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
try {
    $connection.Open()

    # Prepare SQL Command
    $updateCmd = New-Object System.Data.SqlClient.SqlCommand(@"
        UPDATE $tableName
        SET DET_ID = @DetId
        WHERE SIS_ID = @SisId
        AND (DET_ID IS NULL OR DET_ID != @DetId);
        SELECT @@ROWCOUNT as UpdatedRows;
"@, $connection)

    # Add parameters
    $updateCmd.Parameters.Add("@DetId", [System.Data.SqlDbType]::VarChar, 50) | Out-Null
    $updateCmd.Parameters.Add("@SisId", [System.Data.SqlDbType]::VarChar, 50) | Out-Null

    # Process users
    $processedCount = 0
    $totalUsers = $adUsers.Count

    foreach ($user in $adUsers) {
        $processedCount++
        Write-Progress -Activity "Processing Users" -Status "$processedCount of $totalUsers" -PercentComplete (($processedCount/$totalUsers) * 100)

        try {
            # Get DET username from email
            $username = $null
            $schoolEmails = @($user.otherMailbox | Where-Object { $_ -like "*@schools.vic.edu.au" })

            switch ($schoolEmails.Count) {
                0 { continue }
                1 { $username = ($schoolEmails[0] -split '@')[0].ToUpper() }
                default {
                    Write-Warning "Multiple school emails found for $($user.SamAccountName): $($schoolEmails -join ', ')"
                    continue
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($username)) {
                # Update database
                $updateCmd.Parameters["@DetId"].Value = $username
                $updateCmd.Parameters["@SisId"].Value = $user.SamAccountName

                $result = $updateCmd.ExecuteScalar()
                
                if ($result -gt 0) {
                    Write-Host "Updated $($user.SamAccountName) with DET_ID: $username"
                }
            }
        }
        catch {
            Write-Error "Error processing $($user.SamAccountName): $_"
        }
    }
}
catch {
    Write-Error "Fatal error: $_"
}
finally {
    if ($connection.State -eq 'Open') {
        $connection.Close()
    }
}

Write-Host "Processing complete"