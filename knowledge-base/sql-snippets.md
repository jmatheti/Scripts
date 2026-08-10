# OIM SQL Snippets

A team-curated library of reusable SQL queries.

> **Standard Header Format:**
> `-- OIM vX.X | Purpose: [description] | Date: YYYY-MM-DD`

---

## Job Queue

### Failed Jobs
```sql
-- OIM vX.X | Purpose: Failed job queue entries | Date: YYYY-MM-DD
SELECT TOP 100 UID_Job, TaskName, ErrorMessages, LastEndTime, Queue
FROM JobQueue
WHERE State = 'Failed'
ORDER BY LastEndTime DESC
```

### Currently Running Jobs
```sql
-- OIM vX.X | Purpose: Currently running jobs | Date: YYYY-MM-DD
SELECT UID_Job, TaskName, State, StartTime, Queue
FROM JobQueue
WHERE State = 'Running'
ORDER BY StartTime ASC
```

---

## Identities

### Identities Without AD Accounts
```sql
-- OIM vX.X | Purpose: Identities with no AD account | Date: YYYY-MM-DD
SELECT p.UID_Person, p.CentralAccount, p.Lastname, p.Firstname
FROM Person p
LEFT JOIN ADSAccount a ON a.UID_Person = p.UID_Person
WHERE a.UID_ADSAccount IS NULL
  AND p.IsInActive = 0
```

---

## Scheduler

### Active Scheduled Tasks
```sql
-- OIM vX.X | Purpose: Active scheduled tasks | Date: YYYY-MM-DD
SELECT Ident_DialogScheduler, IsActive, NextExecTime, LastExecTime
FROM DialogScheduler
WHERE IsActive = 1
ORDER BY NextExecTime ASC
```

---

<!-- Add new snippets above this line -->
