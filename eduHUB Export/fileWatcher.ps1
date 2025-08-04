param(
    [Parameter(Mandatory=$true)]
    [string]$SiteCode,
    
    [Parameter(Mandatory=$true)]
    [string[]]$WatchedFileTypes,
    
    [Parameter(Mandatory=$true)]
    [string]$WatchPath,
    
    [Parameter(Mandatory=$true)]
    [string]$ProcessingScript,
    
    [int]$DebounceSeconds = 30,
    [int]$SettlingDelaySeconds = 10
)

# Build regex pattern dynamically
$typePattern = "(" + ($WatchedFileTypes -join "|") + ")"
$filePattern = "^${SiteCode}_${typePattern}(_D)?\.csv$"

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $WatchPath
$watcher.Filter = "*.csv"
$watcher.EnableRaisingEvents = $true

$lastProcessTime = [DateTime]::MinValue

Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action {
    $fileName = [System.IO.Path]::GetFileName($Event.SourceEventArgs.FullPath)
    
    if ($fileName -match $using:filePattern) {
        $now = Get-Date
        if (($now - $script:lastProcessTime).TotalSeconds -gt $using:DebounceSeconds) {
            $script:lastProcessTime = $now
            
            Write-Host "Detected relevant file: $fileName"
            Start-Sleep $using:SettlingDelaySeconds
            
            Start-Process PowerShell -ArgumentList "-File '$using:ProcessingScript'" -WindowStyle Hidden
        }
    }
}