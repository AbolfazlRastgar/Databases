-- ============================================================
-- Script   : 06_top_variable_exec_time_queries.sql
-- Purpose  : Queries with inconsistent / unpredictable execution time
-- Read-only : Yes
-- ============================================================
-- Use this when: a query is sometimes fast and sometimes slow,
-- or when users report intermittent timeouts on the same query.
--
-- This script sorts by stddev_exec_time (standard deviation of
-- execution time). A high stddev relative to the mean indicates
-- the query does not run consistently.
--
-- Common causes of high variability:
--   - Lock waits (query sits idle waiting for a row lock)
--   - Plan instability due to parameter sensitivity
--   - Data skew causing plan effectiveness to vary by input
--   - Autovacuum or checkpoint activity affecting I/O
--
-- Example: mean = 40ms, stddev = 300ms
--   The query is fast most of the time but occasionally takes
--   seconds. This is more actionable than just looking at mean.
--
-- Only queries with at least 50 calls are included. Below that
-- threshold the stddev is not yet meaningful.
--
-- Column note (PostgreSQL version differences):
--   PG 13+  : stddev_exec_time, mean_exec_time, total_exec_time
--   PG 12   : stddev_time, mean_time, total_time
-- ============================================================

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
  AND pss.stddev_exec_time > pss.mean_exec_time           -- stddev exceeds mean: clearly inconsistent
ORDER BY pss.stddev_exec_time DESC
LIMIT 20;

-- ============================================================
-- variability_ratio = stddev / mean
--   > 1.0  : execution time is highly unpredictable
--   > 3.0  : something external is likely interfering
--             (locks, I/O spikes, checkpoint pressure)
-- ============================================================
