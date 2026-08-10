# oim-copilot-assistant

A GitHub Copilot-powered assistant repository for teams managing **Quest One Identity Manager (OIM)** implementations, upgrades, and day-to-day operations.

## Purpose

This repository provides:
- Custom Copilot instructions and agent configuration for OIM expertise
- Troubleshooting, upgrade, SQL, and scripting skill guides
- Issue card and session log templates
- A shared knowledge base of known issues and SQL snippets

## Repository Structure

```
oim-copilot-assistant/
├── .github/
│   ├── copilot-instructions.md     # Copilot custom instructions
│   └── agents/
│       └── oim-expert.agent.md     # OIM Expert agent definition
├── docs/
│   ├── skills/                     # Skill guides for common tasks
│   │   ├── troubleshooting-guide.md
│   │   ├── upgrade-guide.md
│   │   ├── sql-query-guide.md
│   │   └── scripting-guide.md
│   └── templates/                  # Reusable document templates
│       ├── issue-card-template.md
│       └── session-log-template.md
├── session-logs/                   # Team session logs (use template)
├── knowledge-base/                 # Shared knowledge repository
│   ├── known-issues.md
│   ├── version-matrix.md
│   └── sql-snippets.md
├── .gitignore
└── README.md
```

## Getting Started

1. **Confirm your OIM version** before every Copilot session (8.x / 9.0 / 9.1 / 9.2 / 9.3+)
2. **Use the OIM Expert agent** (`@oim-expert`) for version-aware technical assistance
3. **Log every session** using `/docs/templates/session-log-template.md`
4. **Raise issues** using `/docs/templates/issue-card-template.md`
5. **Contribute** resolved issues and SQL snippets back to `/knowledge-base/`

## Safety Rules

- ⚠️ Always flag production-impacting steps before executing
- Never commit credentials, connection strings, server names, or IP addresses
- Always have a rollback plan before making DB or schema changes
- Follow change management approval for all Prod changes

## Reference Sources

1. [support.oneidentity.com](https://support.oneidentity.com) — official KB articles
2. [community.oneidentity.com](https://community.oneidentity.com) — community solutions
3. Quest One Identity official documentation portal
4. `/knowledge-base/` — team knowledge base

---

## Previous Content: OIM 9.2.2 → 9.3.3 Upgrade – VB.NET Script Fixes

This document describes the script fixes applied to resolve compilation errors and logic bugs when upgrading from **One Identity Manager (OIM) 9.2.2** to **9.3.3** on **.NET 8.0**.

---

## File 1 – `CCC_Person_Domain`

### Change: `orgPath.Count` → `orgPath.Length`

**Problem:**  
`.Count` is a LINQ extension method that is not reliably resolved by the OIM script compiler under .NET 8.0. This caused a hard compile failure.

**Fix:**  
Replaced `.Count` with `.Length`, which is the native array property and is always available without LINQ resolution.

```vbnet
' Before
If orgPath.Count >= depth Then

' After
If orgPath.Length >= depth Then
```

---

## File 2 – `CCC_AE_CreatedefaultMailAddress` / `CCC_AE_CreatedefaultMailAddress_NameChangeExist`

### Change 1: `.Bool` accessor removed → `Convert.ToBoolean(...)`

**Problem:**  
In OIM 9.3, `GetSingleProperty` returns `Object`. The legacy `.Bool` accessor no longer exists, causing a compile failure.

**Initial Fix (caused secondary error):**  
`Convert.ToBoolean(Object)` was ambiguous — the VB.NET compiler could not resolve which overload to use among `ToBoolean(String)`, `ToBoolean(Integer)`, `ToBoolean(Object)`, etc., resulting in:
> `Overload resolution failed because no accessible 'ToBoolean' is most specific for these arguments`

**Final Fix:**  
Call `.ToString()` on the result first to resolve the `Object` to a `String`, removing all ambiguity before passing to `Convert.ToBoolean`:

```vbnet
' Before (original – legacy accessor)
Dim mailLocked As Boolean = Connection.GetSingleProperty("Person", "CCC_EmailLocked", ...).Bool

' Intermediate fix (caused overload resolution error)
Dim mailLocked As Boolean = Convert.ToBoolean(Connection.GetSingleProperty("Person", "CCC_EmailLocked", ...))

' Final fix (applied)
Dim mailLocked As Boolean = Convert.ToBoolean(Connection.GetSingleProperty("Person", "CCC_EmailLocked", ...).ToString())
```

---

### Change 2: Mixed implicit/explicit return style fixed

**Problem:**  
The function used a VB6-style assignment (`CCC_AE_CreatedefaultMailAddress = String.Empty`) combined with `Exit Function`, which is inconsistent with the rest of the function that uses `Return`.

**Fix:**  
Replaced with `Return String.Empty` for consistent, modern VB.NET style.

```vbnet
' Before
CCC_AE_CreatedefaultMailAddress = String.Empty
Exit Function

' After
Return String.Empty
```

---

### Change 3: Inverted null guard fixed

**Problem:**  
The condition `If String.IsNullOrEmpty(uid_person)` was logically inverted. The exclusion clause was only being appended when `uid_person` was null/empty, making it a no-op and silently skipping the intended filter.

**Fix:**  
Changed to `If Not String.IsNullOrEmpty(uid_person)` to correctly apply the filter when a value is present.

```vbnet
' Before
If String.IsNullOrEmpty(uid_person) Then
    whereClause &= " AND NOT uid_person = '" & uid_person & "'"
End If

' After
If Not String.IsNullOrEmpty(uid_person) Then
    whereClause &= " AND NOT uid_person = '" & uid_person & "'"
End If
```

---

## Summary of Changes

| File | Change | Type |
|------|--------|------|
| `CCC_Person_Domain` (File 1) | `.Count` → `.Length` on array | Compile fix |
| `CCC_AE_CreatedefaultMailAddress` (File 2) | `.Bool` → `Convert.ToBoolean(...ToString())` — resolves overload ambiguity on .NET 8.0 | Compile fix |
| `CCC_AE_CreatedefaultMailAddress` (File 2) | VB6-style return (`= String.Empty` + `Exit Function`) → `Return String.Empty` | Style / compile fix |
| `CCC_AE_CreatedefaultMailAddress_NameChangeExist` (File 2) | Inverted null guard corrected (`IsNullOrEmpty` → `Not IsNullOrEmpty`) | Logic bug fix |
