# OIM Scripting Guide

## Supported Languages:
- PowerShell (automation, deployment, admin tasks)
- VB.Net / C# (Designer scripting context — process chains, format scripts, event handlers)
- SQL (diagnostic and operational queries)

## PowerShell Standards:
- Use approved verbs (`Get-`, `Set-`, `New-`, `Remove-`, `Invoke-`, etc.)
- Always include try/catch error handling
- Explicitly import required modules
- Never store plaintext secrets — use `$env:` variables or secure credential stores
- Use parameter placeholders: `$env:OIM_SERVER`, `$env:OIM_DB`

### PowerShell Template:
```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    [Brief description]
.PARAMETER OIMServer
    OIM Application Server URL (use $env:OIM_SERVER)
.NOTES
    OIM Version: vX.X | Environment: Dev / UAT / Prod
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$OIMServer = $env:OIM_SERVER
)

try {
    # Script logic here
}
catch {
    Write-Error "Error: $_"
    exit 1
}
```

## VB.Net / C# Designer Scripting:
- Scripts run in OIM Designer scripting context only
- Do not use file I/O, network calls, or external dependencies
- Use `Session`, `Connection`, and `UnitOfWork` objects provided by OIM runtime
- Always handle exceptions to avoid breaking process chains

## Reference:
- Quest One Identity Designer documentation
- /knowledge-base/ for team-curated script examples
