-- ============================================================
-- Script   : 01_enable_pg_stat_statements.sql
-- Purpose  : Enable the pg_stat_statements extension
-- ============================================================
-- Requirements:
--   - pg_stat_statements must be added to shared_preload_libraries
--     in postgresql.conf BEFORE running this script
--   - PostgreSQL restart is required after modifying
--     shared_preload_libraries
--   - Superuser or CREATE privilege on the target database
-- ============================================================
-- postgresql.conf setting (requires restart):
--   shared_preload_libraries = 'pg_stat_statements'
--
-- Optional tuning parameters (no restart required):
--   pg_stat_statements.max = 10000   -- max tracked statements
--   pg_stat_statements.track = all   -- all | top | none
-- ============================================================

-- Create the extension if it does not already exist
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify: check the extension is active and view a sample row
SELECT
    version,
    name,
    default_version,
    installed_version,
    comment
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';

-- Quick sanity check: should return rows if data is being collected
SELECT count(*) AS tracked_statements
FROM pg_stat_statements;
