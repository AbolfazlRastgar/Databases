# 04 — Backup and Maintenance

Scripts for monitoring SQL Server backup history, identifying databases without recent backups, analyzing backup duration trends, and reviewing restore history.

All scripts in this folder query `msdb` tables and are **read-only**.

---

## Scripts

| File | Purpose | Safety Level |
|---|---|---|
| `backup-status-last-7-days.sql` | Full/diff/log backup status, sizes, and paths for the last 7 days | Read-only |
| `databases-without-recent-backup.sql` | Databases missing full, diff, or log backups within configurable thresholds | Read-only |
| `backup-duration-trend.sql` | Backup duration trend from msdb history | Read-only |
| `restore-history.sql` | Recent restore operations from msdb | Read-only |

---

## Ola Hallengren Maintenance Solution

The [ola-hallengren-maintenance/](./ola-hallengren-maintenance/) subfolder contains notes and example job scripts for Ola Hallengren's SQL Server Maintenance Solution — the community standard for backup, integrity check, and index maintenance on SQL Server.

---

## When to Use

- During daily DBA health checks to confirm backups completed
- After a backup failure alert to understand what happened
- When validating that RPO (recovery point objective) requirements are being met
- Before a restore operation to identify the most recent available backups

## Permissions Required

- `SELECT` on `msdb.dbo.backupset`, `msdb.dbo.backupmediafamily`, and `msdb.dbo.restorehistory`
- Members of `sysadmin` or `db_datareader` in msdb have this by default

## SQL Server Version Compatibility

- All scripts: SQL Server 2008 and later
- `backup_finish_date`, `compressed_backup_size`, and related columns: SQL Server 2008 and later

## Safety Level

**Read-only** — All scripts query msdb history only.
