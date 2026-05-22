-- ============================================================
-- Script   : 07_reset_statistics.sql
-- Purpose  : Reset pg_stat_statements statistics
-- Read-only : NO — this action is destructive
-- ============================================================
-- WARNING:
--   pg_stat_statements_reset() permanently removes all
--   accumulated query statistics. This cannot be undone.
--
--   Do not run this blindly in production.
--   Once reset, historical aggregated data is gone and the
--   system needs time to accumulate new statistics before
--   queries are meaningful again.
--
-- When a reset may be appropriate:
--   - After a major schema or application deployment, to start
--     collecting a clean baseline for the new workload
--   - After completing a performance investigation, to start
--     a fresh measurement window
--   - In a test or staging environment before a load test
--
-- Required privilege:
--   Superuser, or pg_monitor role (PostgreSQL 14+)
-- ============================================================


-- ── Option 1: Reset ALL statistics for all users/databases ──
-- Uncomment only when intentional:

-- SELECT pg_stat_statements_reset();


-- ── Option 2: Reset statistics for a specific database only ──
-- Available in PostgreSQL 12+
-- Replace 'your_database_name' with the target database.
-- Uncomment only when intentional:

-- SELECT pg_stat_statements_reset(
--     0,                                       -- userid  (0 = all users)
--     (SELECT oid FROM pg_database
--      WHERE datname = 'your_database_name'),  -- dbid
--     0                                        -- queryid (0 = all queries)
-- );


-- ── Option 3: Reset statistics for a specific query ──────────
-- Requires knowing the queryid from pg_stat_statements.
-- Replace the queryid value accordingly.
-- Available in PostgreSQL 12+
-- Uncomment only when intentional:

-- SELECT pg_stat_statements_reset(0, 0, <queryid>);


-- ── Safe check: view current stats before deciding to reset ──
SELECT
    count(*)                                    AS total_tracked_queries,
    min(stats_since)                            AS stats_collected_since,
    max(stats_since)                            AS latest_entry
FROM pg_stat_statements
CROSS JOIN LATERAL (
    SELECT min(stats_since) AS stats_since
    FROM pg_stat_statements
    LIMIT 1
) s;

-- Note: stats_since column is available in PostgreSQL 14+.
-- On earlier versions, remove the stats_since references.
