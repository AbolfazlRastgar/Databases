-- ============================================================
-- Script   : 02_top_slow_queries.sql
-- Purpose  : Queries with the highest mean execution time
-- Read-only : Yes
-- ============================================================
-- Use this when: users report slow individual responses or
-- timeouts and you want to find which queries are slowest
-- per execution.
--
-- Cross-reference with 03_top_total_time_queries.sql.
-- A query slow on average but called rarely may matter less
-- than a moderately slow query called thousands of times.
--
-- Column note (PostgreSQL version differences):
--   PG 13+  : mean_exec_time, total_exec_time, min_exec_time, max_exec_time
--   PG 12   : mean_time, total_time, min_time, max_time
-- ============================================================

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
