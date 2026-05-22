-- ============================================================
-- Script   : 04_top_frequently_executed_queries.sql
-- Purpose  : Most frequently called queries
-- Read-only : Yes
-- ============================================================
-- Use this when: you want to understand call volume patterns,
-- or when total execution time looks normal but the database
-- still feels under load.
--
-- A query taking 2ms called 3,000,000 times contributes
-- 6,000 seconds of cumulative CPU and I/O. It may not show
-- up as "slow" but it is driving real workload.
--
-- Also useful for spotting N+1 patterns:
-- very high calls + avg_rows_per_call close to 1 often means
-- the application is querying row-by-row inside a loop.
--
-- Column note (PostgreSQL version differences):
--   PG 13+  : total_exec_time, mean_exec_time, max_exec_time
--   PG 12   : total_time, mean_time, max_time
-- ============================================================

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
