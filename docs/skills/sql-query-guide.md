# OIM SQL Query Guide

## Standards:
- Always include header: `-- OIM vX.X | Purpose: [description] | Date: YYYY-MM-DD`
- Always use TOP or WHERE filters — avoid unbounded SELECT on large tables
- Never include real server names, credentials, or environment-specific values
- Test queries in Dev before running in Prod ⚠️ PRODUCTION RISK

## Key Tables:
| Table | Description |
|-------|-------------|
| Person | Identity records |
| ADSAccount | Active Directory accounts |
| UNSAccount | Generic unstructured namespace accounts |
| JobQueue | Process queue entries |
| DialogScheduler | Scheduled task definitions |
| QERVIPerson | Role assignments |
| BaseTree | Organisational structure |

## Common Query Patterns:

### Identities without accounts:
```sql
-- OIM vX.X | Purpose: Identities with no AD account | Date: YYYY-MM-DD
SELECT p.UID_Person, p.CentralAccount, p.Lastname, p.Firstname
FROM Person p
LEFT JOIN ADSAccount a ON a.UID_Person = p.UID_Person
WHERE a.UID_ADSAccount IS NULL
  AND p.IsInActive = 0
```

### Failed jobs in queue:
```sql
-- OIM vX.X | Purpose: Failed job queue entries | Date: YYYY-MM-DD
SELECT TOP 100 UID_Job, TaskName, ErrorMessages, LastEndTime, Queue
FROM JobQueue
WHERE State = 'Failed'
ORDER BY LastEndTime DESC
```

### Scheduled tasks:
```sql
-- OIM vX.X | Purpose: Active scheduled tasks | Date: YYYY-MM-DD
SELECT Ident_DialogScheduler, IsActive, NextExecTime, LastExecTime
FROM DialogScheduler
WHERE IsActive = 1
ORDER BY NextExecTime ASC
```

## Reference:
- /knowledge-base/sql-snippets.md for team-curated queries
- support.oneidentity.com for schema documentation
