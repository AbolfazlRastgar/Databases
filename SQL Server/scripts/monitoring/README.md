# 01 — Monitoring

Scripts for observing active server state: running requests, long-running queries, session resource usage, and wait statistics.

All scripts in this folder are **read-only**. They query DMVs and system catalog views and make no changes to the server.

---

## Scripts

| File | Purpose |
|---|---|
| `current-running-requests.sql` | All currently executing requests with session details, wait info, and SQL text |
| `long-running-queries.sql` | Active queries running longer than a configurable threshold |
| `session-resource-usage.sql` | CPU, memory, I/O, and open transaction count per active session |
| `wait-stats-snapshot.sql` | Server-level wait statistics, filtered to exclude benign waits |

---

## When to Use

- During incidents to identify what is running and what is waiting
- When CPU, memory, or I/O spikes without an obvious cause
- As a first step in any performance investigation

## Permissions Required

- `VIEW SERVER STATE` on the SQL Server instance
- These scripts do not require sysadmin

## SQL Server Version Compatibility

- All scripts are compatible with SQL Server 2012 and later
- `sys.dm_exec_query_statistics` and `sys.dm_exec_requests` have been available since SQL Server 2005
- Notes on version-specific columns are included inside the relevant scripts

## Safety Level

**Read-only** — No changes are made to the server.
