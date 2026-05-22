-- ============================================================
-- Script   : 01_enable_pg_stat_statements.sql
-- Purpose  : Enable pg_stat_statements and verify it is active
-- ============================================================
-- Before running this script:
--   1. Add to postgresql.conf (requires service restart):
--        shared_preload_libraries = 'pg_stat_statements'
--
--   2. Optional — set in postgresql.conf or via ALTER SYSTEM:
--        pg_stat_statements.max   = 10000  -- tracked statement limit
--        pg_stat_statements.track = all    -- top | all | none
--
--   3. Restart PostgreSQL, then run this script.
--
-- Required privilege: superuser or CREATE on the target database
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify extension is installed
SELECT
    name,
    installed_version,
    default_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';

-- Verify data is being collected
SELECT count(*) AS tracked_statements
FROM pg_stat_statements;
