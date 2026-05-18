/*
Script Name:     top-cpu-queries-from-plan-cache.sql
Purpose:         Returns the top CPU-consuming queries currently in the
                 SQL Server plan cache. Reports total CPU, average CPU per
                 execution, execution count, and SQL text.
SQL Server Version: 2005 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Adjust @TopN to control how many rows are returned.
                 Focus on total_worker_time for queries that run frequently,
                 and avg_worker_time for queries that are expensive per call.
Notes:           The plan cache is volatile. Plans may be evicted under memory
                 pressure or after schema changes. A query not appearing here
                 does not mean it is cheap — it may simply not be cached.
                 All times are in microseconds.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @TopN INT = 25;

SELECT TOP (@TopN)
    qs.total_worker_time                                AS total_cpu_us,
    qs.total_worker_time / qs.execution_count          AS avg_cpu_us,
    qs.execution_count,
    qs.total_elapsed_time / qs.execution_count         AS avg_elapsed_us,
    qs.total_logical_reads,
    qs.total_logical_reads / qs.execution_count        AS avg_logical_reads,
    qs.creation_time                                    AS plan_cached_at,
    qs.last_execution_time,
    DB_NAME(qt.dbid)                                   AS database_name,
    OBJECT_NAME(qt.objectid, qt.dbid)                  AS object_name,
    SUBSTRING(qt.text, 1, 2000)                        AS sql_text,
    qs.plan_handle
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
ORDER BY
    qs.total_worker_time DESC;
