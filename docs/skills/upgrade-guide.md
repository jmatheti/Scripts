# OIM Upgrade Guide

## Inputs Required:
- Current OIM Version
- Target OIM Version
- Environment: Dev / UAT / Prod
- Components in scope (Job Server, App Server, Web Portal, Sync Editor, etc.)

## Pre-Upgrade Checklist:
- [ ] Confirm target version release notes reviewed
- [ ] Confirm DB backup taken ⚠️ PRODUCTION RISK
- [ ] Confirm all running jobs are complete or paused
- [ ] Confirm service accounts and permissions documented
- [ ] Confirm rollback plan approved

## Upgrade Order:
1. Database migration (using DB Migration Wizard)
2. Job Server
3. Application Server
4. Web Portal
5. Synchronisation Editor / Manager clients
6. Designer

## Post-Upgrade Validation:
- [ ] Job Server connectivity confirmed
- [ ] Process chains executing correctly
- [ ] Web Portal accessible and loading
- [ ] Synchronisation runs completing without errors
- [ ] Audit log entries appearing as expected

## Rollback Plan:
- Restore DB from pre-upgrade backup ⚠️ PRODUCTION RISK
- Reinstall previous component versions from installer media
- Validate service account permissions post-rollback

## Reference:
- support.oneidentity.com — search for "upgrade guide vX.X"
- Quest One Identity official documentation portal
