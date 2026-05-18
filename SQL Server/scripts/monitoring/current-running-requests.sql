/*
Script Name:     current-running-requests.sql
Purpose:         Shows all currently executing requests on the SQL Server instance.
                 Includes session ID, status, wait type, blocking session, CPU time,
                 logical reads, writes, elapsed time, database, login, host, program,
                 and the SQL text of the executing batch.
SQL Server Version: 2012 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is on any instance. Filter by status or wait_type as needed.
                 The @MinElapsedSeconds parameter can be adjusted to focus on
                 requests that have been running for a specific minimum duration.
Notes:           sys.dm_exec_sql_text may return NULL for some system sessions.
                 CROSS APPLY is used to retrieve SQL text and query plan handle
                 without breaking the result set when text is unavailable.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @MinElapsedSeconds INT = 0;  -- Set > 0 to filter short-lived requests

SELECT
    r.session_id,
    r.status,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time                              AS wait_time_ms,
    r.total_elapsed_time / 1000             AS elapsed_seconds,
    r.cpu_time,
    r.logical_reads,
    r.writes,
    r.reads,
    r.row_count,
    DB_NAME(r.database_id)                  AS database_name,
    s.login_name,
    s.host_name,
    s.program_name,
    r.command,
    t.text                                  AS sql_text,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        (
            CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(t.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset
        ) / 2 + 1
    )                                       AS current_statement,
    r.plan_handle
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
    ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND r.total_elapsed_time / 1000 >= @MinElapsedSeconds
ORDER BY
    r.total_elapsed_time DESC;
