-- ============================================================
-- Script   : 04_top_frequently_executed_queries.sql
-- Purpose  : Find the most frequently executed queries
-- Read-only : Yes
-- ============================================================
-- What it answers:
--   Which queries are called most often?
--
-- Why this matters:
--   A query that takes 1ms but runs 5,000,000 times per day
--   generates 5,000 seconds of cumulative load. High-frequency
--   queries are candidates for:
--     - Result caching at the application layer
--     - Connection pooling review
--     - Query batching or consolidation
--     - Index review to reduce per-call cost
--
--   High call counts can also indicate application-level
--   patterns worth reviewing — for example, N+1 query problems.
-- ============================================================

SELECT
    pss.userid::regrole                         AS db_user,
    pss.dbid::regdatabase                       AS database_name,
    pss.calls,
    round(pss.total_exec_time::numeric, 2)      AS total_exec_ms,
    round(pss.mean_exec_time::numeric, 2)       AS mean_exec_ms,
    round(pss.max_exec_time::numeric, 2)        AS max_exec_ms,
    pss.rows,
    round(pss.rows::numeric / nullif(pss.calls, 0), 2) AS avg_rows_per_call,
    left(pss.query, 200)                        AS query_text
FROM pg_stat_statements pss
ORDER BY pss.calls DESC
LIMIT 20;

-- ============================================================
-- avg_rows_per_call: if this is very low (e.g. 0 or 1) and
-- calls are in the millions, the application may be fetching
-- individual rows in a loop instead of batching.
--
-- For PostgreSQL 12 and earlier, replace:
--   total_exec_time ->  total_time
--   mean_exec_time  ->  mean_time
--   max_exec_time   ->  max_time
-- ============================================================
