# HaveIBeenPwned Domain Breach Scanner
# Polls HIBP API for breach data on specified domains

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\HIBP_Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').json",
    
    [Parameter(Mandatory=$false)]
    [switch]$FullBreachDetails,
    
    [Parameter(Mandatory=$false)]
    [int]$RateLimitDelayMs = 2000
)

# API Configuration
$BaseUrl = "https://haveibeenpwned.com/api/v3"
$UserAgent = "PowerShell-HIBP-Scanner/1.0"

# Headers for authenticated requests
$Headers = @{
    "hibp-api-key" = $ApiKey
    "user-agent" = $UserAgent
}

# Function to make API requests with rate limiting and error handling
function Invoke-HIBPRequest {
    param(
        [string]$Endpoint,
        [hashtable]$Headers,
        [int]$RetryCount = 3
    )
    
    $attempt = 0
    while ($attempt -lt $RetryCount) {
        try {
            Start-Sleep -Milliseconds $RateLimitDelayMs
            Write-Host "Making request to: $Endpoint" -ForegroundColor Cyan
            
            $response = Invoke-RestMethod -Uri $Endpoint -Headers $Headers -Method Get
            return $response
        }
        catch {
            $attempt++
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            switch ($statusCode) {
                401 { 
                    Write-Error "Unauthorized - Invalid API key"
                    return $null
                }
                403 { 
                    Write-Error "Forbidden - Check User-Agent header"
                    return $null
                }
                404 { 
                    Write-Host "No results found for this request" -ForegroundColor Yellow
                    return @()
                }
                429 { 
                    $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                    if ($retryAfter) {
                        $waitTime = [int]$retryAfter * 1000
                        Write-Host "Rate limited. Waiting $($retryAfter) seconds..." -ForegroundColor Yellow
                        Start-Sleep -Milliseconds $waitTime
                    } else {
                        Start-Sleep -Milliseconds ($RateLimitDelayMs * 2)
                    }
                }
                default {
                    Write-Warning "HTTP $statusCode error on attempt $attempt/$RetryCount"
                    if ($attempt -eq $RetryCount) {
                        Write-Error "Failed after $RetryCount attempts: $($_.Exception.Message)"
                        return $null
                    }
                    Start-Sleep -Milliseconds ($RateLimitDelayMs * $attempt)
                }
            }
        }
    }
}

# Function to get domain breach data
function Get-DomainBreaches {
    param([string]$Domain)
    
    Write-Host "`n=== Checking Domain Breaches for $Domain ===" -ForegroundColor Green
    
    $endpoint = "$BaseUrl/breacheddomain/$Domain"
    $result = Invoke-HIBPRequest -Endpoint $endpoint -Headers $Headers
    
    if ($result) {
        Write-Host "Found breached accounts for domain $Domain" -ForegroundColor Green
        $accountCount = ($result | Get-Member -MemberType NoteProperty).Count
        Write-Host "Total breached accounts: $accountCount" -ForegroundColor Cyan
        
        # Convert to more readable format
        $domainResults = @()
        foreach ($property in $result.PSObject.Properties) {
            $domainResults += [PSCustomObject]@{
                EmailAlias = $property.Name
                FullEmail = "$($property.Name)@$Domain"
                Breaches = $property.Value
                BreachCount = $property.Value.Count
            }
        }
        return $domainResults
    }
    else {
        Write-Host "No breached accounts found or domain not verified" -ForegroundColor Yellow
        return @()
    }
}

# Function to get all breaches (for reference)
function Get-AllBreaches {
    Write-Host "`n=== Getting All Known Breaches ===" -ForegroundColor Green
    
    $endpoint = "$BaseUrl/breaches"
    $result = Invoke-HIBPRequest -Endpoint $endpoint -Headers @{"user-agent" = $UserAgent}
    
    if ($result) {
        Write-Host "Retrieved $($result.Count) total breaches" -ForegroundColor Cyan
        return $result
    }
    return @()
}

# Function to get breach details
function Get-BreachDetails {
    param([string]$BreachName)
    
    $endpoint = "$BaseUrl/breach/$BreachName"
    return Invoke-HIBPRequest -Endpoint $endpoint -Headers @{"user-agent" = $UserAgent}
}

# Function to output detailed account breach information
function Write-AccountBreachDetails {
    param(
        [array]$BreachedAccounts,
        [string]$Domain,
        [hashtable]$BreachDetailsCache
    )
    
#    Write-Host "`n=== DETAILED BREACH REPORT FOR $Domain ===" -ForegroundColor Magenta
#    Write-Host "Format: Email | Breach Name | Breach Date | Added to HIBP Date" -ForegroundColor Cyan
#    Write-Host ("-" * 100) -ForegroundColor Gray
    
    $detailedResults = @()
    
    foreach ($account in $BreachedAccounts) {
        $fullEmail = "$($account.EmailAlias)@$Domain"
        
        foreach ($breachName in $account.Breaches) {
            # Get breach details from cache or fetch if not cached
            if (-not $BreachDetailsCache.ContainsKey($breachName)) {
                Write-Host "  → Fetching breach details for: $breachName" -ForegroundColor Yellow
                $breachDetail = Get-BreachDetails -BreachName $breachName
                if ($breachDetail) {
                    $BreachDetailsCache[$breachName] = $breachDetail
                } else {
                    Write-Host "  ✗ Failed to get details for breach: $breachName" -ForegroundColor Red
                    $BreachDetailsCache[$breachName] = $null
                    continue
                }
            }
            
            $breach = $BreachDetailsCache[$breachName]
            if ($breach) {
                $breachDate = if ($breach.BreachDate) { 
                    [DateTime]::Parse($breach.BreachDate).ToString("yyyy-MM-dd") 
                } else { 
                    "Unknown" 
                }
                
                $addedDate = if ($breach.AddedDate) { 
                    [DateTime]::Parse($breach.AddedDate).ToString("yyyy-MM-dd") 
                } else { 
                    "Unknown" 
                }
                
                # Format the output line with consistent spacing
 #               $outputLine = "{0} | {1} | {2} | {3}" -f $fullEmail.PadRight(40), $breach.Title.PadRight(25), $breachDate, $addedDate
#                Write-Host $outputLine -ForegroundColor White
                
                # Store for structured output
                $detailedResults += [PSCustomObject]@{
                    Email = $fullEmail
                    EmailAlias = $account.EmailAlias
                    Domain = $Domain
                    BreachName = $breach.Name
                    BreachTitle = $breach.Title
                    BreachDate = $breachDate
                    AddedDate = $addedDate
                    BreachDomain = $breach.Domain
                    PwnCount = $breach.PwnCount
                    Description = $breach.Description
                    DataClasses = $breach.DataClasses -join "; "
                    IsVerified = $breach.IsVerified
                    IsSensitive = $breach.IsSensitive
                }
            }
        }
    }
    
    Write-Host ("-" * 100) -ForegroundColor Gray
    Write-Host "Total breach incidents for $Domain`: $($detailedResults.Count)" -ForegroundColor Green
    Write-Host ""
    
    return $detailedResults
}

# Function to get subscription status
function Get-SubscriptionStatus {
    Write-Host "`n=== Checking Subscription Status ===" -ForegroundColor Green
    
    $endpoint = "$BaseUrl/subscription/status"
    $result = Invoke-HIBPRequest -Endpoint $endpoint -Headers $Headers
    
    if ($result) {
        Write-Host "Subscription: $($result.SubscriptionName)" -ForegroundColor Cyan
        Write-Host "Rate Limit: $($result.Rpm) requests per minute" -ForegroundColor Cyan
        Write-Host "Valid Until: $($result.SubscribedUntil)" -ForegroundColor Cyan
    }
    return $result
}

# Function to get subscribed domains
function Get-SubscribedDomains {
    Write-Host "`n=== Getting Subscribed Domains ===" -ForegroundColor Green
    
    $endpoint = "$BaseUrl/subscribeddomains"
    $result = Invoke-HIBPRequest -Endpoint $endpoint -Headers $Headers
    
    if ($result -and $result.Count -gt 0) {
        Write-Host "Found $($result.Count) subscribed domain(s):" -ForegroundColor Green
        foreach ($domain in $result) {
            $pwnCount = if ($domain.PwnCount) { $domain.PwnCount } else { "Not yet scanned" }
            $pwnCountExcluding = if ($domain.PwnCountExcludingSpamLists) { $domain.PwnCountExcludingSpamLists } else { "Not yet scanned" }
            Write-Host "  - $($domain.DomainName)" -ForegroundColor Cyan
            Write-Host "    Total Pwned Accounts: $pwnCount" -ForegroundColor White
            Write-Host "    Pwned (excluding spam): $pwnCountExcluding" -ForegroundColor White
        }
        return $result
    } else {
        Write-Host "No subscribed domains found or error retrieving domains" -ForegroundColor Yellow
        Write-Host "Make sure you have verified domains in your HIBP dashboard at https://haveibeenpwned.com/DomainSearch" -ForegroundColor Yellow
        return @()
    }
}

# Main execution
Write-Host "HaveIBeenPwned Subscribed Domains Scanner" -ForegroundColor Magenta
Write-Host "=========================================" -ForegroundColor Magenta

# Check subscription status first
$subscription = Get-SubscriptionStatus

# Get subscribed domains
$subscribedDomains = Get-SubscribedDomains

if ($subscribedDomains.Count -eq 0) {
    Write-Host "`nNo subscribed domains found. Exiting." -ForegroundColor Red
    Write-Host "Please verify domains in your HIBP dashboard: https://haveibeenpwned.com/DomainSearch" -ForegroundColor Yellow
    exit 1
}

# Extract domain names for processing
$domains = $subscribedDomains | ForEach-Object { $_.DomainName }
Write-Host "`nWill scan the following domains: $($domains -join ', ')" -ForegroundColor Green

# Initialize results object
$results = @{
    ScanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Subscription = $subscription
    SubscribedDomains = $subscribedDomains
    Domains = @{}
    AllBreaches = @()
    DetailedBreachReports = @()
    Summary = @{}
}

# Cache for breach details to avoid duplicate API calls
$breachDetailsCache = @{}

# Get all breaches for reference
Write-Host "`nGetting reference list of all breaches..." -ForegroundColor Cyan
$allBreaches = Get-AllBreaches
$results.AllBreaches = $allBreaches

# Process each domain
foreach ($domain in $domains) {
    Write-Host "`n" + "="*50 -ForegroundColor Magenta
    Write-Host "Processing Domain: $domain" -ForegroundColor Magenta
    Write-Host "="*50 -ForegroundColor Magenta
    
    $domainData = @{
        Domain = $domain
        SubscriptionInfo = ($subscribedDomains | Where-Object { $_.DomainName -eq $domain })
        BreachedAccounts = @()
        UniqueBreaches = @()
        TotalAccounts = 0
        TotalBreaches = 0
        DetailedBreachReport = @()
    }
    
    # Get domain breaches
    $breachedAccounts = Get-DomainBreaches -Domain $domain
    $domainData.BreachedAccounts = $breachedAccounts
    $domainData.TotalAccounts = $breachedAccounts.Count
    
    # Get unique breaches for this domain
    $uniqueBreaches = $breachedAccounts.Breaches | Sort-Object -Unique
    $domainData.UniqueBreaches = $uniqueBreaches
    $domainData.TotalBreaches = $uniqueBreaches.Count
    
    # Generate detailed breach report for each account
    if ($breachedAccounts.Count -gt 0) {
        $detailedReport = Write-AccountBreachDetails -BreachedAccounts $breachedAccounts -Domain $domain -BreachDetailsCache $breachDetailsCache
        $domainData.DetailedBreachReport = $detailedReport
        $results.DetailedBreachReports += $detailedReport
    }
    
    $results.Domains[$domain] = $domainData
    
    # Display summary for this domain
    Write-Host "`nDomain Summary for $domain`:" -ForegroundColor Yellow
    Write-Host "  Breached Accounts: $($domainData.TotalAccounts)" -ForegroundColor White
    Write-Host "  Unique Breaches: $($domainData.TotalBreaches)" -ForegroundColor White
    Write-Host "  Total Breach Incidents: $($domainData.DetailedBreachReport.Count)" -ForegroundColor White
    if ($domainData.TotalBreaches -gt 0) {
        Write-Host "  Breach Names: $($uniqueBreaches -join ', ')" -ForegroundColor White
    }
}

# Generate overall summary
$totalAccounts = ($results.Domains.Values | Measure-Object -Property TotalAccounts -Sum).Sum
$totalBreachIncidents = $results.DetailedBreachReports.Count
$allUniqueBreaches = $results.Domains.Values.UniqueBreaches | Sort-Object -Unique

$results.Summary = @{
    TotalDomains = $domains.Count
    TotalSubscribedDomains = $subscribedDomains.Count
    TotalBreachedAccounts = $totalAccounts
    TotalBreachIncidents = $totalBreachIncidents
    TotalUniqueBreaches = $allUniqueBreaches.Count
    UniqueBreachNames = $allUniqueBreaches
    DomainsScanned = $domains
}

# Display final summary
Write-Host "`n" + "="*50 -ForegroundColor Green
Write-Host "FINAL SUMMARY" -ForegroundColor Green
Write-Host "="*50 -ForegroundColor Green
Write-Host "Subscribed Domains: $($results.Summary.TotalSubscribedDomains)" -ForegroundColor White
Write-Host "Domains Scanned: $($results.Summary.TotalDomains)" -ForegroundColor White
Write-Host "Domain Names: $($results.Summary.DomainsScanned -join ', ')" -ForegroundColor Cyan
Write-Host "Total Breached Accounts: $($results.Summary.TotalBreachedAccounts)" -ForegroundColor White
Write-Host "Total Breach Incidents: $($results.Summary.TotalBreachIncidents)" -ForegroundColor White
Write-Host "Total Unique Breaches: $($results.Summary.TotalUniqueBreaches)" -ForegroundColor White

if ($results.Summary.TotalUniqueBreaches -gt 0) {
    Write-Host "Breaches Found: $($results.Summary.UniqueBreachNames -join ', ')" -ForegroundColor Yellow
}

# Save results to JSON file
Write-Host "`nSaving results to: $OutputPath" -ForegroundColor Cyan
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8

# Also save detailed breach report as CSV
$csvPath = $OutputPath -replace '\.json', '_DetailedReport.csv'

Write-Host "`nScan completed successfully!" -ForegroundColor Green
Write-Host "Results saved to: $OutputPath" -ForegroundColor Cyan
if ($results.DetailedBreachReports.Count -gt 0) {
    Write-Host "Detailed CSV report saved to: $csvPath" -ForegroundColor Cyan
}

<#
# Display instructions for next steps
Write-Host "`n" + "="*50 -ForegroundColor Blue
Write-Host "NEXT STEPS" -ForegroundColor Blue
Write-Host "="*50 -ForegroundColor Blue
Write-Host "1. Review the JSON output file for complete results" -ForegroundColor White
Write-Host "2. Open the CSV file for detailed breach information per account" -ForegroundColor White
Write-Host "3. Add more domains to your HIBP dashboard if needed" -ForegroundColor White
Write-Host "4. Consider implementing regular monitoring for new breaches" -ForegroundColor White
Write-Host "5. Review breach dates to prioritize remediation efforts" -ForegroundColor White
Write-Host "6. Visit https://haveibeenpwned.com/DomainSearch to manage subscribed domains" -ForegroundColor White

# Display sample of detailed results if any found
if ($results.DetailedBreachReports.Count -gt 0) {
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "SAMPLE DETAILED RESULTS (First 10 entries)" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    Write-Host "Format: Email | Breach Name | Breach Date | Added Date" -ForegroundColor Yellow
    Write-Host ("-" * 100) -ForegroundColor Gray
    
    $sampleResults = $results.DetailedBreachReports | Select-Object -First 10
    foreach ($result in $sampleResults) {
        $outputLine = "{0} | {1} | {2} | {3}" -f $result.Email.PadRight(40), $result.BreachTitle.PadRight(25), $result.BreachDate, $result.AddedDate
        Write-Host $outputLine -ForegroundColor White
    }
    
    Write-Host ("-" * 100) -ForegroundColor Gray
    if ($results.DetailedBreachReports.Count -gt 10) {
        Write-Host "... and $($results.DetailedBreachReports.Count - 10) more entries in the full report files" -ForegroundColor Yellow
    }
    Write-Host "Complete detailed results available in JSON and CSV files" -ForegroundColor Green
} else {
    Write-Host "`nNo breached accounts found across all subscribed domains." -ForegroundColor Green
}#>

if ($results.DetailedBreachReports.Count -gt 0) {
    Write-Host "Saving detailed breach report to: $csvPath" -ForegroundColor Cyan
    $results.DetailedBreachReports | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
}

Write-Host "`nScan completed successfully!" -ForegroundColor Green
Write-Host "Results saved to: $OutputPath" -ForegroundColor Cyan

# Display instructions for next steps
Write-Host "`n" + "="*50 -ForegroundColor Blue
Write-Host "NEXT STEPS" -ForegroundColor Blue
Write-Host "="*50 -ForegroundColor Blue
Write-Host "1. Review the JSON output file for detailed results" -ForegroundColor White
Write-Host "2. Consider running individual account searches for specific emails" -ForegroundColor White
Write-Host "3. Check if domains are verified in your HIBP dashboard" -ForegroundColor White
Write-Host "4. Set up regular monitoring for new breaches" -ForegroundColor White