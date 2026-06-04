# Scripts

A collection of utility scripts for log management and maintenance.
All scripts run in **guided mode** — no parameters needed. Each script will prompt for all required inputs at runtime.

---

## Remove-IPLines.ps1

Removes all lines containing IPv4 addresses from log files in a folder.

**Run:**
```powershell
.\Remove-IPLines.ps1
```

**Prompts:**
| Prompt | Default | Description |
|--------|---------|-------------|
| Log folder path | — | Full path to the folder containing log files |

**Notes:**
- Processes all file types in the folder
- Files are updated in-place — **back up before running**
- Prints per-file and total count of removed lines
- Asks for confirmation before making any changes

---

## Parse-LogsToCsv.ps1

Parses `.NET NLog` log files from a folder into a structured CSV for analysis.
Useful for analysing errors, exception trends, and affected timezones across multiple log files.

**Run:**
```powershell
.\Parse-LogsToCsv.ps1
```

**Prompts:**
| Prompt | Default | Description |
|--------|---------|-------------|
| Log folder path | — | Folder containing log files (scanned recursively) |
| File filter | `*.txt` | File name pattern — use `*.log` if needed |
| Minimum log level | `ALL` | `TRACE` `DEBUG` `INFO` `WARN` `ERROR` `FATAL` `ALL` |
| Output CSV path | `<LogFolder>\log_analysis_<timestamp>.csv` | Full path for the output CSV file |

**CSV Output Columns:**
| Column | Description |
|--------|-------------|
| `Date` / `Time` / `DateTime` | Parsed timestamp from the log entry |
| `Level` | Log level (ERROR, WARN, etc.) |
| `Source` | Logger name from the log entry |
| `Message` | Cleaned message text |
| `ExceptionType` | All exception class names found (semicolon-separated) |
| `InnerException` | The `---> InnerException` line if present |
| `Timezone` | Timezone ID extracted from the message (e.g. `Etc/GMT-10`) |
| `RootFrame` | Innermost `at ...` stack frame |
| `StackDepth` | Number of stack frames |
| `FullStack` | All stack frames pipe-delimited |
| `SourceFile` / `SourcePath` | Source file name and full path |

**Notes:**
- Log timestamps are used as-is — no timezone conversion is applied
- Save the script as **UTF-8 with BOM** to avoid encoding issues on Windows PowerShell 5.x
- Prints a summary after export: file count, entry count, date range, level breakdown, top exceptions, top timezones

---

## iis-local-stats.ps1

Analyzes copied IIS W3C log files directly on the current server and produces selected analysis reports.
Run once a week — automatically picks up from where the last run left off.

**Run:**
```powershell
.\iis-local-stats.ps1
```

> **Important:** Point to a **copy** of IIS logs — not the live folder IIS is actively writing to.

**Prompts:**
| Prompt | Default | Description |
|--------|---------|-------------|
| IIS log folder path | — | Path to the copied IIS log folder on this server |
| Reports output folder | `<LogFolder>\Reports` | Where report transcripts and CSVs are saved |
| Reports to run | `A` (all) | Select one, many, or all — see table below |
| Minimum hits (slowest table) | `20` | Only shown when report `[5]` is selected |
| Export CSV files | `N` | Whether to write results to timestamped CSV files |

**Report Selection:**
| Key | Report | Description |
|-----|--------|-------------|
| `1` | Traffic by Day | Total request count per day |
| `2` | Traffic by Hour | Total request count per hour |
| `3` | Status Categories | 2xx / 3xx / 4xx / 5xx breakdown |
| `4` | Top 30 Failed Endpoints | Most failing normalized API paths + status code |
| `5` | Top 30 Slowest Endpoints | Slowest normalized API paths by Avg / P95 / Max ms |
| `A` | All reports | Runs all 5 reports (default) |

You can combine selections — e.g. enter `1,2` for day and hour traffic, or `3,4,5` for errors and performance.

**Incremental runs:**
| Behaviour | Detail |
|-----------|--------|
| First run | No state file exists — processes all log entries |
| Subsequent runs | Reads last run timestamp — skips entries already processed |
| File-level skip | Files not modified since last run are skipped entirely |
| State file | Saved as `iis-lastrun-<SERVERNAME>.txt` in the reports folder |

**Output files (all saved to the reports folder):**
| File | Description |
|------|-------------|
| `iis-report-<SERVER>-<yyyyMMdd-HHmmss>.txt` | Full console transcript of the run |
| `traffic_by_day-<SERVER>-<timestamp>.csv` | Report [1] CSV (if exported) |
| `traffic_by_hour-<SERVER>-<timestamp>.csv` | Report [2] CSV (if exported) |
| `status_categories-<SERVER>-<timestamp>.csv` | Report [3] CSV (if exported) |
| `top_failed-<SERVER>-<timestamp>.csv` | Report [4] CSV (if exported) |
| `slow_endpoints-<SERVER>-<timestamp>.csv` | Report [5] CSV (if exported) |

**Notes:**
- IIS log files must be in standard W3C format with a `#Fields:` header
- Log times are used as-is — no timezone conversion is applied
- Azure Load Balancer Agent requests are excluded automatically
- URI segments are normalized: numbers → `{id}`, GUIDs → `{guid}`, long tokens → `{token}`
- Run on each server independently — the state file is server-specific
