# 05 — SQL Agent

Scripts for monitoring SQL Server Agent jobs: failed jobs, duration anomalies, and disabled jobs or schedules.

All scripts in this folder are **read-only**.

---

## Scripts

| File | Purpose |
|---|---|
| `failed-sql-agent-jobs-last-24h.sql` | Failed jobs in the last 24 hours with step name, error, and duration |
| `long-running-sql-agent-jobs.sql` | Jobs whose current or recent duration exceeds their historical average |
| `disabled-jobs-and-schedules.sql` | All disabled jobs and disabled schedules |

---

## When to Use

- As part of a daily morning check to verify overnight jobs succeeded
- When investigating a data freshness or ETL issue
- When a job is running significantly longer than usual
- When auditing SQL Agent configuration

## Permissions Required

- `SELECT` on `msdb.dbo.sysjobs`, `msdb.dbo.sysjobhistory`, `msdb.dbo.sysjobactivity`, `msdb.dbo.sysschedules`
- Members of the `SQLAgentReaderRole` in msdb have these permissions
- sysadmin has full access

## SQL Server Version Compatibility

- All scripts: SQL Server 2008 and later
- `msdb.dbo.sysjobactivity` is available from SQL Server 2008

## Safety Level

**Read-only** — All scripts query msdb tables only.
