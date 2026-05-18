# SQL Server Scripts

T-SQL scripts for SQL Server administration, organized by area. Each subfolder has its own README covering what the scripts do, when to use them, required permissions, and safety level.

---

## Script Categories

| Folder | Purpose | Safety Level |
|---|---|---|
| [monitoring](./monitoring/) | Current activity, wait statistics, session resource usage | Read-only |
| [performance](./performance/) | Plan cache analysis, missing indexes, index fragmentation | Read-only |
| [blocking-and-sessions](./blocking-and-sessions/) | Blocking chains, sleeping sessions with open transactions, KILL generator | Read-only / Generates commands only |
| [backup-and-maintenance](./backup-and-maintenance/) | Backup history, missing backups, duration trends, restore history | Read-only |
| [sql-agent](./sql-agent/) | Failed jobs, long-running jobs, disabled schedules | Read-only |
| [tempdb](./tempdb/) | TempDB space usage, session allocations, file move generator | Read-only / Generates commands only |
| [security-and-permissions](./security-and-permissions/) | Server roles, database owners, orphaned users | Read-only |
| [health-checks](./health-checks/) | File growth settings, compatibility levels, VLF counts, disk space | Read-only |
| [Find blocking processes](./Find%20blocking%20processes/) | Blocking process detection scripts | Read-only |
| [SQL Server Backup Status & Duration Monitoring View](./SQL%20Server%20Backup%20Status%20%26%20Duration%20Monitoring%20View/) | Centralized backup monitoring view built on Redgate SQL Monitor — aggregates backup freshness, file references, and duration trends across all monitored instances | Read-only |

---

## Safety Level Reference

| Level | What It Means |
|---|---|
| **Read-only** | Queries system views, DMVs, or msdb only. No changes made to the server. Safe to run on production. |
| **Generates commands only** | Produces T-SQL output (e.g. KILL, ALTER DATABASE) but does not execute it. Review all output before running. |
| **Changes server state** | Modifies server or database configuration. Not the default behavior of any script in this repository. |
