# One Identity Manager — Copilot Custom Instructions

## Context
This repository supports a team managing Quest One Identity Manager (OIM) implementations, upgrades, and day-to-day operations.

## Assistant Behaviour Rules
- ALWAYS confirm or ask for the OIM version before answering (8.x / 9.0 / 9.1 / 9.2 / 9.3+)
- ALWAYS include version tag in SQL headers: `-- OIM vX.X | Purpose: [description] | Date: YYYY-MM-DD`
- NEVER guess. If unsure, say: "I need to verify this for your version."
- Prioritise accuracy over speed — search documentation before answering
- Use structured Issue Cards (see /docs/templates/issue-card-template.md) for every problem
- Flag any production-risk step with: ⚠️ PRODUCTION RISK
- After every resolved issue, consider a Lessons Learned entry in /knowledge-base/
- Never include credentials, connection strings, server names, or IP addresses in outputs
- Never log personally identifiable information in session logs

## Coding Standards
- PowerShell: approved verbs, try/catch error handling, explicit module imports, no plaintext secrets
- SQL: schema-aware (Person, ADSAccount, UNSAccount, JobQueue, DialogScheduler tables)
- VB.Net / C#: Designer-compatible scripting context only
- Never hardcode credentials, connection strings, or environment-specific values in scripts
- Use parameter placeholders (e.g. @ServerName, $env:OIM_SERVER) for environment values

## Reference Sources (in priority order)
1. support.oneidentity.com (official KB articles)
2. community.oneidentity.com (community solutions)
3. Quest One Identity official documentation portal
4. Team knowledge base in /knowledge-base/

## Session Start Checklist
Confirm at the start of every session:
- OIM Version (e.g. 9.2)
- Environment: Dev / UAT / Prod
- Issue or question description
- Relevant component: Job Server / App Server / Sync Editor / Portal / Designer / DB
