/*
Script Name:     sleeping-sessions-with-open-transactions.sql
Purpose:         Finds sessions that are currently sleeping (no active request)
                 but still hold one or more open transactions. These sessions
                 are a common cause of blocking, log file growth, and version
                 store accumulation in tempdb.
SQL Server Version: 2008 R2 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is. Review the open_transaction_count and
                 last_request_end_time columns. Sessions that have been idle
                 for a long time with open transactions are usually the result
                 of application bugs, connection pooling issues, or long-running
                 ETL processes that forgot to commit.
                 To terminate a session, use kill-command-generator.sql to
                 produce the KILL statement and review it before executing.
Notes:           A sleeping session with an open transaction is holding at least
                 one lock. It will block any other session trying to acquire a
                 conflicting lock on the same resources.
                 most_recent_sql_handle may return the last completed statement,
                 which can help identify what the session was doing before it
                 became idle.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    s.session_id,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(s.database_id)                         AS database_name,
    s.open_transaction_count,
    s.login_time,
    s.last_request_start_time,
    s.last_request_end_time,
    DATEDIFF(SECOND, s.last_request_end_time, GETDATE()) AS idle_seconds,
    s.cpu_time,
    s.logical_reads,
    s.writes,
    -- Most recent SQL executed in this session
    SUBSTRING(t.text, 1, 1000)                     AS last_sql_text
FROM sys.dm_exec_sessions AS s
OUTER APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle) AS t
WHERE s.is_user_process = 1
  AND s.status = 'sleeping'
  AND s.open_transaction_count > 0
ORDER BY
    idle_seconds DESC;
