-- ============================================================
-- Script   : 06_top_mean_exec_time_queries.sql
-- Purpose  : Find queries with high average execution time,
--            filtered to meaningful call counts
-- Read-only : Yes
-- ============================================================
-- What it answers:
--   Which queries are slow on average, but only among queries
--   that have been executed enough times to be statistically
--   meaningful?
--
-- Why filter by call count:
--   A query called once that took 60 seconds may be an anomaly —
--   a one-time data load, a maintenance job, or an unusual edge
--   case. Including it distorts the picture of real workload.
--   Filtering to queries with at least 10 or more calls shows
--   patterns that are consistently slow, not just outliers.
--
--   Adjust the calls threshold based on your environment and
--   the time window since statistics were last reset.
-- ============================================================

SELECT
    pss.userid::regrole                         AS db_user,
    pss.dbid::regdatabase                       AS database_name,
    pss.calls,
    round(pss.mean_exec_time::numeric, 2)       AS mean_exec_ms,
    round(pss.min_exec_time::numeric, 2)        AS min_exec_ms,
    round(pss.max_exec_time::numeric, 2)        AS max_exec_ms,
    round(pss.stddev_exec_time::numeric, 2)     AS stddev_exec_ms,
    round(pss.total_exec_time::numeric, 2)      AS total_exec_ms,
    pss.rows,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
WHERE pss.calls >= 10                           -- adjust threshold as needed
ORDER BY pss.mean_exec_time DESC
LIMIT 20;

-- ============================================================
-- stddev_exec_ms: a high standard deviation relative to the
-- mean suggests inconsistent execution times. This can point
-- to parameter sniffing-like issues, lock waits, or data
-- distribution problems affecting plan quality.
--
-- Example: mean = 50ms, stddev = 200ms likely means the query
-- is fast most of the time but occasionally very slow.
--
-- For PostgreSQL 12 and earlier, replace:
--   mean_exec_time   ->  mean_time
--   min_exec_time    ->  min_time
--   max_exec_time    ->  max_time
--   stddev_exec_time ->  stddev_time
--   total_exec_time  ->  total_time
-- ============================================================
