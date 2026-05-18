/*
Script Name:     top-io-queries-from-plan-cache.sql
Purpose:         Returns the top logical-read and physical-read queries from
                 the SQL Server plan cache. Helps identify queries driving
                 buffer pool pressure and storage I/O.
SQL Server Version: 2005 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is. The result is sorted by total_logical_reads by default.
                 Change ORDER BY to total_physical_reads to focus on queries
                 that bypass the buffer pool and hit disk.
                 Adjust @TopN as needed.
Notes:           High logical reads usually point to missing or unused indexes,
                 or queries returning more rows than necessary.
                 High physical reads alongside low logical reads may indicate
                 the buffer pool is too small, or data is not being reused.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @TopN INT = 25;

SELECT TOP (@TopN)
    qs.total_logical_reads,
    qs.total_logical_reads / qs.execution_count        AS avg_logical_reads,
    qs.total_physical_reads,
    qs.total_physical_reads / qs.execution_count       AS avg_physical_reads,
    qs.total_logical_writes,
    qs.execution_count,
    qs.total_worker_time / qs.execution_count          AS avg_cpu_us,
    qs.total_elapsed_time / qs.execution_count         AS avg_elapsed_us,
    qs.last_execution_time,
    qs.creation_time                                   AS plan_cached_at,
    DB_NAME(qt.dbid)                                   AS database_name,
    OBJECT_NAME(qt.objectid, qt.dbid)                  AS object_name,
    SUBSTRING(qt.text, 1, 2000)                        AS sql_text,
    qs.plan_handle
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
ORDER BY
    qs.total_logical_reads DESC;
