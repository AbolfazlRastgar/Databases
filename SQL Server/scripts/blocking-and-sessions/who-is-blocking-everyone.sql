/*
Script Name:     who-is-blocking-everyone.sql
Purpose:         Identifies which sessions are blocking others and how many
                 sessions each is blocking. Focuses on the main blockers
                 rather than mapping the full chain.
SQL Server Version: 2008 R2 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is. The blocked_session_count column shows how many
                 sessions are directly or indirectly waiting on each blocker.
                 A high count indicates a significant incident. Check the
                 sql_text and open_transaction_count of the head blocker first.
Notes:           This script is intentionally simpler than find-blocking-chain.sql.
                 Use it for a quick answer to "who is the problem?".
                 For a full chain map, use find-blocking-chain.sql.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    r.blocking_session_id                      AS blocker_session_id,
    s.login_name                               AS blocker_login,
    s.host_name                                AS blocker_host,
    s.program_name                             AS blocker_program,
    s.status                                   AS blocker_status,
    s.open_transaction_count,
    s.last_request_start_time,
    s.last_request_end_time,
    COUNT(*)                                   AS blocked_session_count,
    -- SQL text of the head blocker's most recent batch
    SUBSTRING(bt.text, 1, 1000)               AS blocker_sql_text
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
    ON r.blocking_session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle) AS bt
WHERE r.blocking_session_id > 0
GROUP BY
    r.blocking_session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    s.open_transaction_count,
    s.last_request_start_time,
    s.last_request_end_time,
    bt.text
ORDER BY
    blocked_session_count DESC;
