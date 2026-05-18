/*
Script Name:     long-running-queries.sql
Purpose:         Finds active requests that have been running longer than a
                 configurable threshold. Returns elapsed time, wait info,
                 SQL text, and query plan handle.
SQL Server Version: 2012 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Adjust @ThresholdSeconds to match your environment.
                 The default is 30 seconds. In a busy OLTP system you may
                 want 60-120 seconds. For batch/ETL environments, raise it higher.
Notes:           This script targets user sessions only. System sessions
                 (is_user_process = 0) are excluded.
                 Long elapsed time alone does not indicate a problem — check
                 wait_type and blocking_session_id as well.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @ThresholdSeconds INT = 30;

SELECT
    r.session_id,
    r.status,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time                             AS wait_time_ms,
    r.total_elapsed_time / 1000            AS elapsed_seconds,
    r.cpu_time,
    r.logical_reads,
    r.writes,
    r.granted_query_memory * 8 / 1024      AS granted_memory_mb,
    DB_NAME(r.database_id)                 AS database_name,
    s.login_name,
    s.host_name,
    s.program_name,
    t.text                                 AS sql_text,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        (
            CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(t.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset
        ) / 2 + 1
    )                                      AS current_statement,
    r.plan_handle
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
    ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND r.total_elapsed_time / 1000 >= @ThresholdSeconds
ORDER BY
    r.total_elapsed_time DESC;
