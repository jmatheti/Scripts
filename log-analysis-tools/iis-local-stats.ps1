<#
.SYNOPSIS
    Analyzes IIS W3C log files locally from two servers and produces 5 analysis tables.

.DESCRIPTION
    Scans IIS W3C .log files from two server folders, normalizes API paths,
    filters out Azure Load Balancer Agent traffic, and outputs:

        [1] Traffic by Day        - Date | Server01 | Server02 | Total
        [2] Traffic by Hour       - DateHour | Server01 | Server02 | Total
        [3] Status Categories     - 2xx / 3xx / 4xx / 5xx counts per server
        [4] Top 30 Failed         - NormalizedUri + status code + hit count
        [5] Top 30 Slowest        - NormalizedUri + Hits / AvgMs / P95Ms / MaxMs

    URI normalization rules:
        Numeric segments  =>  {id}     e.g. /api/orders/123  => /api/orders/{id}
        GUID segments     =>  {guid}
        Long tokens       =>  {token}

.NOTES
    Author  : Janardhan Matheti
    Version : 1.1
    Updated : 06-03-2026
    Requires: PowerShell 5.1 or later. No external modules needed.
              Log files must be in standard IIS W3C format with a #Fields: header.
              Times in IIS logs are displayed as-is (no timezone conversion).
#>

[CmdletBinding()]
param ()

Write-Host ""
Write-Host "=== IIS Local Log Analysis ===" -ForegroundColor Cyan
Write-Host "Analyzes IIS W3C log files from two servers and produces 5 analysis tables."
Write-Host ""

# -- Guided input --------------------------------------------------------------

# Root folder
do {
    $root = Read-Host "Enter the root folder containing server log subfolders"
    if ([string]::IsNullOrWhiteSpace($root)) {
        Write-Warning "Root folder path cannot be empty."
    } elseif (-not (Test-Path $root)) {
        Write-Warning "Folder not found: $root"
        $root = $null
    }
} while ([string]::IsNullOrWhiteSpace($root))

# Server subfolder names
$serverInput = Read-Host "Enter server subfolder names, comma-separated (default: 01,02 — press Enter to use default)"
if ([string]::IsNullOrWhiteSpace($serverInput)) {
    $serverNames = @("01", "02")
} else {
    $serverNames = $serverInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

# Minimum hits for slowest endpoints table
$minHitsInput = Read-Host "Minimum hits to appear in slowest endpoints table (default: 20 — press Enter to use default)"
$minHits = 20
if (-not [string]::IsNullOrWhiteSpace($minHitsInput)) {
    $parsed = 0
    if ([int]::TryParse($minHitsInput.Trim(), [ref]$parsed) -and $parsed -gt 0) {
        $minHits = $parsed
    } else {
        Write-Warning "Invalid value '$minHitsInput'. Using default: 20"
    }
}

# Export CSVs?
$exportInput = Read-Host "Export results to CSV files in the root folder? (Y/N — default: N)"
$exportCsv   = $exportInput -match '^[Yy]$'

Write-Host ""
Write-Host "Settings:" -ForegroundColor Cyan
Write-Host "  Root folder : $root"
Write-Host "  Servers     : $($serverNames -join ', ')"
Write-Host "  Min hits    : $minHits"
Write-Host "  Export CSV  : $exportCsv"
Write-Host ""

$confirm = Read-Host "Start analysis? (Y/N)"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Operation cancelled."
    exit 0
}

Write-Host ""

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
        [Parameter(Mandatory)] [string] $serverName,
        [Parameter(Mandatory)] [string] $filePath
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

            $status    = 0; [int]::TryParse($row["sc-status"],  [ref]$status)    | Out-Null
            $timeTaken = 0; [int]::TryParse($row["time-taken"], [ref]$timeTaken) | Out-Null

            $uriStem = $row["cs-uri-stem"]

            [pscustomobject]@{
                Server        = $serverName
                Date          = $dt.Date
                DateHour      = [datetime]::new($dt.Year, $dt.Month, $dt.Day, $dt.Hour, 0, 0)
                Method        = $row["cs-method"]
                UriStem       = $uriStem
                NormalizedUri = Normalize-UriStem -uriStem $uriStem
                Status        = $status
                TimeTakenMs   = $timeTaken
                UserAgent     = $row["cs(User-Agent)"]
            }
        }
    }
}

# -----------------------------------------------------------------------------
# FUNCTION: Load-IisEventsForServer
# -----------------------------------------------------------------------------
function Load-IisEventsForServer {
    param([Parameter(Mandatory)][string]$serverName)

    $iisPath = Join-Path $root "$serverName\IIS"

    if (-not (Test-Path $iisPath)) {
        Write-Warning "  [SKIP] Path not found: $iisPath"
        return
    }

    Write-Host "[$serverName] Scanning: $iisPath"
    $files = @(Get-ChildItem -Path $iisPath -Recurse -File -Filter *.log -ErrorAction SilentlyContinue)
    Write-Host "[$serverName] Found $($files.Count) .log file(s)"

    if ($files.Count -eq 0) { return }

    $events = [System.Collections.Generic.List[object]]::new()
    $i = 0

    foreach ($f in $files) {
        $i++
        Write-Progress `
            -Activity    "[$serverName] Parsing IIS logs" `
            -Status      "File $i / $($files.Count) : $($f.Name)" `
            -PercentComplete ([int](($i / [double]$files.Count) * 100))

        foreach ($e in (Parse-IisW3cFile -serverName $serverName -filePath $f.FullName)) {
            $events.Add($e)
        }
    }

    Write-Progress -Activity "[$serverName] Parsing IIS logs" -Completed
    Write-Host "[$serverName] Parsed $($events.Count) request lines"

    return $events
}

# =============================================================================
# MAIN
# =============================================================================
Write-Host "============================================="
Write-Host " IIS Local Log Analysis"
Write-Host " Root    : $root"
Write-Host " Servers : $($serverNames -join ', ')"
Write-Host "============================================="

$all = [System.Collections.Generic.List[object]]::new()
foreach ($s in $serverNames) {
    $loaded = Load-IisEventsForServer -serverName $s
    if ($loaded) { foreach ($e in $loaded) { $all.Add($e) } }
}

if ($all.Count -eq 0) {
    Write-Warning "No IIS log events found. Check paths under $root"
    exit 1
}

Write-Host "`nTotal requests parsed (before filter) : $($all.Count)"

$all = @($all | Where-Object { $_.UserAgent -notmatch '(?i)load(\+|\s)*balancer(\+|\s)*agent' })
Write-Host "Total requests (after LB agent filter) : $($all.Count)"

function Get-ServerCounts {
    param($group)
    $byServer = $group | Group-Object Server
    $s01 = ($byServer | Where-Object Name -eq "01" | Select-Object -ExpandProperty Count -ErrorAction SilentlyContinue)
    $s02 = ($byServer | Where-Object Name -eq "02" | Select-Object -ExpandProperty Count -ErrorAction SilentlyContinue)
    if (-not $s01) { $s01 = 0 }
    if (-not $s02) { $s02 = 0 }
    return [int]$s01, [int]$s02
}

# -- [1] Traffic by Day -------------------------------------------------------
$dailyPivot = $all |
    Group-Object Date |
    ForEach-Object {
        $s01, $s02 = Get-ServerCounts $_.Group
        [pscustomobject]@{
            Date     = $_.Group[0].Date.ToString("yyyy-MM-dd")
            Server01 = $s01
            Server02 = $s02
            Total    = $s01 + $s02
        }
    } | Sort-Object Date

"`n=== [1] Traffic by Day (01 vs 02 vs Total) ==="
$dailyPivot | Format-Table -AutoSize

# -- [2] Traffic by Hour ------------------------------------------------------
$hourlyPivot = $all |
    Group-Object DateHour |
    ForEach-Object {
        $s01, $s02 = Get-ServerCounts $_.Group
        [pscustomobject]@{
            DateHour = $_.Group[0].DateHour.ToString("yyyy-MM-dd HH:00")
            Server01 = $s01
            Server02 = $s02
            Total    = $s01 + $s02
        }
    } | Sort-Object DateHour

"`n=== [2] Traffic by Hour (01 vs 02 vs Total) ==="
$hourlyPivot | Format-Table -AutoSize

# -- [3] Status Categories ----------------------------------------------------
$statusCats = $all | ForEach-Object {
    $cat =
        if    ($_.Status -ge 200 -and $_.Status -le 299) { "2xx Success" }
        elseif($_.Status -ge 300 -and $_.Status -le 399) { "3xx Redirect" }
        elseif($_.Status -ge 400 -and $_.Status -le 499) { "4xx ClientError" }
        elseif($_.Status -ge 500 -and $_.Status -le 599) { "5xx ServerError" }
        else  { "Other" }
    [pscustomobject]@{ Server=$_.Server; Category=$cat }
} |
Group-Object Server, Category |
ForEach-Object {
    $k = $_.Name -split ', '
    [pscustomobject]@{ Server=$k[0]; Category=$k[1]; Count=$_.Count }
} | Sort-Object Server, Category

"`n=== [3] Status Categories (by server) ==="
$statusCats | Format-Table -AutoSize

# -- [4] Top 30 Failed Endpoints ----------------------------------------------
$topFailed = $all |
    Where-Object { $_.Status -ge 400 -and $_.Status -le 599 } |
    Group-Object NormalizedUri, Status |
    ForEach-Object {
        $k = $_.Name -split ', '
        [pscustomobject]@{ NormalizedUri=$k[0]; Status=[int]$k[1]; Hits=$_.Count }
    } |
    Sort-Object Hits -Descending |
    Select-Object -First 30

"`n=== [4] Top 30 Failed Endpoints (NormalizedUri) ==="
$topFailed | Format-Table -AutoSize

# -- [5] Top 30 Slowest Endpoints ---------------------------------------------
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

"`n=== [5] Top 30 Slowest Endpoints (NormalizedUri) (minHits=$minHits) ==="
$slow | Format-Table -AutoSize

Write-Host "`nDone." -ForegroundColor Green

# -- Optional CSV export -------------------------------------------------------
if ($exportCsv) {
    $dailyPivot  | Export-Csv -NoTypeInformation -Path (Join-Path $root "traffic_by_day.csv")
    $hourlyPivot | Export-Csv -NoTypeInformation -Path (Join-Path $root "traffic_by_hour.csv")
    $statusCats  | Export-Csv -NoTypeInformation -Path (Join-Path $root "status_categories.csv")
    $topFailed   | Export-Csv -NoTypeInformation -Path (Join-Path $root "top_failed_endpoints.csv")
    $slow        | Export-Csv -NoTypeInformation -Path (Join-Path $root "slow_endpoints.csv")
    Write-Host ""
    Write-Host "CSV files written to: $root" -ForegroundColor Green
}
