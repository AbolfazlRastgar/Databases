/*
Script Name:     find-blocking-chain.sql
Purpose:         Shows blocking chains on the instance. Identifies the head blocker
                 (a session that is blocking others but is not itself blocked),
                 and maps every blocked session back to its root blocker.
SQL Server Version: 2008 R2 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is during a blocking incident. The head_blocker column
                 identifies the root cause. Investigate that session first.
                 Look at the sql_text column to understand what the head blocker
                 is running (or waiting on if it is a sleeping session with an
                 open transaction).
Notes:           A session can be a head blocker even if it is not actively
                 running a query — it may be sleeping with an open transaction.
                 In that case, check sleeping-sessions-with-open-transactions.sql.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

WITH BlockingChain AS (
    -- Start with all blocked sessions
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time                        AS wait_time_ms,
        r.total_elapsed_time / 1000       AS elapsed_seconds,
        DB_NAME(r.database_id)            AS database_name,
        s.login_name,
        s.host_name,
        s.program_name,
        s.status                          AS session_status,
        t.text                            AS sql_text,
        -- Head blocker: blocking others but not itself blocked
        CASE
            WHEN r.blocking_session_id = 0
              OR r.blocking_session_id IS NULL THEN 1
            ELSE 0
        END                               AS is_head_blocker,
        r.blocking_session_id             AS root_blocker
    FROM sys.dm_exec_requests AS r
    INNER JOIN sys.dm_exec_sessions AS s
        ON r.session_id = s.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
    WHERE s.is_user_process = 1
)
SELECT
    bc.session_id,
    bc.blocking_session_id,
    bc.is_head_blocker,
    bc.wait_type,
    bc.wait_time_ms,
    bc.elapsed_seconds,
    bc.session_status,
    bc.database_name,
    bc.login_name,
    bc.host_name,
    bc.program_name,
    SUBSTRING(bc.sql_text, 1, 1000)       AS sql_text
FROM BlockingChain AS bc
-- Only show rows that are part of an active blocking chain
WHERE bc.blocking_session_id > 0
   OR bc.session_id IN (
       SELECT blocking_session_id
       FROM BlockingChain
       WHERE blocking_session_id > 0
   )
ORDER BY
    bc.is_head_blocker DESC,
    bc.blocking_session_id,
    bc.session_id;
