-- ============================================================
-- Script   : 03_top_total_time_queries.sql
-- Purpose  : Queries consuming the most cumulative execution time
-- Read-only : Yes
-- ============================================================
-- Use this first during most performance investigations.
-- Total execution time shows where the database actually spends
-- its time — not just which queries are slow in isolation.
--
-- A query at 35%+ of total tracked time is almost always
-- worth looking at before anything else.
--
-- pct_of_total_time is calculated over all tracked statements,
-- not just the top 20 shown here.
--
-- Column note (PostgreSQL version differences):
--   PG 13+  : total_exec_time, mean_exec_time, max_exec_time
--   PG 12   : total_time, mean_time, max_time
-- ============================================================

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
