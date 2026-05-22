-- ============================================================
-- Script   : 07_reset_statistics.sql
-- Purpose  : Reset pg_stat_statements accumulated statistics
-- Read-only : NO — destructive, cannot be undone
-- ============================================================
-- WARNING:
--   pg_stat_statements_reset() deletes all accumulated query
--   statistics permanently. Once run, historical data is gone
--   and the system needs time to collect a new baseline.
--
--   Do not run this during an active investigation.
--   Do not run this as a routine "cleanup" task.
--
-- When a reset is appropriate:
--   - After a major deployment to start a clean baseline
--   - After resolving a performance issue, to confirm the fix
--   - In staging/test environments before a controlled load test
--
-- Required privilege:
--   Superuser only. pg_monitor role can READ pg_stat_statements
--   but cannot reset it. pg_stat_statements_reset() requires
--   superuser regardless of PostgreSQL version.
-- ============================================================


-- ── Before resetting: check what you are about to lose ───────

SELECT
    count(*)                                   AS total_tracked_statements,
    round(sum(total_exec_time)::numeric / 1000, 2) AS total_exec_seconds,
    sum(calls)                                 AS total_calls
FROM pg_stat_statements;


-- ── Option 1: Reset ALL statistics (all users, all databases) ─
-- Uncomment only when intentional:

-- SELECT pg_stat_statements_reset();


-- ── Option 2: Reset for a specific database only ─────────────
-- Available in PostgreSQL 12+
-- Uncomment only when intentional:

-- SELECT pg_stat_statements_reset(
--     0,                                        -- 0 = all users
--     (SELECT oid FROM pg_database
--      WHERE datname = 'your_database_name'),   -- target database
--     0                                         -- 0 = all queries
-- );


-- ── Option 3: Reset a single query by queryid ────────────────
-- Get the queryid from pg_stat_statements first.
-- Available in PostgreSQL 12+
-- Uncomment only when intentional:

-- SELECT pg_stat_statements_reset(
--     0,                  -- 0 = all users
--     0,                  -- 0 = all databases
--     <queryid>           -- replace with the actual bigint queryid
-- );
