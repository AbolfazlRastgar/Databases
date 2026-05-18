/*
Script Name:     02-find-blocking-chain.sql
Purpose:         Uses sp_WhoIsActive to surface blocking chains and identify
                 head blockers. sp_WhoIsActive's blocking chain output is
                 more readable than raw DMV queries for complex chains.
SQL Server Version: sp_WhoIsActive supports SQL Server 2005 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run section by section depending on what you need.
                 sp_WhoIsActive must be installed before running these examples.
                 Download from: http://whoisactive.com
Notes:           The @show_sleeping_spids = 1 parameter is important here.
                 Head blockers are often sleeping sessions holding open
                 transactions, not actively running requests. Without this
                 parameter they would not appear in the output.
Author:          Abolfazl Rastgar
*/

-- ============================================================
-- 1. Show active requests and sleeping sessions with open
--    transactions (captures head blockers that are idle)
-- ============================================================
EXEC sp_WhoIsActive
    @show_sleeping_spids = 1,
    @get_full_inner_text = 1;


-- ============================================================
-- 2. Show only sessions that are blocked or blocking others
-- ============================================================
EXEC sp_WhoIsActive
    @show_sleeping_spids = 1,
    @only_show_blocking  = 1;   -- Only available in later versions; check yours


-- ============================================================
-- 3. Show blocking chain with SQL text and wait info
--    Sort by blocking_session_id to see the chain structure
-- ============================================================
EXEC sp_WhoIsActive
    @show_sleeping_spids = 1,
    @get_full_inner_text = 1,
    @sort_order          = '[blocked_session_count] DESC';


-- ============================================================
-- 4. After identifying the head blocker session_id from the
--    output above, run this to check its last executed SQL
--    (replace 99 with the actual session_id)
-- ============================================================
SELECT
    s.session_id,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    s.open_transaction_count,
    s.last_request_start_time,
    s.last_request_end_time,
    SUBSTRING(t.text, 1, 2000)  AS last_sql_text
FROM sys.dm_exec_sessions AS s
OUTER APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle) AS t
WHERE s.session_id = 99;  -- Replace with actual head blocker session_id
