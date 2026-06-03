<#
.SYNOPSIS
    Parses .NET NLog log files from a folder into a structured CSV for analysis.

.DESCRIPTION
    Scans all log files in a folder (recursively), parses each entry using
    NLog's standard layout, and exports results to a CSV file.

    Extracted fields: Date, Time, DateTime, Level, Source, Message,
    Exception types, Inner exception, Timezone, Stack info, Source file.

    A summary is printed to the console after export.

.NOTES
    Author  : Janardhan Matheti
    Version : 1.0
    Updated : 06-02-2026
    Requires: PowerShell 5.1 or later. Save as UTF-8 with BOM on PS 5.x.
#>

[CmdletBinding()]
param ()

Write-Host ""
Write-Host "=== Parse-LogsToCsv ===" -ForegroundColor Cyan
Write-Host "Parses NLog log files into a structured CSV for analysis."
Write-Host ""

# -- Guided input --------------------------------------------------------------

# Log folder
do {
    $LogFolderPath = Read-Host "Enter the path to the log folder"
    if ([string]::IsNullOrWhiteSpace($LogFolderPath)) {
        Write-Warning "Log folder path cannot be empty."
    } elseif (-not (Test-Path $LogFolderPath -PathType Container)) {
        Write-Warning "Folder not found: $LogFolderPath"
        $LogFolderPath = $null
    }
} while ([string]::IsNullOrWhiteSpace($LogFolderPath))

# File filter
$filterInput = Read-Host "File filter (default: *.txt  |  e.g. *.log — press Enter to use default)"
$Filter = if ([string]::IsNullOrWhiteSpace($filterInput)) { "*.txt" } else { $filterInput.Trim() }

# Log level
Write-Host ""
Write-Host "Log levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL, ALL"
$levelInput = Read-Host "Minimum log level to include (default: ALL — press Enter to use default)"
$validLevels = @("TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "ALL")
if ([string]::IsNullOrWhiteSpace($levelInput)) {
    $Level = "ALL"
} elseif ($validLevels -contains $levelInput.ToUpper()) {
    $Level = $levelInput.ToUpper()
} else {
    Write-Warning "Invalid level '$levelInput'. Defaulting to ALL."
    $Level = "ALL"
}

# Output CSV path
$timestamp         = Get-Date -Format "yyyyMMdd_HHmmss"
$defaultOutputPath = Join-Path $LogFolderPath "log_analysis_$timestamp.csv"
Write-Host ""
Write-Host "Default output path: $defaultOutputPath"
$outputInput   = Read-Host "Output CSV path (press Enter to use default)"
$OutputCsvPath = if ([string]::IsNullOrWhiteSpace($outputInput)) { $defaultOutputPath } else { $outputInput.Trim() }

Write-Host ""
Write-Host "Settings:" -ForegroundColor Cyan
Write-Host "  Folder : $LogFolderPath"
Write-Host "  Filter : $Filter"
Write-Host "  Level  : $Level"
Write-Host "  Output : $OutputCsvPath"
Write-Host ""

$confirm = Read-Host "Start parsing? (Y/N)"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Operation cancelled."
    exit 0
}

Write-Host ""

# -- Log level ordering for filtering -----------------------------------------
$levelOrder = @{ TRACE = 0; DEBUG = 1; INFO = 2; WARN = 3; ERROR = 4; FATAL = 5 }
$minLevel   = if ($Level -eq "ALL") { 0 } else { $levelOrder[$Level] }

# -- Regex patterns ------------------------------------------------------------
$entryPattern          = '^(?<Date>\d{4}-\d{2}-\d{2})\s+(?<Time>\d{2}:\d{2}:\d{2}\.\d+)\s+(?<Level>TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\s+\((?<Source>[^)]*)\)\s*:\s*(?<Message>.*)$'
$exceptionTypePattern  = '(?<ExType>[A-Za-z][\w\.]+Exception)'
$innerExceptionPattern = '--->\s*(?<InnerEx>[A-Za-z][\w\.]+(?:Exception|Error)[^\r\n]*)'
$tzPattern             = 'timezone(?:info)?\s+was:\s*(?<TZ>[^\s]+)'
$stackFramePattern     = '^\s+at\s+(?<Frame>.+)$'

# -- Collect files -------------------------------------------------------------
$logFiles = Get-ChildItem -Path $LogFolderPath -Filter $Filter -File -Recurse |
            Where-Object { $_.FullName -ne $OutputCsvPath }

if ($logFiles.Count -eq 0) {
    Write-Warning "No files matching '$Filter' found in: $LogFolderPath"
    exit 0
}

Write-Host "Found $($logFiles.Count) file(s) to parse..."
Write-Host ""

# -- Parse entries -------------------------------------------------------------
$results     = [System.Collections.Generic.List[PSCustomObject]]::new()
$allDates    = [System.Collections.Generic.List[datetime]]::new()
$levelCounts = @{ TRACE = 0; DEBUG = 0; INFO = 0; WARN = 0; ERROR = 0; FATAL = 0 }
$exCounts    = @{}
$tzCounts    = @{}

foreach ($logFile in $logFiles) {
    Write-Host "  Parsing: $($logFile.Name)"
    $lines      = Get-Content $logFile.FullName -Encoding UTF8
    $lineCount  = $lines.Count
    $i          = 0
    $entryLines = [System.Collections.Generic.List[string]]::new()

    while ($i -le $lineCount) {
        $line = if ($i -lt $lineCount) { $lines[$i] } else { $null }

        if (($null -eq $line -or $line -match $entryPattern) -and $entryLines.Count -gt 0) {
            $firstLine = $entryLines[0]
            if ($firstLine -match $entryPattern) {
                $entryLevel = $Matches['Level']
                if ($levelOrder[$entryLevel] -ge $minLevel) {
                    $entryDate  = $Matches['Date']
                    $entryTime  = $Matches['Time']
                    $entryMsg   = $Matches['Message']
                    $entryBody  = $entryLines -join "`n"

                    $exMatches  = [regex]::Matches($entryBody, $exceptionTypePattern)
                    $exTypes    = ($exMatches | ForEach-Object { $_.Groups['ExType'].Value } | Sort-Object -Unique) -join '; '

                    $innerMatch = [regex]::Match($entryBody, $innerExceptionPattern)
                    $innerEx    = if ($innerMatch.Success) { $innerMatch.Groups['InnerEx'].Value } else { '' }

                    $tzMatch    = [regex]::Match($entryBody, $tzPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    $timezone   = if ($tzMatch.Success) { $tzMatch.Groups['TZ'].Value } else { '' }

                    $stackFrames = $entryLines | Where-Object { $_ -match $stackFramePattern } |
                                   ForEach-Object { [regex]::Match($_, $stackFramePattern).Groups['Frame'].Value }
                    $rootFrame   = if ($stackFrames.Count -gt 0) { $stackFrames[0] } else { '' }
                    $fullStack   = $stackFrames -join ' | '
                    $stackDepth  = $stackFrames.Count

                    $dtString = "$entryDate $entryTime"
                    $parsedDt = [datetime]::MinValue
                    [datetime]::TryParse($dtString, [ref]$parsedDt) | Out-Null

                    $levelCounts[$entryLevel]++
                    if ($parsedDt -ne [datetime]::MinValue) { $allDates.Add($parsedDt) }
                    foreach ($ex in ($exTypes -split '; ' | Where-Object { $_ })) {
                        $exCounts[$ex] = ($exCounts[$ex] ?? 0) + 1
                    }
                    if ($timezone) { $tzCounts[$timezone] = ($tzCounts[$timezone] ?? 0) + 1 }

                    $results.Add([PSCustomObject]@{
                        Date           = $entryDate
                        Time           = $entryTime
                        DateTime       = $dtString
                        Level          = $entryLevel
                        Source         = $Matches['Source']
                        Message        = $entryMsg
                        ExceptionType  = $exTypes
                        InnerException = $innerEx
                        Timezone       = $timezone
                        RootFrame      = $rootFrame
                        FullStack      = $fullStack
                        StackDepth     = $stackDepth
                        SourceFile     = $logFile.Name
                        SourcePath     = $logFile.FullName
                    })
                }
            }
            $entryLines.Clear()
        }

        if ($null -ne $line) { $entryLines.Add($line) }
        $i++
    }
}

# -- Export CSV ----------------------------------------------------------------
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host "CSV exported to: $OutputCsvPath" -ForegroundColor Green
} else {
    Write-Warning "No log entries matched the specified filter and level. No CSV written."
    exit 0
}

# -- Summary -------------------------------------------------------------------
$dateMin  = if ($allDates.Count -gt 0) { ($allDates | Measure-Object -Minimum).Minimum } else { $null }
$dateMax  = if ($allDates.Count -gt 0) { ($allDates | Measure-Object -Maximum).Maximum } else { $null }
$spanDays = if ($dateMin -and $dateMax) { [math]::Round(($dateMax - $dateMin).TotalDays, 1) } else { 'N/A' }

Write-Host ""
Write-Host "===============================" -ForegroundColor Cyan
Write-Host " Parse Summary" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan
Write-Host "  Folder   : $LogFolderPath"
Write-Host "  Filter   : $Filter"
Write-Host "  Level    : $Level"
Write-Host "  Files    : $($logFiles.Count)"
Write-Host "  Entries  : $($results.Count)"
Write-Host "  From     : $dateMin"
Write-Host "  To       : $dateMax"
Write-Host "  Span     : $spanDays day(s)"
Write-Host ""
Write-Host "  By Level:"
foreach ($lv in @('FATAL','ERROR','WARN','INFO','DEBUG','TRACE')) {
    if ($levelCounts[$lv] -gt 0) {
        Write-Host ("    {0,-6}: {1}" -f $lv, $levelCounts[$lv])
    }
}
if ($exCounts.Count -gt 0) {
    Write-Host ""
    Write-Host "  Top 10 Exception Types:"
    $exCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 |
        ForEach-Object { Write-Host ("    {0,-55}: {1}" -f $_.Key, $_.Value) }
}
if ($tzCounts.Count -gt 0) {
    Write-Host ""
    Write-Host "  Top Timezones in Errors:"
    $tzCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 |
        ForEach-Object { Write-Host ("    {0,-35}: {1}" -f $_.Key, $_.Value) }
}
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""
