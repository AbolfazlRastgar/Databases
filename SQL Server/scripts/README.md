# SQL Server Scripts

This folder contains T-SQL scripts for SQL Server administration, organized by area. Each subfolder has its own README that explains the scripts in detail.

All scripts include a header block documenting purpose, required permissions, SQL Server version compatibility, and safety level.

---

## Script Index

| Category | Folder | Scripts | Safety Level |
|---|---|---|---|
| Monitoring | [01-monitoring](./01-monitoring/) | current-running-requests, long-running-queries, session-resource-usage, wait-stats-snapshot | Read-only |
| Performance | [02-performance](./02-performance/) | top-cpu-queries, top-io-queries, missing-indexes-report, index-fragmentation-report | Read-only |
| Blocking & Sessions | [03-blocking-and-sessions](./03-blocking-and-sessions/) | find-blocking-chain, who-is-blocking-everyone, sleeping-sessions-with-open-transactions | Read-only |
| Blocking & Sessions | [03-blocking-and-sessions](./03-blocking-and-sessions/) | kill-command-generator | Generates commands only |
| Blocking & Sessions | [03-blocking-and-sessions/sp_WhoIsActive-usage](./03-blocking-and-sessions/sp_WhoIsActive-usage/) | basic-usage, find-blocking-chain, capture-to-table | Read-only |
| Backup & Maintenance | [04-backup-and-maintenance](./04-backup-and-maintenance/) | backup-status-last-7-days, databases-without-recent-backup, backup-duration-trend, restore-history | Read-only |
| Backup & Maintenance | [04-backup-and-maintenance/ola-hallengren-maintenance](./04-backup-and-maintenance/ola-hallengren-maintenance/) | example job scripts, commandlog query | Generates commands only / Read-only |
| SQL Agent | [05-sql-agent](./05-sql-agent/) | failed-jobs-last-24h, long-running-jobs, disabled-jobs-and-schedules | Read-only |
| TempDB | [06-tempdb](./06-tempdb/) | tempdb-space-usage, tempdb-usage-by-session | Read-only |
| TempDB | [06-tempdb](./06-tempdb/) | move-tempdb-files-generate-script | Generates commands only |
| Security & Permissions | [07-security-and-permissions](./07-security-and-permissions/) | server-role-members, database-owner-check, orphaned-users-check | Read-only |
| Health Checks | [08-health-checks](./08-health-checks/) | database-file-growth-settings, database-compatibility-levels, high-vlf-count-check, disk-space-overview | Read-only |

---

## Safety Level Reference

| Level | What It Means |
|---|---|
| **Read-only** | Queries system views and DMVs only. No changes made. |
| **Generates commands only** | Produces T-SQL statements as output. Does not execute them. Review output before running. |
| **Changes server state** | Modifies server or database configuration. Not used in this repository by default. |
