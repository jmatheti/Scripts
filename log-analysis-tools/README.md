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

Analyzes IIS W3C log files locally from two servers and produces 5 analysis tables.

**Run:**
```powershell
.\iis-local-stats.ps1
```

**Prompts:**
| Prompt | Default | Description |
|--------|---------|-------------|
| Root folder path | — | Root folder containing server log subfolders |
| Server subfolder names | `01, 02` | Comma-separated subfolder names under the root |
| Minimum hits (slowest table) | `20` | Minimum request count for an endpoint to appear in the slowest table |
| Export CSV files | `N` | Whether to write results to CSV files in the root folder |

**Output Tables:**
| # | Table | Description |
|---|-------|-------------|
| 1 | Traffic by Day | Daily request counts: Server01 vs Server02 vs Total |
| 2 | Traffic by Hour | Hourly request counts: Server01 vs Server02 vs Total |
| 3 | Status Categories | 2xx / 3xx / 4xx / 5xx breakdown per server |
| 4 | Top 30 Failed Endpoints | Most failing normalized API paths and status code |
| 5 | Top 30 Slowest Endpoints | Slowest normalized API paths by Avg / P95 / Max ms |

**Notes:**
- IIS log files must be in standard W3C format with a `#Fields:` header
- Times in IIS logs are UTC by default
- Azure Load Balancer Agent requests are excluded automatically
- CSV files (if exported) are written to the root folder
