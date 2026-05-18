/*
Script Name:     session-resource-usage.sql
Purpose:         Shows resource consumption per active session: CPU, reads, writes,
                 memory, open transaction count, login name, host, and program.
                 Useful for identifying which sessions are consuming the most
                 resources at a point in time.
SQL Server Version: 2012 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is. Sort by cpu_time, logical_reads, or memory_usage_mb
                 depending on what you are investigating.
                 Change @IncludeIdle to 1 to also show sessions with no active
                 request (connected but idle).
Notes:           memory_usage is reported in 8KB pages; converted to MB below.
                 Sessions with open_transaction_count > 0 but no active request
                 are sleeping with uncommitted transactions — these can cause
                 blocking and log growth.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @IncludeIdle BIT = 0;   -- 0 = active sessions only, 1 = all user sessions

SELECT
    s.session_id,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(s.database_id)                 AS database_name,
    s.login_time,
    s.last_request_start_time,
    s.last_request_end_time,
    s.cpu_time,
    s.logical_reads,
    s.reads,
    s.writes,
    s.memory_usage * 8 / 1024.0           AS memory_usage_mb,
    s.open_transaction_count,
    s.row_count,
    s.total_scheduled_time,
    s.total_elapsed_time,
    -- Active request info if session currently has one
    r.status                               AS request_status,
    r.wait_type,
    r.wait_time                            AS wait_time_ms,
    r.blocking_session_id
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r
    ON s.session_id = r.session_id
WHERE s.is_user_process = 1
  AND (
      @IncludeIdle = 1
      OR r.session_id IS NOT NULL
      OR s.open_transaction_count > 0
  )
ORDER BY
    s.cpu_time DESC;
