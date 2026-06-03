<#
.SYNOPSIS
    Removes all lines containing IPv4 addresses from log files in a folder.

.DESCRIPTION
    Scans all files in the specified folder and removes any line containing
    an IPv4 address pattern. Files are updated in-place.

.NOTES
    Author  : Janardhan Matheti
    Version : 1.0
    Updated : 06-02-2026
    Warning : This script modifies files in-place. Back up files before running.
#>

Write-Host ""
Write-Host "=== Remove-IPLines ===" -ForegroundColor Cyan
Write-Host "Removes all lines containing IPv4 addresses from log files in a folder."
Write-Host ""

# -- Guided input --------------------------------------------------------------
$LogFolder = Read-Host "Enter the full path to the log folder"

if ([string]::IsNullOrWhiteSpace($LogFolder)) {
    Write-Error "No folder path provided. Exiting."
    exit 1
}

if (-not (Test-Path $LogFolder)) {
    Write-Error "Folder not found: $LogFolder"
    exit 1
}

$files = Get-ChildItem -Path $LogFolder -File
if ($files.Count -eq 0) {
    Write-Host "No files found in: $LogFolder"
    exit 0
}

Write-Host ""
Write-Host "Found $($files.Count) file(s) in: $LogFolder"
Write-Host ""

# -- Confirm before proceeding -------------------------------------------------
$confirm = Read-Host "Proceed with removing IP address lines? (Y/N)"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Operation cancelled."
    exit 0
}

Write-Host ""

# -- Process files -------------------------------------------------------------
$totalRemoved = 0

$files | ForEach-Object {
    $file     = $_.FullName
    $content  = Get-Content $file
    $filtered = $content | Where-Object { $_ -notmatch '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' }
    $removed  = $content.Count - $filtered.Count
    $filtered | Set-Content $file
    $totalRemoved += $removed
    Write-Host "Processed: $($_.Name) — Removed $removed line(s)"
}

Write-Host ""
Write-Host "Done! Total lines removed across all files: $totalRemoved" -ForegroundColor Green
