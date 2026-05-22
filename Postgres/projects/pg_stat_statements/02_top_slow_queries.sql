-- ============================================================
-- Script   : 02_top_slow_queries.sql
-- Purpose  : Find queries with the highest mean execution time
-- Read-only : Yes
-- ============================================================
-- What it answers:
--   Which individual queries are slowest on average?
--
-- When to use:
--   When users report slow response times or timeouts and you
--   want to identify which queries are taking the longest per
--   execution on average.
--
-- Note:
--   Mean execution time alone can be misleading. A query called
--   once that took 30 seconds may matter less than a query
--   called 10,000 times that averages 200ms. Cross-reference
--   with call count and total time.
--
-- Column availability:
--   mean_exec_time / total_exec_time are available in PG 13+.
--   For PG 12 and earlier, use mean_time / total_time instead.
-- ============================================================

SELECT
    pss.userid::regrole                         AS db_user,
    pss.dbid::regdatabase                       AS database_name,
    pss.calls,
    round(pss.mean_exec_time::numeric, 2)       AS mean_exec_ms,
    round(pss.min_exec_time::numeric, 2)        AS min_exec_ms,
    round(pss.max_exec_time::numeric, 2)        AS max_exec_ms,
    round(pss.total_exec_time::numeric, 2)      AS total_exec_ms,
    pss.rows,
    round(pss.rows::numeric / nullif(pss.calls, 0), 2) AS avg_rows_per_call,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
WHERE pss.calls >= 5               -- filter out one-off queries
ORDER BY pss.mean_exec_time DESC
LIMIT 20;

-- ============================================================
-- For PostgreSQL 12 and earlier, replace:
--   mean_exec_time  ->  mean_time
--   min_exec_time   ->  min_time
--   max_exec_time   ->  max_time
--   total_exec_time ->  total_time
-- ============================================================
