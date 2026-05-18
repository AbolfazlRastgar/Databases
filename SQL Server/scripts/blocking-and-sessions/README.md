# 03 — Blocking and Sessions

Scripts for identifying blocking chains, sleeping sessions holding open transactions, and generating KILL commands for review.

---

## Scripts

| File | Purpose | Safety Level |
|---|---|---|
| `find-blocking-chain.sql` | Maps blocking relationships and identifies the head blocker | Read-only |
| `who-is-blocking-everyone.sql` | Summarizes which session is blocking the most others | Read-only |
| `sleeping-sessions-with-open-transactions.sql` | Finds idle sessions that still hold open transactions | Read-only |
| `kill-command-generator.sql` | Generates KILL statements — does not execute them | Generates commands only |

---

## sp_WhoIsActive

The [sp_WhoIsActive-usage/](./sp_WhoIsActive-usage/) subfolder contains usage examples for Adam Machanic's `sp_WhoIsActive` stored procedure. `sp_WhoIsActive` is a widely-used, community-standard tool for monitoring active sessions and is significantly more capable than querying DMVs directly for day-to-day troubleshooting.

---

## When to Use

- When an application is reporting timeouts or slowdowns due to blocking
- When lock waits are visible in wait statistics
- When a session needs to be terminated as a last resort

## Permissions Required

- `VIEW SERVER STATE` for DMV access
- `sysadmin` or `ALTER ANY CONNECTION` to execute KILL (not done by these scripts)

## SQL Server Version Compatibility

- All scripts: SQL Server 2008 R2 and later
- Blocking chain CTE logic: SQL Server 2005 and later

## Safety Level

- Most scripts: **Read-only**
- `kill-command-generator.sql`: **Generates commands only** — never executes KILL automatically
