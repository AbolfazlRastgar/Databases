# 02 — Performance

Scripts for query performance analysis using the plan cache and index-related DMVs.

All scripts in this folder are **read-only**. They do not modify any indexes, statistics, or server settings.

---

## Scripts

| File | Purpose |
|---|---|
| `top-cpu-queries-from-plan-cache.sql` | Top CPU-consuming queries from the procedure cache |
| `top-io-queries-from-plan-cache.sql` | Top logical-read and physical-read queries from the procedure cache |
| `missing-indexes-report.sql` | Missing index recommendations from DMVs, with cost impact estimates |
| `index-fragmentation-report.sql` | Index fragmentation data filtered by page count threshold |

---

## When to Use

- When investigating high CPU or I/O on a SQL Server instance
- When a query or workload is performing poorly and you need to identify candidates
- During scheduled performance reviews or after large data changes
- Before deciding whether to add or rebuild indexes

## Permissions Required

- `VIEW SERVER STATE` for plan cache and DMV access
- `VIEW DATABASE STATE` for fragmentation data (per-database)

## SQL Server Version Compatibility

- Plan cache DMVs: SQL Server 2005 and later
- `sys.dm_db_missing_index_*`: SQL Server 2005 and later
- `sys.dm_db_index_physical_stats`: SQL Server 2005 and later

## Safety Level

**Read-only** — No changes are made to the server.

## Important Notes on Missing Indexes

The missing index DMVs (`sys.dm_db_missing_index_*`) provide suggestions based on query execution patterns. These suggestions are **not authoritative**. Before adding any index:
- Verify the query actually matters in terms of business impact and frequency
- Consider existing indexes that cover similar columns
- Evaluate the write overhead the new index will add
- Never add all missing index suggestions blindly
