/*
Script Name:     wait-stats-snapshot.sql
Purpose:         Returns a snapshot of server-level wait statistics from
                 sys.dm_os_wait_stats, filtered to exclude common benign
                 background waits. Shows wait count, total wait time,
                 average wait time, and percentage of total waits.
SQL Server Version: 2005 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is for a cumulative snapshot since the last SQL Server
                 restart or the last DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR).
                 For a meaningful delta, capture the output to a table, wait
                 several minutes, capture again, and subtract.
Notes:           Wait statistics are CUMULATIVE from server startup.
                 A single wait type dominating the output does not always
                 indicate a problem — context matters. For example:
                   CXPACKET alone is not a problem in SQL 2019+ (MAXDOP tuning)
                   LCK_M_* waits indicate locking/blocking
                   PAGEIOLATCH_* waits indicate disk I/O pressure
                   SOS_SCHEDULER_YIELD can indicate CPU pressure
                 The exclusion list below is based on Paul Randal's well-known
                 benign waits list. Adjust it to match your environment.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

WITH WaitStats AS (
    SELECT
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms,
        wait_time_ms - signal_wait_time_ms  AS resource_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        -- Common benign background waits
        'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SLEEP_DBSTARTUP',
        'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
        'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_TEMPDBSTARTUP',
        'SLEEP_WAITS', 'SLEEP_WORKQUEUESCAN', 'SLEEP_MEMORYPOOL_ALLOCATEPAGES',
        'WAITFOR',
        'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'BROKER_EVENTHANDLER',
        'DISPATCHER_QUEUE_SEMAPHORE',
        'CHECKPOINT_QUEUE',
        'REQUEST_FOR_DEADLOCK_SEARCH',
        'RESOURCE_QUEUE',
        'SERVER_IDLE_CHECK',
        'SQL_TRACE_BUFFER_FLUSH',
        'SQLTRACE_BUFFER_FLUSH',
        'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        'HADR_WORK_QUEUE',
        'HADR_TIMER_TASK',
        'HADR_CLUSAPI_CALL',
        'DBMIRROR_EVENTS_QUEUE',
        'DBMIRROR_WORKER_QUEUE',
        'FT_IFTS_SCHEDULER_IDLE_WAIT',
        'XE_DISPATCHER_WAIT',
        'XE_TIMER_EVENT',
        'CLR_AUTO_EVENT',
        'CLR_MANUAL_EVENT',
        'SNI_HTTP_ACCEPT',
        'ONDEMAND_TASK_QUEUE',
        'BAD_PAGE_PROCESS',
        'DIRTY_PAGE_POLL',
        'PREEMPTIVE_OS_AUTHENTICATIONOPS',
        'PREEMPTIVE_OS_GENERICOPS',
        'PREEMPTIVE_OS_WAITFORSINGLEOBJECT',
        'PREEMPTIVE_OS_WRITEFILEGATHER'
    )
    AND waiting_tasks_count > 0
),
TotalWaits AS (
    SELECT SUM(CAST(wait_time_ms AS BIGINT)) AS total_wait_time_ms
    FROM WaitStats
)
SELECT
    ws.wait_type,
    ws.waiting_tasks_count,
    ws.wait_time_ms,
    ws.resource_wait_time_ms,
    ws.signal_wait_time_ms,
    ws.max_wait_time_ms,
    CASE
        WHEN ws.waiting_tasks_count = 0 THEN 0
        ELSE CAST(ws.wait_time_ms AS DECIMAL(18,2)) / ws.waiting_tasks_count
    END                                                        AS avg_wait_ms_per_task,
    CAST(
        100.0 * ws.wait_time_ms / NULLIF(tw.total_wait_time_ms, 0)
    AS DECIMAL(5,2))                                           AS pct_of_total_waits
FROM WaitStats AS ws
CROSS JOIN TotalWaits AS tw
ORDER BY
    ws.wait_time_ms DESC;
