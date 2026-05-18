/*
Script Name:     01-basic-usage.sql
Purpose:         Common sp_WhoIsActive invocations for everyday monitoring.
                 Demonstrates frequently used parameter combinations.
SQL Server Version: sp_WhoIsActive supports SQL Server 2005 and later
Required Permissions: VIEW SERVER STATE (typically)
Safety Level:    Read-only
How to Use:      Run the section relevant to your current task.
                 sp_WhoIsActive must be installed before running these examples.
                 Download from: http://whoisactive.com
Notes:           Parameters not shown here default to their documented values.
                 See the full parameter reference at:
                 http://whoisactive.com/docs/
Author:          Abolfazl Rastgar
*/

-- ============================================================
-- 1. Basic execution — shows all active user requests
-- ============================================================
EXEC sp_WhoIsActive;


-- ============================================================
-- 2. Include the SQL text of each active request
-- ============================================================
EXEC sp_WhoIsActive
    @get_full_inner_text = 1;


-- ============================================================
-- 3. Include the estimated query plan
--    Note: retrieving plans adds overhead; use selectively
-- ============================================================
EXEC sp_WhoIsActive
    @get_plans = 1;


-- ============================================================
-- 4. Show all sessions including idle ones
-- ============================================================
EXEC sp_WhoIsActive
    @show_sleeping_spids = 2;    -- 0 = active only, 1 = sleeping with open txn, 2 = all


-- ============================================================
-- 5. Show only sessions involved in blocking
-- ============================================================
EXEC sp_WhoIsActive
    @filter_type = 'session',
    @not_filter_type = 'login';
-- Alternatively, show only blocked sessions:
-- EXEC sp_WhoIsActive @show_sleeping_spids = 1, @show_own_spid = 0;


-- ============================================================
-- 6. Filter to a specific database
-- ============================================================
EXEC sp_WhoIsActive
    @filter       = 'YourDatabaseName',
    @filter_type  = 'database';


-- ============================================================
-- 7. Include additional columns: tempdb usage, delta stats,
--    memory usage
-- ============================================================
EXEC sp_WhoIsActive
    @get_additional_info  = 1,
    @delta_interval       = 5;   -- Capture two snapshots 5 seconds apart
                                  -- and show the delta (reads/writes/CPU since last snapshot)


-- ============================================================
-- 8. Sort by elapsed time descending
-- ============================================================
EXEC sp_WhoIsActive
    @sort_order = '[elapsed_time] DESC';
