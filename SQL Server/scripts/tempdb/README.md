# 06 — TempDB

Scripts for monitoring TempDB space usage, identifying sessions consuming TempDB, and generating file move commands.

---

## Scripts

| File | Purpose | Safety Level |
|---|---|---|
| `tempdb-space-usage.sql` | TempDB file usage, version store, user objects, internal objects, free space | Read-only |
| `tempdb-usage-by-session.sql` | Per-session TempDB allocation (user objects + internal objects) | Read-only |
| `move-tempdb-files-generate-script.sql` | Generates ALTER DATABASE commands to move TempDB files — does not execute them | Generates commands only |

---

## When to Use

- When TempDB is filling up or driving disk pressure
- When investigating sort spills, hash spills, or high version store usage
- When setting up a new server or moving TempDB to a dedicated drive

## Permissions Required

- `VIEW SERVER STATE` for TempDB DMVs
- `sysadmin` to execute ALTER DATABASE commands (not done by these scripts)

## SQL Server Version Compatibility

- `sys.dm_db_file_space_usage`: SQL Server 2005 and later
- `sys.dm_db_session_space_usage`: SQL Server 2005 and later

## Safety Level

- Monitoring scripts: **Read-only**
- `move-tempdb-files-generate-script.sql`: **Generates commands only**

## TempDB Best Practices (Reference)

- Place TempDB on a dedicated, fast drive (ideally SSD or NVMe)
- Use multiple data files (one per logical CPU core, up to 8) to reduce allocation contention
- Pre-size TempDB to avoid autogrowth during production hours
- Autogrowth should be fixed size, not percentage-based
