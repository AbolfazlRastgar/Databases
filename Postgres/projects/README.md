# PostgreSQL pg_stat_statements Monitoring Toolkit

## Overview

`pg_stat_statements` is a PostgreSQL extension that tracks execution statistics for every normalized query the database runs. It aggregates call count, execution time, rows returned, and block I/O — and makes all of it queryable through a single view.

It helps answer the questions that actually matter during a performance investigation:

- Which queries are consuming the most total execution time?
- Which queries are slow on average?
- Which queries are called too often?
- Which queries are causing I/O pressure?
- Which query is fast most of the time but occasionally takes seconds?

---

## Why This Matters

Without `pg_stat_statements`, PostgreSQL performance tuning is largely guesswork. You might optimize a query that runs twice a day while missing one that runs two million times. This extension shows where the database actually spends its time, based on real workload data accumulated since the last reset.

It is one of the first extensions worth enabling on any PostgreSQL instance used in production.

---

## Project Files

| File | Purpose |
|---|---|
| `01_enable_pg_stat_statements.sql` | Enable the extension and verify it is collecting data |
| `02_top_slow_queries.sql` | Queries with the highest mean execution time |
| `03_top_total_time_queries.sql` | Queries consuming the most cumulative execution time |
| `04_top_frequently_executed_queries.sql` | Most frequently called queries |
| `05_top_io_heavy_queries.sql` | Queries with high block read or temp spill activity |
| `06_top_variable_exec_time_queries.sql` | Queries with inconsistent / unpredictable execution time |
| `07_reset_statistics.sql` | Reset statistics — destructive, requires superuser |

Scripts `02` through `06` are read-only. Scripts `01` and `07` modify state.

---

## Requirements

- PostgreSQL (scripts target PG 13+; column aliases for PG 12 noted in each file)
- `pg_stat_statements` in `shared_preload_libraries` — requires a service restart to take effect
- `CREATE EXTENSION` requires superuser or `CREATE` privilege on the target database
- Querying `pg_stat_statements` requires `pg_monitor` or superuser
- Calling `pg_stat_statements_reset()` requires **superuser** — `pg_monitor` alone is not sufficient

---

## How to Enable

### 1. Add to postgresql.conf

```
shared_preload_libraries = 'pg_stat_statements'
```

If other libraries are already listed, append:

```
shared_preload_libraries = 'existing_lib,pg_stat_statements'
```

Optional (no restart required once the extension is loaded):

```
pg_stat_statements.max   = 10000   -- max tracked statements
pg_stat_statements.track = all     -- top | all | none
```

### 2. Restart PostgreSQL

```bash
# systemd
sudo systemctl restart postgresql

# Debian/Ubuntu with pg_ctlcluster
sudo pg_ctlcluster 15 main restart
```

### 3. Create the extension

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### 4. Verify

```sql
SELECT count(*) FROM pg_stat_statements;
```

A non-zero result means the extension is active and collecting data.

---

## Queries

### 02 — Top Slow Queries (mean execution time)

Use when users report slow responses or timeouts. Shows which queries are slowest per individual execution. Cross-reference with script `03` — a slow query called rarely may matter less than a moderately slow one called constantly.

Filters to queries with at least 20 calls to reduce one-off noise.

```sql
SELECT
    pss.userid::regrole                                    AS db_user,
    pss.dbid::regdatabase                                  AS database_name,
    pss.calls,
    round(pss.mean_exec_time::numeric,  2)                 AS mean_exec_ms,
    round(pss.min_exec_time::numeric,   2)                 AS min_exec_ms,
    round(pss.max_exec_time::numeric,   2)                 AS max_exec_ms,
    round(pss.total_exec_time::numeric, 2)                 AS total_exec_ms,
    pss.rows,
    round(pss.rows::numeric / nullif(pss.calls, 0), 2)    AS avg_rows_per_call,
    left(pss.query, 200)                                   AS query_text
FROM pg_stat_statements pss
WHERE pss.calls >= 20
ORDER BY pss.mean_exec_time DESC
LIMIT 20;
```

---

### 03 — Top Total Time Queries

Start here in most investigations. Total execution time shows cumulative load — where the database is actually spending its time across all executions since the last reset.

`pct_of_total_time` is calculated over all tracked statements, not just the top 20.

```sql
SELECT
    pss.userid::regrole                                        AS db_user,
    pss.dbid::regdatabase                                      AS database_name,
    pss.calls,
    round(pss.total_exec_time::numeric, 2)                     AS total_exec_ms,
    round(
        pss.total_exec_time
        / nullif(sum(pss.total_exec_time) OVER (), 0) * 100
    , 2)                                                       AS pct_of_total_time,
    round(pss.mean_exec_time::numeric, 2)                      AS mean_exec_ms,
    round(pss.max_exec_time::numeric,  2)                      AS max_exec_ms,
    pss.rows,
    left(pss.query, 200)                                       AS query_text
FROM pg_stat_statements pss
ORDER BY pss.total_exec_time DESC
LIMIT 20;
```

---

### 04 — Top Frequently Executed Queries

Use when total execution time looks normal but the database still feels under load, or when you want to understand call volume patterns.

`avg_rows_per_call` close to 1 with millions of calls often signals an N+1 query pattern at the application level.

```sql
SELECT
    pss.userid::regrole                                    AS db_user,
    pss.dbid::regdatabase                                  AS database_name,
    pss.calls,
    round(pss.total_exec_time::numeric, 2)                 AS total_exec_ms,
    round(pss.mean_exec_time::numeric,  2)                 AS mean_exec_ms,
    round(pss.max_exec_time::numeric,   2)                 AS max_exec_ms,
    pss.rows,
    round(pss.rows::numeric / nullif(pss.calls, 0), 2)    AS avg_rows_per_call,
    left(pss.query, 200)                                   AS query_text
FROM pg_stat_statements pss
ORDER BY pss.calls DESC
LIMIT 20;
```

---

### 05 — Top I/O-Heavy Queries

Use when disk I/O appears to be a bottleneck or queries are slower than their plan suggests.

`shared_blks_read` means data was not served from shared buffers — it came from disk or OS cache. `temp_blks_written` means a sort or hash operation spilled to disk, usually due to insufficient `work_mem`.

`blk_read_time` and `blk_write_time` are only populated when `track_io_timing = on`. If both show 0, I/O timing is disabled.

```sql
SELECT
    pss.userid::regrole                                            AS db_user,
    pss.dbid::regdatabase                                         AS database_name,
    pss.calls,
    pss.shared_blks_hit,
    pss.shared_blks_read,
    pss.shared_blks_dirtied,
    pss.shared_blks_written,
    pss.temp_blks_read,
    pss.temp_blks_written,
    round(pss.blk_read_time::numeric,  2)                         AS blk_read_ms,
    round(pss.blk_write_time::numeric, 2)                         AS blk_write_ms,
    round(
        pss.shared_blks_hit::numeric
        / nullif(pss.shared_blks_hit + pss.shared_blks_read, 0) * 100
    , 2)                                                          AS cache_hit_pct,
    round(pss.total_exec_time::numeric, 2)                        AS total_exec_ms,
    left(pss.query, 200)                                          AS query_text
FROM pg_stat_statements pss
WHERE (pss.shared_blks_read + pss.temp_blks_written) > 0
ORDER BY (pss.shared_blks_read + pss.temp_blks_written) DESC
LIMIT 20;
```

---

### 06 — Top Variable Execution Time Queries

Use when users report a query that is sometimes fast and sometimes slow, or when you see intermittent timeouts on the same operation.

This is the script that script `02` misses. A query with `mean = 40ms` looks fine — but if `stddev = 400ms`, it is occasionally taking seconds. `variability_ratio = stddev / mean`: above 1.0 is worth noting, above 3.0 something external is likely interfering (lock waits, checkpoint activity, plan instability).

Only queries with at least 50 calls are included — below that, stddev is not yet meaningful.

```sql
SELECT
    pss.userid::regrole                                    AS db_user,
    pss.dbid::regdatabase                                  AS database_name,
    pss.calls,
    round(pss.mean_exec_time::numeric,   2)                AS mean_exec_ms,
    round(pss.stddev_exec_time::numeric, 2)                AS stddev_exec_ms,
    round(
        pss.stddev_exec_time / nullif(pss.mean_exec_time, 0)
    , 2)                                                   AS variability_ratio,
    round(pss.min_exec_time::numeric,    2)                AS min_exec_ms,
    round(pss.max_exec_time::numeric,    2)                AS max_exec_ms,
    round(pss.total_exec_time::numeric,  2)                AS total_exec_ms,
    left(pss.query, 200)                                   AS query_text
FROM pg_stat_statements pss
WHERE pss.calls >= 50
  AND pss.stddev_exec_time > pss.mean_exec_time
ORDER BY pss.stddev_exec_time DESC
LIMIT 20;
```

---

### 07 — Reset Statistics

> **This is destructive and cannot be undone.** All options are commented out. Read the script before uncommenting anything.
>
> Required privilege: **superuser**. The `pg_monitor` role can read `pg_stat_statements` but cannot reset it.

The script includes a summary query to show what would be lost before resetting.

---

## Interpreting Results

| Signal | What to check |
|---|---|
| High `total_exec_time` | Start here. Tune this before anything else. |
| High `mean_exec_time` | Run `EXPLAIN (ANALYZE, BUFFERS)` on the query |
| High `calls` + low `avg_rows_per_call` | Possible N+1 pattern at the application level |
| High `shared_blks_read` | Query not hitting shared buffers — check indexes and `shared_buffers` |
| High `temp_blks_written` | Sort or hash spill — check `work_mem` and indexes on ORDER BY / GROUP BY columns |
| High `variability_ratio` | Check for lock contention, autovacuum, or plan instability |
| Low `cache_hit_pct` | Query is reading from disk frequently — may benefit from index or larger `shared_buffers` |

Query text in `pg_stat_statements` is normalized. Literal values are replaced with `$1`, `$2`, etc. You will not see the exact parameter values used at runtime.

---

## Common Mistakes

- Tuning based on mean execution time alone, while ignoring call count and total time
- Resetting statistics during an investigation and losing the data you were analyzing
- Treating a query called once as representative of a performance problem
- Not running `EXPLAIN (ANALYZE, BUFFERS)` after identifying a candidate query
- Forgetting that the statistics window depends on when the last reset happened — a week of data and a day of data look very different

---

## Limitations

- Does not show execution plans — use `EXPLAIN` or `EXPLAIN ANALYZE` after identifying a query
- Requires a service restart to enable for the first time
- Column names differ between PostgreSQL 12 and 13+ (noted in each script)
- Statistics are cumulative since the last reset; interpret numbers with that window in mind
- The `pg_stat_statements.max` setting caps how many distinct normalized queries are tracked; beyond that, older entries are evicted

---

## Next Steps After Identifying a Query

1. Run `EXPLAIN (ANALYZE, BUFFERS)` — carefully, and outside peak hours if the query is resource-heavy
2. Check whether appropriate indexes exist for filter, join, and sort columns
3. Compare estimated vs actual row counts — large discrepancies indicate stale statistics or data skew
4. Check whether the application is fetching more data than it needs
5. If the query is called too often, consider whether batching or caching is appropriate at the application level

---

## References

- [pg_stat_statements — PostgreSQL Documentation](https://www.postgresql.org/docs/current/pgstatstatements.html)
- [EXPLAIN — PostgreSQL Documentation](https://www.postgresql.org/docs/current/sql-explain.html)
- [Cumulative Statistics System — PostgreSQL Documentation](https://www.postgresql.org/docs/current/monitoring-stats.html)
- [Runtime Statistics Configuration](https://www.postgresql.org/docs/current/runtime-config-statistics.html)
