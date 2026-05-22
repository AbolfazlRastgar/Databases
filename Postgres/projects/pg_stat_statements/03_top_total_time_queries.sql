-- ============================================================
-- Script   : 03_top_total_time_queries.sql
-- Purpose  : Find queries consuming the most total execution time
-- Read-only : Yes
-- ============================================================
-- What it answers:
--   Which queries are consuming the most cumulative database time
--   since statistics were last reset?
--
-- Why this matters more than mean time alone:
--   A query that runs in 5ms but is called 2,000,000 times
--   contributes far more total load than a query that takes
--   2 seconds but runs once a day. Total execution time shows
--   you where your database actually spends its time.
--
--   This is typically the most useful starting point for
--   performance tuning in production.
-- ============================================================

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
    round(pss.max_exec_time::numeric, 2)        AS max_exec_ms,
    pss.rows,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
ORDER BY pss.total_exec_time DESC
LIMIT 20;

-- ============================================================
-- pct_of_total_time: shows what percentage of all tracked
-- execution time this single query accounts for. A query at
-- 40%+ of total time is almost always worth investigating first.
--
-- For PostgreSQL 12 and earlier, replace:
--   total_exec_time ->  total_time
--   mean_exec_time  ->  mean_time
--   max_exec_time   ->  max_time
-- ============================================================
