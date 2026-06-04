<#
.SYNOPSIS
    Analyzes IIS W3C log files on the current server and produces selected analysis reports.

.DESCRIPTION
    Scans copied IIS W3C .log files from a specified folder on the local server,
    normalizes API paths, filters out Azure Load Balancer Agent traffic, and outputs
    one or more of the following reports based on your selection:

        [1] Traffic by Day        - Date | Total
        [2] Traffic by Hour       - DateHour | Total
        [3] Status Categories     - 2xx / 3xx / 4xx / 5xx counts
        [4] Top 30 Failed         - NormalizedUri + status code + hit count
        [5] Top 30 Slowest        - NormalizedUri + Hits / AvgMs / P95Ms / MaxMs
        [A] All reports

    Incremental runs: tracks the last run timestamp and only processes new log
    entries on each subsequent run. Run once a week — picks up from last run.

    Output: saves a timestamped report transcript alongside the analysis results.

    URI normalization rules:
        Numeric segments  =>  {id}     e.g. /api/orders/123  => /api/orders/{id}
        GUID segments     =>  {guid}
        Long tokens       =>  {token}

.NOTES
    Author  : Janardhan Matheti
    Version : 2.1
    Updated : 06-04-2026
    Requires: PowerShell 5.1 or later. No external modules needed.
              Point to a COPY of IIS logs — not the live folder IIS writes to.
              Log files must be in standard IIS W3C format with a #Fields: header.
              Times are used as-is from the log files (no timezone conversion).
#>

[CmdletBinding()]
param ()

$serverName = $env:COMPUTERNAME

Write-Host ""
Write-Host "=== IIS Local Log Analysis ===" -ForegroundColor Cyan
Write-Host "Server  : $serverName"
Write-Host "Analyzes copied IIS W3C log files and produces selected analysis reports."
Write-Host ""

# -- Guided input --------------------------------------------------------------

# IIS log folder
do {
    $logFolder = Read-Host "Enter the path to the copied IIS log folder"
    if ([string]::IsNullOrWhiteSpace($logFolder)) {
        Write-Warning "Log folder path cannot be empty."
    } elseif (-not (Test-Path $logFolder)) {
        Write-Warning "Folder not found: $logFolder"
        $logFolder = $null
    }
} while ([string]::IsNullOrWhiteSpace($logFolder))

# Reports output folder
$defaultReportsFolder = Join-Path $logFolder "Reports"
Write-Host ""
Write-Host "Default reports folder: $defaultReportsFolder"
$reportsInput  = Read-Host "Reports output folder (press Enter to use default)"
$reportsFolder = if ([string]::IsNullOrWhiteSpace($reportsInput)) { $defaultReportsFolder } else { $reportsInput.Trim() }

if (-not (Test-Path $reportsFolder)) {
    New-Item -ItemType Directory -Path $reportsFolder -Force | Out-Null
    Write-Host "Created reports folder: $reportsFolder"
}

# -- Report selection ----------------------------------------------------------
Write-Host ""
Write-Host "Available reports:" -ForegroundColor Cyan
Write-Host "  [1] Traffic by Day"
Write-Host "  [2] Traffic by Hour"
Write-Host "  [3] Status Categories  (2xx / 3xx / 4xx / 5xx)"
Write-Host "  [4] Top 30 Failed Endpoints"
Write-Host "  [5] Top 30 Slowest Endpoints"
Write-Host "  [A] All reports"
Write-Host ""
Write-Host "You can select multiple reports — e.g. enter: 1,3,5  or  A"

$reportInput = Read-Host "Select reports to run (default: A — press Enter for all)"
if ([string]::IsNullOrWhiteSpace($reportInput) -or $reportInput.Trim().ToUpper() -eq "A") {
    $selectedReports = @(1, 2, 3, 4, 5)
} else {
    $selectedReports = $reportInput -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^[1-5]$' } |
        ForEach-Object { [int]$_ } |
        Sort-Object -Unique
    if ($selectedReports.Count -eq 0) {
        Write-Warning "No valid reports selected. Defaulting to all."
        $selectedReports = @(1, 2, 3, 4, 5)
    }
}

$reportLabels = @{
    1 = "Traffic by Day"
    2 = "Traffic by Hour"
    3 = "Status Categories"
    4 = "Top 30 Failed Endpoints"
    5 = "Top 30 Slowest Endpoints"
}

Write-Host ""
Write-Host "Reports selected:" -ForegroundColor Cyan
$selectedReports | ForEach-Object { Write-Host ("  [{0}] {1}" -f $_, $reportLabels[$_]) }

# Minimum hits — only ask if report 5 is selected
$minHits = 20
if ($selectedReports -contains 5) {
    $minHitsInput = Read-Host "Minimum hits for slowest endpoints table (default: 20 — press Enter to use default)"
    if (-not [string]::IsNullOrWhiteSpace($minHitsInput)) {
        $parsed = 0
        if ([int]::TryParse($minHitsInput.Trim(), [ref]$parsed) -and $parsed -gt 0) {
            $minHits = $parsed
        } else {
            Write-Warning "Invalid value '$minHitsInput'. Using default: 20"
        }
    }
}

# Export CSVs?
$exportInput = Read-Host "Export results to CSV files in the reports folder? (Y/N — default: N)"
$exportCsv   = $exportInput -match '^[Yy]$'

# -- Last run state ------------------------------------------------------------
$stateFile     = Join-Path $reportsFolder "iis-lastrun-$serverName.txt"
$lastRunTime   = $null
$isIncremental = $false

if (Test-Path $stateFile) {
    $lastRunRaw  = Get-Content $stateFile -Raw
    $parsedLast  = [datetime]::MinValue
    if ([datetime]::TryParse($lastRunRaw.Trim(), [ref]$parsedLast) -and $parsedLast -ne [datetime]::MinValue) {
        $lastRunTime   = $parsedLast
        $isIncremental = $true
    }
}

Write-Host ""
Write-Host "Settings:" -ForegroundColor Cyan
Write-Host "  Server         : $serverName"
Write-Host "  Log folder     : $logFolder"
Write-Host "  Reports folder : $reportsFolder"
Write-Host ("  Reports        : {0}" -f ($selectedReports -join ', '))
if ($selectedReports -contains 5) {
    Write-Host "  Min hits       : $minHits"
}
Write-Host "  Export CSV     : $exportCsv"
if ($isIncremental) {
    Write-Host "  Mode           : Incremental (entries after $lastRunTime)" -ForegroundColor Yellow
} else {
    Write-Host "  Mode           : Full (first run — all entries)" -ForegroundColor Green
}
Write-Host ""

$confirm = Read-Host "Start analysis? (Y/N)"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Operation cancelled."
    exit 0
}

# -- Start transcript ----------------------------------------------------------
$runTimestamp = Get-Date
$reportFile   = Join-Path $reportsFolder ("iis-report-{0}-{1}.txt" -f $serverName, $runTimestamp.ToString("yyyyMMdd-HHmmss"))
Start-Transcript -Path $reportFile -Append | Out-Null

Write-Host ""
Write-Host "============================================="
Write-Host " IIS Local Log Analysis"
Write-Host " Server  : $serverName"
Write-Host " Folder  : $logFolder"
Write-Host " Run at  : $($runTimestamp.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host (" Reports : {0}" -f ($selectedReports | ForEach-Object { "[$_] $($reportLabels[$_])" }) -join ', ')
if ($isIncremental) {
    Write-Host " Since   : $($lastRunTime.ToString('yyyy-MM-dd HH:mm:ss')) (incremental)"
} else {
    Write-Host " Since   : (all entries — first run)"
}
Write-Host "============================================="

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# FUNCTION: Normalize-UriStem
# -----------------------------------------------------------------------------
function Normalize-UriStem {
    param([string]$uriStem)

    if ([string]::IsNullOrWhiteSpace($uriStem) -or $uriStem -eq "-") { return $uriStem }
    if ($uriStem[0] -ne '/') { $uriStem = '/' + $uriStem }

    $guidRegex  = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $intRegex   = '^\d+$'
    $tokenRegex = '^[A-Za-z0-9\-_]{20,}$'

    $norm = foreach ($seg in $uriStem.Trim('/').Split('/')) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        if ($seg -match $guidRegex)       { "{guid}" }
        elseif ($seg -match $intRegex)    { "{id}" }
        elseif ($seg -match $tokenRegex)  { "{token}" }
        else { $seg }
    }

    "/" + ($norm -join "/")
}

# -----------------------------------------------------------------------------
# FUNCTION: Parse-IisW3cFile
# -----------------------------------------------------------------------------
function Parse-IisW3cFile {
    param(
        [Parameter(Mandatory)] [string]              $filePath,
        [Parameter(Mandatory=$false)] [nullable[datetime]] $sinceTime = $null,
        [Parameter(Mandatory)] [bool]                $needUri,
        [Parameter(Mandatory)] [bool]                $needTimeTaken
    )

    $fields = $null

    foreach ($chunk in Get-Content -LiteralPath $filePath -ReadCount 5000) {
        foreach ($l in $chunk) {
            if (-not $l) { continue }

            if ($l.StartsWith("#Fields:")) {
                $fields = $l.Substring(8).Trim().Split(' ')
                continue
            }

            if ($l[0] -eq '#') { continue }
            if (-not $fields)  { continue }

            $parts = $l.Split(' ')
            if ($parts.Length -lt $fields.Length) { continue }

            $row = @{}
            for ($i = 0; $i -lt $fields.Length; $i++) { $row[$fields[$i]] = $parts[$i] }

            $date = $row["date"]; $time = $row["time"]
            if (-not $date -or -not $time) { continue }

            $dt = $null
            try {
                $dt = [datetime]::ParseExact("$date $time", "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            } catch { continue }
            if (-not $dt) { continue }

            # Incremental filter — skip entries on or before last run
            if ($sinceTime -and $dt -le $sinceTime) { continue }

            $status    = 0; [int]::TryParse($row["sc-status"],  [ref]$status)    | Out-Null
            $timeTaken = 0
            if ($needTimeTaken) { [int]::TryParse($row["time-taken"], [ref]$timeTaken) | Out-Null }

            $uriStem      = if ($needUri) { $row["cs-uri-stem"] } else { $null }
            $normalizedUri = if ($needUri) { Normalize-UriStem -uriStem $uriStem } else { $null }

            [pscustomobject]@{
                Date          = $dt.Date
                DateHour      = [datetime]::new($dt.Year, $dt.Month, $dt.Day, $dt.Hour, 0, 0)
                UriStem       = $uriStem
                NormalizedUri = $normalizedUri
                Status        = $status
                TimeTakenMs   = $timeTaken
                UserAgent     = $row["cs(User-Agent)"]
            }
        }
    }
}

# =============================================================================
# MAIN — Load and parse log files
# =============================================================================

# Determine which fields are actually needed based on selected reports
$needUri       = ($selectedReports -contains 4) -or ($selectedReports -contains 5)
$needTimeTaken = ($selectedReports -contains 5)

Write-Host ""
Write-Host "Scanning: $logFolder"
$files = @(Get-ChildItem -Path $logFolder -Recurse -File -Filter *.log -ErrorAction SilentlyContinue)
Write-Host "Found $($files.Count) .log file(s)"

if ($files.Count -eq 0) {
    Write-Warning "No .log files found in: $logFolder"
    Stop-Transcript | Out-Null
    exit 1
}

# For incremental runs, skip files not modified since last run
if ($isIncremental) {
    $filesBeforeFilter = $files.Count
    $files = @($files | Where-Object { $_.LastWriteTime -gt $lastRunTime })
    Write-Host "Files after last-modified filter : $($files.Count) (skipped $($filesBeforeFilter - $files.Count) unchanged file(s))"
}

$all = [System.Collections.Generic.List[object]]::new()
$i   = 0

foreach ($f in $files) {
    $i++
    Write-Progress `
        -Activity    "Parsing IIS logs" `
        -Status      "File $i / $($files.Count) : $($f.Name)" `
        -PercentComplete ([int](($i / [double]$files.Count) * 100))

    foreach ($e in (Parse-IisW3cFile -filePath $f.FullName -sinceTime $lastRunTime -needUri $needUri -needTimeTaken $needTimeTaken)) {
        $all.Add($e)
    }
}

Write-Progress -Activity "Parsing IIS logs" -Completed
Write-Host "Total requests parsed (before filter) : $($all.Count)"

if ($all.Count -eq 0) {
    Write-Host ""
    Write-Warning "No new log entries found since last run ($lastRunTime). Nothing to report."
    Stop-Transcript | Out-Null
    $runTimestamp.ToString("yyyy-MM-dd HH:mm:ss") | Set-Content $stateFile
    exit 0
}

# Exclude Azure Load Balancer Agent traffic
$all = @($all | Where-Object { $_.UserAgent -notmatch '(?i)load(\+|\s)*balancer(\+|\s)*agent' })
Write-Host "Total requests (after LB agent filter) : $($all.Count)"
Write-Host ""

# -- [1] Traffic by Day -------------------------------------------------------
$dailyPivot = $null
if ($selectedReports -contains 1) {
    $dailyPivot = $all |
        Group-Object Date |
        ForEach-Object {
            [pscustomobject]@{
                Date  = $_.Group[0].Date.ToString("yyyy-MM-dd")
                Total = $_.Count
            }
        } | Sort-Object Date

    "`n=== [1] Traffic by Day ==="
    $dailyPivot | Format-Table -AutoSize
}

# -- [2] Traffic by Hour ------------------------------------------------------
$hourlyPivot = $null
if ($selectedReports -contains 2) {
    $hourlyPivot = $all |
        Group-Object DateHour |
        ForEach-Object {
            [pscustomobject]@{
                DateHour = $_.Group[0].DateHour.ToString("yyyy-MM-dd HH:00")
                Total    = $_.Count
            }
        } | Sort-Object DateHour

    "`n=== [2] Traffic by Hour ==="
    $hourlyPivot | Format-Table -AutoSize
}

# -- [3] Status Categories ----------------------------------------------------
$statusCats = $null
if ($selectedReports -contains 3) {
    $statusCats = $all | ForEach-Object {
        $cat =
            if    ($_.Status -ge 200 -and $_.Status -le 299) { "2xx Success" }
            elseif($_.Status -ge 300 -and $_.Status -le 399) { "3xx Redirect" }
            elseif($_.Status -ge 400 -and $_.Status -le 499) { "4xx ClientError" }
            elseif($_.Status -ge 500 -and $_.Status -le 599) { "5xx ServerError" }
            else  { "Other" }
        [pscustomobject]@{ Category = $cat }
    } |
    Group-Object Category |
    ForEach-Object {
        [pscustomobject]@{ Category = $_.Name; Count = $_.Count }
    } | Sort-Object Category

    "`n=== [3] Status Categories ==="
    $statusCats | Format-Table -AutoSize
}

# -- [4] Top 30 Failed Endpoints ----------------------------------------------
$topFailed = $null
if ($selectedReports -contains 4) {
    $topFailed = $all |
        Where-Object { $_.Status -ge 400 -and $_.Status -le 599 } |
        Group-Object NormalizedUri, Status |
        ForEach-Object {
            $k = $_.Name -split ', '
            [pscustomobject]@{ NormalizedUri = $k[0]; Status = [int]$k[1]; Hits = $_.Count }
        } |
        Sort-Object Hits -Descending |
        Select-Object -First 30

    "`n=== [4] Top 30 Failed Endpoints ==="
    $topFailed | Format-Table -AutoSize
}

# -- [5] Top 30 Slowest Endpoints ---------------------------------------------
$slow = $null
if ($selectedReports -contains 5) {
    $slow = $all |
        Where-Object {
            $_.TimeTakenMs -gt 0 -and
            -not [string]::IsNullOrWhiteSpace($_.NormalizedUri) -and
            $_.NormalizedUri -ne "-"
        } |
        Group-Object NormalizedUri |
        ForEach-Object {
            if ($_.Count -lt $minHits) { return }

            $times    = $_.Group | Select-Object -ExpandProperty TimeTakenMs | Sort-Object
            $avg      = [math]::Round(($times | Measure-Object -Average).Average, 2)
            $p95Index = [math]::Floor(0.95 * ($times.Count - 1))

            [pscustomobject]@{
                NormalizedUri = $_.Name
                Hits          = $_.Count
                AvgMs         = $avg
                P95Ms         = [int]$times[$p95Index]
                MaxMs         = [int]$times[-1]
            }
        } |
        Sort-Object AvgMs -Descending |
        Select-Object -First 30

    "`n=== [5] Top 30 Slowest Endpoints (minHits=$minHits) ==="
    $slow | Format-Table -AutoSize
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Report saved : $reportFile"

# -- Optional CSV export -------------------------------------------------------
if ($exportCsv) {
    $ts = $runTimestamp.ToString("yyyyMMdd-HHmmss")
    if ($null -ne $dailyPivot)  { $dailyPivot  | Export-Csv -NoTypeInformation -Path (Join-Path $reportsFolder "traffic_by_day-$serverName-$ts.csv") }
    if ($null -ne $hourlyPivot) { $hourlyPivot | Export-Csv -NoTypeInformation -Path (Join-Path $reportsFolder "traffic_by_hour-$serverName-$ts.csv") }
    if ($null -ne $statusCats)  { $statusCats  | Export-Csv -NoTypeInformation -Path (Join-Path $reportsFolder "status_categories-$serverName-$ts.csv") }
    if ($null -ne $topFailed)   { $topFailed   | Export-Csv -NoTypeInformation -Path (Join-Path $reportsFolder "top_failed-$serverName-$ts.csv") }
    if ($null -ne $slow)        { $slow        | Export-Csv -NoTypeInformation -Path (Join-Path $reportsFolder "slow_endpoints-$serverName-$ts.csv") }
    Write-Host "CSV files saved to : $reportsFolder"
}

# -- Stop transcript -----------------------------------------------------------
Stop-Transcript | Out-Null

# -- Update last run state file ------------------------------------------------
$runTimestamp.ToString("yyyy-MM-dd HH:mm:ss") | Set-Content $stateFile
Write-Host ""
Write-Host "Last run state updated : $stateFile" -ForegroundColor DarkGray
