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

$sidFilter = "(samAccountName=$($activeStudents[0].SIS_ID))"
foreach ($student in $activeStudents | Select-Object -Skip 1) {
    $sidFilter += " -or (samAccountName -eq '$($student.SIS_ID)')"
}


<#
foreach ($user in $adUsers) {
    $username = $null
    if ($user.otherMailbox) {
        if ($user.otherMailbox.Count -gt 1) {
            # Filter for school email addresses
            $schoolEmails = $user.otherMailbox | Where-Object { $_ -like "*@schools.vic.edu.au" }
            
            if ($schoolEmails.Count -eq 1) {
                # One school email found
                $username = ($schoolEmails -split '@')[0].ToUpper()
                Write-Host "$($user.SamAccountName) | $username"
            }
            elseif ($schoolEmails.Count -gt 1) {
                # Multiple school emails found - error
                Write-Error "$($user.SamAccountName) | Multiple school emails found for $($user.SamAccountName): $($schoolEmails -join ', ')"
            }
        }
        elseif ($user.otherMailbox -like "*@schools.vic.edu.au") {
            # Single email that is a school email
            $username = ($user.otherMailbox -split '@')[0].ToUpper()
        }

        if (-not [string]::IsNullOrWhiteSpace($username)) {
            try {
                # Get existing record before making changes
                $existingRecord = Invoke-Sqlcmd -ConnectionString $connectionString -Query "SELECT * FROM $table WHERE SIS_ID = '$($user.SamAccountName)'"
                Write-Host "TESTING"
                $query = @"
                IF EXISTS (
                    SELECT 1 FROM $table 
                    WHERE SIS_ID = '$($user.SamAccountName)' 
                    AND (DET_ID IS NULL OR DET_ID != '$username')
                )
                BEGIN
                    UPDATE $table 
                    SET DET_ID = '$username', 
                        LW_DATE = GETDATE(),
                        LW_USER = '$(($env:USERNAME).ToUpper())'
                    WHERE SIS_ID = '$($user.SamAccountName)'
                
                    SELECT 'Updated' as Status
                END
                ELSE
                    SELECT 'No Change' as Status
"@
                $result = Invoke-Sqlcmd -ConnectionString $connectionString -Query $query
                
                if ($result.Status -eq 'Updated') {
                    # Log to user_changes table
                    $logQuery = @"
                    INSERT INTO user_changes (change_datetime, sis_id, field_name, old_value, new_value)
                    VALUES (
                        GETDATE(),
                        '$($user.SamAccountName)',
                        'DET_ID',
                        $(if ([string]::IsNullOrWhiteSpace($existingRecord.DET_ID)) { "NULL" } else { "'$(Optimize-SQLString($existingRecord.DET_ID))'" }),
                        '$username'
                    )
"@
                    Invoke-Sqlcmd -ConnectionString $connectionString -Query $logQuery
                    
                    Write-Host "Updated $($user.SamAccountName) with DET_ID: $username"
                }
            }
            catch {
                Write-Error "Failed to update database for $($user.SamAccountName): $_"
            }
        }
        else {
            $query = @"
                UPDATE $table 
                SET DET_ID = '$username', 
                    LW_DATE = GETDATE(),
                    LW_USER = '$(($env:USERNAME).ToUpper())'
                WHERE SIS_ID = '$($user.SamAccountName)'
"@
                Invoke-Sqlcmd -ConnectionString $connectionString -Query $query
                Write-Host "Updated $($user.SamAccountName) with DET_ID: $username"
        }
    }
}#>