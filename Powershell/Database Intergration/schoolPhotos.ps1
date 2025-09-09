param (
        [Parameter(Mandatory=$true)]
        [string]$photoDirectory,
        [Parameter(Mandatory=$true)]
        [string]$dbServer,
        [Parameter(Mandatory=$true)]
        [string]$dbName,
        [string]$formatName
    )


#Set format name to unknown unless specified
if ([string]::IsNullOrWhiteSpace($formatName))
{
    $formatName = "Unknown"
}

#Test that the photo directory exists
if (-not (Test-Path $photoDirectory -PathType Container))
{
    Write-Error "Supplied photo path is not a valid directory or does not exists"
    Exit
}

# Import required assemblies
Add-Type -AssemblyName System.Drawing

# Add Required Modules
Import-Module SQLServer

# Function to get image details
function Get-ImageDetails {
    param (
        [string]$imagePath
    )
    
    try {
        # Get basic image properties
        $image = [System.Drawing.Image]::FromFile($imagePath)
        $width = $image.Width
        $height = $image.Height
        $dpiX = $image.HorizontalResolution
        $dpiY = $image.VerticalResolution
        $photoDate = (Get-Item $imagePath).LastWriteTime
        $fileSize = (Get-Item $imagePath).Length

        # Create custom object with details
        $details = [PSCustomObject]@{
            FilePath = $imagePath
            Width = $width
            Height = $height
            DpiX = $dpiX
            DpiY = $dpiY
            PhotoDate = $photoDate
            FileSize = $fileSize
        }
        
        $image.Dispose()
        return $details
    }
    catch {
        Write-Error "Error processing $imagePath : $($_.Exception.Message)"
        return $null
    }
}

function Add-PhotoToDatabase {
    param (
        [Parameter(Mandatory=$true)]
        [string]$sisId,
        [Parameter(Mandatory=$true)]
        [datetime]$photoDate,
        [int]$width,
        [int]$height,
        [float]$dpiX,
        [float]$dpiY,
        [string]$formatName,
        [Parameter(Mandatory=$true)]
        [byte[]]$photo,
        [Parameter(Mandatory=$true)]
        [string]$fileName,
        [Parameter(Mandatory=$true)]
        [long]$fileSize
    )

    # Database connection string
    $connectionString = "Server=$dbServer;Database=$dbName;Integrated Security=True;TrustServerCertificate=True;"
    
    try {
        # Create connection
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        
        # Check if record exists
        $checkQuery = "SELECT COUNT(*) FROM [Photos] WHERE SIS_ID = @SisId AND PHOTO_DATE = @PhotoDate AND FORMAT_NAME = @FormatName"
        $checkCommand = New-Object System.Data.SqlClient.SqlCommand($checkQuery, $connection)
        $checkCommand.Parameters.Add("@SisId", [System.Data.SqlDbType]::VarChar, 50).Value = $sisId
        $checkCommand.Parameters.Add("@FormatName", [System.Data.SqlDbType]::VarChar, 50).Value = $formatName
        $checkCommand.Parameters.Add("@PhotoDate", [System.Data.SqlDbType]::Date).Value = $photoDate.Date
        
        $connection.Open()
        $recordExists = $checkCommand.ExecuteScalar() -gt 0
        
        if ($recordExists) {
            Write-Verbose "Photo already exists for SIS ID: $sisId on date: $($photoDate.ToString('yyyy-MM-dd'))"
            return $false
        }
        
        # Insert new record using parameterized query
        $insertQuery = @"
INSERT INTO [Photos] (SIS_ID, PHOTO_DATE, WIDTH, HEIGHT, DPI_X, DPI_Y, FORMAT_NAME, PHOTO, FILE_SIZE)
VALUES (@SisId, @PhotoDate, @Width, @Height, @DpiX, @DpiY, @FormatName, @Photo, @FileSize)
"@
        
        $insertCommand = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        
        # Add parameters with proper data types
        $insertCommand.Parameters.Add("@SisId", [System.Data.SqlDbType]::VarChar, 50).Value = $sisId
        $insertCommand.Parameters.Add("@PhotoDate", [System.Data.SqlDbType]::Date).Value = $photoDate.Date
        $insertCommand.Parameters.Add("@Width", [System.Data.SqlDbType]::Int).Value = $width
        $insertCommand.Parameters.Add("@Height", [System.Data.SqlDbType]::Int).Value = $height
        $insertCommand.Parameters.Add("@DpiX", [System.Data.SqlDbType]::Float).Value = $dpiX
        $insertCommand.Parameters.Add("@DpiY", [System.Data.SqlDbType]::Float).Value = $dpiY
        $insertCommand.Parameters.Add("@FormatName", [System.Data.SqlDbType]::VarChar, 50).Value = $formatName
        $insertCommand.Parameters.Add("@Photo", [System.Data.SqlDbType]::VarBinary, -1).Value = $photo
        $insertCommand.Parameters.Add("@FileSize", [System.Data.SqlDbType]::BigInt).Value = $fileSize
        
        # Execute the insert
        $rowsAffected = $insertCommand.ExecuteNonQuery()
        
        if ($rowsAffected -gt 0) {
            $fileSizeKB = [math]::Round($fileSize / 1024, 2)
            Write-Information "Successfully added photo for SIS ID: $sisId dated $(Get-Date $photoDate.Date -UFormat "%Y-%m-%d") - Size: $fileSizeKB KB" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "No rows were inserted for SIS ID: $sisId"
            return $false
        }
    }
    catch {
        Write-Error "Error adding photo for SIS ID $sisId : $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
    }
}

# Function to retrieve and save photo from database
function Get-PhotoFromDatabase {
    param (
        [Parameter(Mandatory=$true)]
        [string]$sisId,
        [Parameter(Mandatory=$true)]
        [datetime]$photoDate,
        [Parameter(Mandatory=$true)]
        [string]$outputPath
    )
    
    $connectionString = "Server=$dbServer;Database=$dbName;Integrated Security=True;TrustServerCertificate=True;"
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        
        $selectQuery = "SELECT PHOTO, FORMAT_NAME, FILE_SIZE FROM [Photos] WHERE SIS_ID = @SisId AND PHOTO_DATE = @PhotoDate"
        $selectCommand = New-Object System.Data.SqlClient.SqlCommand($selectQuery, $connection)
        $selectCommand.Parameters.Add("@SisId", [System.Data.SqlDbType]::VarChar, 50).Value = $sisId
        $selectCommand.Parameters.Add("@PhotoDate", [System.Data.SqlDbType]::Date).Value = $photoDate.Date
        
        $connection.Open()
        $reader = $selectCommand.ExecuteReader()
        
        if ($reader.Read()) {
            $photoData = $reader["PHOTO"]
            $formatName = $reader["FORMAT_NAME"]
            $fileSize = $reader["FILE_SIZE"]
            
            # Create output directory if it doesn't exist
            $outputDir = [System.IO.Path]::GetDirectoryName($outputPath)
            if (-not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force
            }
            
            # Write photo data to file
            [System.IO.File]::WriteAllBytes($outputPath, $photoData)
            $fileSizeKB = [math]::Round($fileSize / 1024, 2)
            Write-Information "Photo retrieved and saved to: $outputPath (Size: $fileSizeKB KB)" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "No photo found for SIS ID: $sisId on date: $($photoDate.ToString('yyyy-MM-dd'))"
            return $false
        }
    }
    catch {
        Write-Error "Error retrieving photo for SIS ID $sisId : $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
    }
}

# Main execution
Write-Information "Starting photo processing..."

# Get all JPG files recursively
$jpgFiles = Get-ChildItem -Path $photoDirectory -Include *.jpg,*.jpeg -Recurse -File

Write-Information "Found $($jpgFiles.Count) image files to process"

$successCount = 0
$errorCount = 0
$skippedCount = 0
$totalSize = 0

# Process each file
foreach ($file in $jpgFiles) {
    Write-Verbose "Processing: $($file.Name)"
    
    $imageDetails = Get-ImageDetails -imagePath $file.FullName
    if ($imageDetails) {
        # Extract SIS_ID from the filename (minus the extension)
        $sisId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

        # Read the photo as a byte array
        $photo = [System.IO.File]::ReadAllBytes($file.FullName)
        
        # Add the photo to the database if it does not exist
        $result = Add-PhotoToDatabase -sisId $sisId -photoDate $imageDetails.PhotoDate -width $imageDetails.Width -height $imageDetails.Height -dpiX $imageDetails.DpiX -dpiY $imageDetails.DpiY -formatName $formatName -photo $photo -fileName $file.Name -fileSize $imageDetails.FileSize
        
        if ($result) {
            $successCount++
            $totalSize += $imageDetails.FileSize
        } else {
            $skippedCount++
        }
    } else {
        $errorCount++
    }
}

$totalSizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Information "`nProcessing completed!" -ForegroundColor Cyan
Write-Information "Successfully added: $successCount" -ForegroundColor Green
Write-Information "Skipped (already exist): $skippedCount" -ForegroundColor Yellow
Write-Information "Errors: $errorCount" -ForegroundColor Red
Write-Information "Total size processed: $totalSizeMB MB" -ForegroundColor Cyan

# Example of how to retrieve a photo
# Uncomment and modify as needed:
# $testSisId = "ABC0001"  # Replace with actual SIS ID
# $testDate = Get-Date "2017-01-01"  # Replace with actual photo date
# $outputPath = "C:\temp\retrieved_photo.jpg"
# Get-PhotoFromDatabase -sisId $testSisId -photoDate $testDate -outputPath $outputPath