# PostgreSQL pg_stat_statements Monitoring Toolkit

## Overview

`pg_stat_statements` is a PostgreSQL extension that tracks execution statistics for every query the database runs. It aggregates data across executions — call count, total and mean execution time, rows returned, block I/O — and makes it queryable through a view.

It helps answer questions that are otherwise difficult to answer without instrumentation:

- Which queries are consuming the most total execution time?
- Which queries are slow on average?
- Which queries are executed too frequently?
- Which queries are causing I/O pressure?
- Which queries are worth tuning first?

---

## Why This Matters

Without query-level statistics, PostgreSQL performance tuning is largely guesswork. You might optimize a query that runs twice a day while missing a simpler query that runs two million times. `pg_stat_statements` shows you where the database actually spends its time, based on real workload data rather than assumptions.

It is one of the first extensions worth enabling on any PostgreSQL instance used in production.

---

## What This Project Includes

| File | Purpose |
|---|---|
| `01_enable_pg_stat_statements.sql` | Enable the extension and verify it is working |
| `02_top_slow_queries.sql` | Queries with the highest mean execution time |
| `03_top_total_time_queries.sql` | Queries consuming the most cumulative execution time |
| `04_top_frequently_executed_queries.sql` | Most frequently called queries |
| `05_top_io_heavy_queries.sql` | Queries with high block read, write, or temp spill activity |
| `06_top_mean_exec_time_queries.sql` | Slow queries filtered to meaningful call counts |
| `07_reset_statistics.sql` | Reset statistics — destructive, use with care |

All scripts except `01` and `07` are read-only.

---

## Requirements

- PostgreSQL (scripts tested against PG 13+; notes included for PG 12 column differences)
- `pg_stat_statements` listed in `shared_preload_libraries` in `postgresql.conf`
- PostgreSQL service restart required after adding to `shared_preload_libraries`
- `CREATE EXTENSION` requires superuser or `CREATE` privilege on the target database
- Querying `pg_stat_statements` requires `pg_monitor` role or superuser

---

## How to Enable pg_stat_statements

### Step 1 — Edit postgresql.conf

```
shared_preload_libraries = 'pg_stat_statements'
```

If other libraries are already listed, append it:

```
shared_preload_libraries = 'existing_lib,pg_stat_statements'
```

Optional tuning (can be set without restart):

```
pg_stat_statements.max   = 10000   # maximum number of tracked statements
pg_stat_statements.track = all     # all | top | none
```

### Step 2 — Restart PostgreSQL

```bash
# systemd
sudo systemctl restart postgresql

# or pg_ctlcluster (Debian/Ubuntu)
sudo pg_ctlcluster 15 main restart
```

### Step 3 — Create the extension

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### Step 4 — Verify

```sql
SELECT count(*) FROM pg_stat_statements;
```

If it returns a row count without error, the extension is active and collecting data.

---

## Useful Queries

### 02 — Top Slow Queries (by mean execution time)

Queries ordered by average execution time per call. Filtered to queries with at least 5 calls to reduce one-off noise.

```sql
SELECT
    pss.userid::regrole                         AS db_user,
    pss.dbid::regdatabase                       AS database_name,
    pss.calls,
    round(pss.mean_exec_time::numeric, 2)       AS mean_exec_ms,
    round(pss.min_exec_time::numeric, 2)        AS min_exec_ms,
    round(pss.max_exec_time::numeric, 2)        AS max_exec_ms,
    round(pss.total_exec_time::numeric, 2)      AS total_exec_ms,
    pss.rows,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
WHERE pss.calls >= 5
ORDER BY pss.mean_exec_time DESC
LIMIT 20;
```

---

### 03 — Top Total Time Queries

Queries consuming the most cumulative execution time. This is usually the most actionable starting point. A query at 40% of total tracked time is almost always worth investigating first, regardless of its mean execution time.

```sql
SELECT
    pss.userid::regrole                         AS db_user,
    pss.dbid::regdatabase                       AS database_name,
    pss.calls,
    round(pss.total_exec_time::numeric, 2)      AS total_exec_ms,
    round(
        pss.total_exec_time / nullif(sum(pss.total_exec_time) OVER (), 0) * 100,
        2
    )                                           AS pct_of_total_time,
    round(pss.mean_exec_time::numeric, 2)       AS mean_exec_ms,
    pss.rows,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
ORDER BY pss.total_exec_time DESC
LIMIT 20;
```

---

### 04 — Top Frequently Executed Queries

Queries ordered by call count. A fast query called millions of times can generate more total load than an occasionally slow one. Low `avg_rows_per_call` with very high call counts may also indicate an N+1 query pattern at the application level.

```sql
SELECT
    pss.userid::regrole                         AS db_user,
    pss.dbid::regdatabase                       AS database_name,
    pss.calls,
    round(pss.total_exec_time::numeric, 2)      AS total_exec_ms,
    round(pss.mean_exec_time::numeric, 2)       AS mean_exec_ms,
    pss.rows,
    round(pss.rows::numeric / nullif(pss.calls, 0), 2) AS avg_rows_per_call,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
ORDER BY pss.calls DESC
LIMIT 20;
```

---

### 05 — Top I/O-Heavy Queries

Queries sorted by block reads and temp block writes. High `shared_blks_read` means data is not being served from shared buffers. High `temp_blks_written` usually means a sort or hash operation spilled to disk due to insufficient `work_mem`.

`blk_read_time` and `blk_write_time` are only populated when `track_io_timing = on`.

```sql
SELECT
    pss.userid::regrole                                         AS db_user,
    pss.dbid::regdatabase                                       AS database_name,
    pss.calls,
    pss.shared_blks_hit,
    pss.shared_blks_read,
    pss.shared_blks_written,
    pss.temp_blks_read,
    pss.temp_blks_written,
    round(pss.blk_read_time::numeric, 2)                        AS blk_read_ms,
    round(pss.blk_write_time::numeric, 2)                       AS blk_write_ms,
    round(
        pss.shared_blks_hit::numeric /
        nullif(pss.shared_blks_hit + pss.shared_blks_read, 0) * 100,
        2
    )                                                           AS cache_hit_pct,
    left(pss.query, 200)                                        AS query_text
FROM pg_stat_statements pss
WHERE (pss.shared_blks_read + pss.shared_blks_written + pss.temp_blks_written) > 0
ORDER BY (pss.shared_blks_read + pss.temp_blks_written) DESC
LIMIT 20;
```

---

### 06 — Top Mean Exec Time (filtered)

Similar to script 02, but includes `stddev_exec_time` to surface queries with inconsistent execution times. A high standard deviation relative to the mean often points to lock contention, plan instability, or data skew.

```sql
SELECT
    pss.userid::regrole                         AS db_user,
    pss.dbid::regdatabase                       AS database_name,
    pss.calls,
    round(pss.mean_exec_time::numeric, 2)       AS mean_exec_ms,
    round(pss.stddev_exec_time::numeric, 2)     AS stddev_exec_ms,
    round(pss.min_exec_time::numeric, 2)        AS min_exec_ms,
    round(pss.max_exec_time::numeric, 2)        AS max_exec_ms,
    round(pss.total_exec_time::numeric, 2)      AS total_exec_ms,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
WHERE pss.calls >= 10
ORDER BY pss.mean_exec_time DESC
LIMIT 20;
```

---

### 07 — Reset Statistics

> **Warning:** This is destructive. `pg_stat_statements_reset()` permanently removes all accumulated statistics. Do not run it without a deliberate reason.

All reset options are commented out in the script file. Review `07_reset_statistics.sql` before using it.

---

## How to Interpret the Results

| Signal | What it likely means |
|---|---|
| High `total_exec_time` | Tune this first — it affects the system most |
| High `mean_exec_time` | The query itself is slow, check the plan |
| High `calls` | Application may be over-querying; check for N+1 patterns |
| High `rows` | Large result sets — check if all rows are actually needed |
| High `shared_blks_read` | Data not in shared buffers; possible I/O pressure |
| High `temp_blks_written` | Sort or hash spill; consider index or `work_mem` review |
| High `stddev_exec_time` | Inconsistent performance; check for lock waits or plan changes |
| Low `cache_hit_pct` | Query not benefiting from buffer cache |

Query text in `pg_stat_statements` is normalized — literal values are replaced with `$1`, `$2`, etc. You will not see the exact parameter values used at runtime.

---

## Common Mistakes

- Looking only at mean execution time and ignoring call count
- Ignoring total execution time, which shows real system impact
- Resetting statistics too frequently and losing baseline data
- Tuning a rare query while ignoring high-frequency workload
- Not reviewing the execution plan after identifying a problem query
- Treating one-off queries (calls = 1) as representative of ongoing performance
- Forgetting that column names differ between PostgreSQL versions

---

## Limitations

- `pg_stat_statements` does not show execution plans — use `EXPLAIN` or `EXPLAIN ANALYZE` after identifying a query
- It requires a PostgreSQL restart to enable for the first time
- Column names differ between PostgreSQL 12 and 13+: `total_time` / `mean_time` vs `total_exec_time` / `mean_exec_time`
- Statistics are cumulative since the last reset; context matters when interpreting numbers
- The `pg_stat_statements.max` setting limits how many distinct normalized queries are tracked; beyond that limit, older entries are evicted
- It does not record individual query executions — only aggregates

---

## Recommended Next Steps

After identifying a problematic query:

1. Run `EXPLAIN (ANALYZE, BUFFERS)` on the query — carefully, and ideally outside peak hours
2. Check whether appropriate indexes exist for the filter and join columns
3. Compare estimated vs actual row counts in the plan — large discrepancies often indicate stale statistics
4. Review join order, sort operations, and hash batches
5. Check whether the application is querying more rows than it needs
6. Review whether the query is called too often and whether caching or batching is appropriate

---

## References

- [pg_stat_statements — PostgreSQL Documentation](https://www.postgresql.org/docs/current/pgstatstatements.html)
- [EXPLAIN — PostgreSQL Documentation](https://www.postgresql.org/docs/current/sql-explain.html)
- [Monitoring Database Activity — PostgreSQL Documentation](https://www.postgresql.org/docs/current/monitoring-stats.html)
- [Runtime Statistics — PostgreSQL Documentation](https://www.postgresql.org/docs/current/runtime-config-statistics.html)
