Import-Module SqlServer

# Import configuration
$config = Import-PowerShellDataFile -Path "$PSScriptRoot\Config.psd1"

# Database connection parameters from config
$server = $config.server
$database = $config.database
$connectionString = "Server=$server;Database=$database;Integrated Security=True;TrustServerCertificate=True;"

# Script-specific parameters
$tableName = "Students"
$csvPath = "\\7893FS01\eduhub$\CasesStudents.csv"
$fullSync = $true
$processLastHours = 24

function Convert-ToSqlDate {
    param([string]$dateString)
    if ([string]::IsNullOrWhiteSpace($dateString)) { return $null }
    try {
        return [DateTime]::ParseExact($dateString, "d/MM/yyyy h:mm:ss tt", $null)
    } catch {
        Write-Warning "Invalid date: $dateString"
        return $null
    }
}

# Function to log changes to user_changes table
function Log-UserChange {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$SisId,
        [string]$FieldName,
        [string]$OldValue,
        [string]$NewValue
    )
    
    $logCmd = New-Object System.Data.SqlClient.SqlCommand(@"
        INSERT INTO user_changes (change_datetime, sis_id, field_name, old_value, new_value)
        VALUES (GETDATE(), @SisId, @FieldName, @OldValue, @NewValue)
"@, $Connection)
    
    $logCmd.Parameters.AddWithValue("@SisId", $SisId) | Out-Null
    $logCmd.Parameters.AddWithValue("@FieldName", $FieldName) | Out-Null
    $logCmd.Parameters.AddWithValue("@OldValue", [DBNull]::Value) | Out-Null  # Default to NULL
    $logCmd.Parameters.AddWithValue("@NewValue", [DBNull]::Value) | Out-Null  # Default to NULL
    
    if ($OldValue -ne $null) { $logCmd.Parameters["@OldValue"].Value = $OldValue }
    if ($NewValue -ne $null) { $logCmd.Parameters["@NewValue"].Value = $NewValue }
    
    $logCmd.ExecuteNonQuery() | Out-Null
}

# Read CSV
$csvData = Import-Csv -Path $csvPath | Sort-Object -Property SIS_ID
$headers = $csvData[0].PSObject.Properties.Name
<#if (!$fullSync) {
    # Get most recent LW_DATE from database
    $recentDateQuery = "SELECT MAX(LW_DATE) as MaxDate FROM $tableName"
    $mostRecentDate = Invoke-Sqlcmd -ConnectionString $connectionString -Query $recentDateQuery 
    
    if ($mostRecentDate.MaxDate) {…}
}#>

# Create SQL Connection
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$connection.Open()

try {
    foreach ($row in $csvData) {
        try {
            # Process dates
            $dates = @{
                START = Convert-ToSqlDate $row.START
                BIRTHDATE = Convert-ToSqlDate $row.BIRTHDATE
                LW_DATE = Convert-ToSqlDate $row.LW_DATE
                FINISH = Convert-ToSqlDate $row.FINISH
            }
            
            # Process LW_USER - remove domain prefix
            $lwUser = $row.LW_USER -replace '^EDU001\\', ''
            
            # Check if user exists and get current values
            $userCheckCmd = New-Object System.Data.SqlClient.SqlCommand(
                "SELECT * FROM $tableName WHERE SIS_ID = @SisId", $connection)
            $userCheckCmd.Parameters.AddWithValue("@SisId", $row.SIS_ID) | Out-Null
            
            $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($userCheckCmd)
            $existingUserData = New-Object System.Data.DataTable
            $adapter.Fill($existingUserData) | Out-Null
            
            if ($existingUserData.Rows.Count -gt 0) {
                $existingUser = $existingUserData.Rows[0]
                # Check if update is needed based on LW_DATE
                if ($dates.LW_DATE -gt $existingUser.LW_DATE) {
                    # Execute update command
                    $updateCmd = New-Object System.Data.SqlClient.SqlCommand(@"
UPDATE $tableName SET
    START = @Start,
    BIRTHDATE = @BirthDate,
    LW_DATE = @LwDate,
    LW_USER = @LwUser,
    FINISH = @Finish,
    SURNAME = @Surname,
    FIRST_NAME = @FirstName,
    SECOND_NAME = @SecondName,
    PREF_NAME = @PrefName,
    STATUS = @Status,
    SCHOOL_YEAR = @SchoolYear,
    HOME_GROUP = @HomeGroup,
    FAMILY = @Family,
    CONTACT_A = @ContactA,
    DB_DATE = GETDATE()
WHERE SIS_ID = @SisId
"@, $connection)

                    # Add parameters
                    $updateCmd.Parameters.AddWithValue("@SisId", $row.SIS_ID) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@Start", $dates.START) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@BirthDate", $dates.BIRTHDATE) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@LwDate", $dates.LW_DATE) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@LwUser", $lwUser) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@Finish", $dates.FINISH) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@Surname", $row.SURNAME) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@FirstName", $row.FIRST_NAME) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@SecondName", $row.SECOND_NAME) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@PrefName", $row.PREF_NAME) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@Status", $row.STATUS) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@SchoolYear", $row.SCHOOL_YEAR) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@HomeGroup", $row.HOME_GROUP) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@Family", $row.FAMILY) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@ContactA", $row.CONTACT_A) | Out-Null

                    $updateCmd.ExecuteNonQuery() | Out-Null
                    
                    # Log changes for each changed field
                    $fieldsToCheck = @{
                        "START" = @{ New = $dates.START; Old = $existingUser.START }
                        "BIRTHDATE" = @{ New = $dates.BIRTHDATE; Old = $existingUser.BIRTHDATE }
                        "LW_DATE" = @{ New = $dates.LW_DATE; Old = $existingUser.LW_DATE }
                        "LW_USER" = @{ New = $lwUser; Old = $existingUser.LW_USER }
                        "FINISH" = @{ New = $dates.FINISH; Old = $existingUser.FINISH }
                        "SURNAME" = @{ New = $row.SURNAME; Old = $existingUser.SURNAME }
                        "FIRST_NAME" = @{ New = $row.FIRST_NAME; Old = $existingUser.FIRST_NAME }
                        "SECOND_NAME" = @{ New = $row.SECOND_NAME; Old = $existingUser.SECOND_NAME }
                        "PREF_NAME" = @{ New = $row.PREF_NAME; Old = $existingUser.PREF_NAME }
                        "STATUS" = @{ New = $row.STATUS; Old = $existingUser.STATUS }
                        "SCHOOL_YEAR" = @{ New = $row.SCHOOL_YEAR; Old = $existingUser.SCHOOL_YEAR }
                        "HOME_GROUP" = @{ New = $row.HOME_GROUP; Old = $existingUser.HOME_GROUP }
                        "FAMILY" = @{ New = $row.FAMILY; Old = $existingUser.FAMILY }
                        "CONTACT_A" = @{ New = $row.CONTACT_A; Old = $existingUser.CONTACT_A }
                    }
                    
                    foreach ($field in $fieldsToCheck.Keys) {
                        $newValue = $fieldsToCheck[$field].New
                        $oldValue = $fieldsToCheck[$field].Old
                        
                        # Only log if there's an actual change
                        if (($newValue -ne $oldValue) -or 
                            ([string]::IsNullOrEmpty($newValue) -xor [string]::IsNullOrEmpty($oldValue))) {
                            Log-UserChange -Connection $connection -SisId $row.SIS_ID -FieldName $field `
                                          -OldValue $oldValue -NewValue $newValue
                        }
                    }
                
                    Write-Host "Updated User SIS_ID: $($row.SIS_ID)|$($row.FAMILY)"
                }
            }
            else {
                $insertCmd = New-Object System.Data.SqlClient.SqlCommand(@"
INSERT INTO $tableName (
    SIS_ID, START, BIRTHDATE, LW_DATE, LW_USER, FINISH,
    SURNAME, FIRST_NAME, SECOND_NAME, PREF_NAME,
    STATUS, SCHOOL_YEAR, HOME_GROUP, FAMILY, CONTACT_A, DB_DATE
) VALUES (
    @SisId, @Start, @BirthDate, @LwDate, @LwUser, @Finish,
    @Surname, @FirstName, @SecondName, @PrefName,
    @Status, @SchoolYear, @HomeGroup, @Family, @ContactA, GETDATE()
)
"@, $connection)

                # Add parameters
                $insertCmd.Parameters.AddWithValue("@SisId", $row.SIS_ID) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Start", $dates.START) | Out-Null
                $insertCmd.Parameters.AddWithValue("@BirthDate", $dates.BIRTHDATE) | Out-Null
                $insertCmd.Parameters.AddWithValue("@LwDate", $dates.LW_DATE) | Out-Null
                $insertCmd.Parameters.AddWithValue("@LwUser", $lwUser) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Finish", $dates.FINISH) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Surname", $row.SURNAME) | Out-Null
                $insertCmd.Parameters.AddWithValue("@FirstName", $row.FIRST_NAME) | Out-Null
                $insertCmd.Parameters.AddWithValue("@SecondName", $row.SECOND_NAME) | Out-Null
                $insertCmd.Parameters.AddWithValue("@PrefName", $row.PREF_NAME) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Status", $row.STATUS) | Out-Null
                $insertCmd.Parameters.AddWithValue("@SchoolYear", $row.SCHOOL_YEAR) | Out-Null
                $insertCmd.Parameters.AddWithValue("@HomeGroup", $row.HOME_GROUP) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Family", $row.FAMILY) | Out-Null
                $insertCmd.Parameters.AddWithValue("@ContactA", $row.CONTACT_A) | Out-Null

                $insertCmd.ExecuteNonQuery() | Out-Null

                # Log new user creation with special "user" field name
                Log-UserChange -Connection $connection -SisId $row.SIS_ID -FieldName "user" `
                              -OldValue "new_user" -NewValue $null

                Write-Host "New User Added SIS_ID: $($row.SIS_ID)|$($row.FAMILY)"
            }
        }
        catch {
            Write-Error "Error processing SIS_ID $($row.SIS_ID): $_"
        }
    }
}
finally {
    if ($connection.State -eq 'Open') {
        $connection.Close()
    }
}

Write-Host "Processing complete"