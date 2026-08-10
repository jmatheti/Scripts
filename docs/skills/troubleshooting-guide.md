# OIM Troubleshooting Guide

## Inputs Required:
- OIM Version (mandatory)
- Component affected: Job Server / App Server / Sync Editor / Portal / Designer / DB
- Error message or log extract
- Environment: Dev / UAT / Prod

## Troubleshooting Process:
1. Parse the error message for known OIM error codes or patterns
2. Check /knowledge-base/known-issues.md for existing resolutions
3. If not found, search support.oneidentity.com and community.oneidentity.com
4. Provide numbered, step-by-step diagnostic steps
5. Provide fix with ⚠️ PRODUCTION RISK flag where applicable
6. Log outcome using Issue Card template
7. If issue is new and resolved, add to /knowledge-base/known-issues.md

## Key Log File Locations:
| Component | Log Location |
|-----------|-------------|
| Job Server | `[InstallDir]\One Identity Manager\JobService\Logs\` |
| Application Server | IIS logs + Windows Event Viewer > Application |
| Synchronisation | Synchronisation Editor > Log view (in-tool) |
| Web Portal | IIS logs + `%ProgramData%\One Identity\Logs\` |
| Designer | `%AppData%\One Identity\Designer\Logs\` |

## Diagnostic SQL:
```sql
-- OIM vX.X | Purpose: Failed job queue entries | Date: YYYY-MM-DD
SELECT TOP 100 UID_Job, TaskName, ErrorMessages, LastEndTime, Queue
FROM JobQueue
WHERE State = 'Failed'
ORDER BY LastEndTime DESC

-- OIM vX.X | Purpose: Currently running jobs | Date: YYYY-MM-DD
SELECT UID_Job, TaskName, State, StartTime, Queue
FROM JobQueue
WHERE State = 'Running'
ORDER BY StartTime ASC
```
