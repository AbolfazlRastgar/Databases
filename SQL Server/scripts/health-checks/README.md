# 08 — Health Checks

Scripts for routine SQL Server health checks: file growth settings, compatibility levels, VLF counts, and disk space.

All scripts in this folder are **read-only**.

---

## Scripts

| File | Purpose |
|---|---|
| `database-file-growth-settings.sql` | File sizes, autogrowth settings, and flags for percentage-based growth |
| `database-compatibility-levels.sql` | Compatibility levels, recovery models, page verify, auto close, auto shrink |
| `high-vlf-count-check.sql` | VLF count per database, with context on why high VLF counts matter |
| `disk-space-overview.sql` | Drive capacity, free space, and database files per volume |

---

## When to Use

- During regular health check routines (weekly or monthly)
- When setting up a new SQL Server instance
- When investigating log file growth, slow recovery, or disk space issues
- When preparing for an upgrade or migration

## Permissions Required

- `VIEW SERVER STATE` for `sys.dm_os_volume_stats` and VLF-related queries
- `VIEW ANY DATABASE` for `sys.databases`
- `VIEW DATABASE STATE` for per-database file queries

## SQL Server Version Compatibility

- `sys.dm_os_volume_stats`: SQL Server 2008 R2 SP1 and later
- `sys.dm_db_log_info` (for VLF details): SQL Server 2016 SP2 and later
  - For older versions, `DBCC LOGINFO` is used as a fallback
- All other scripts: SQL Server 2008 and later

## Safety Level

**Read-only** — No changes are made to the server.
