/*
Script Name:     tempdb-usage-by-session.sql
Purpose:         Shows which sessions are currently allocating space in TempDB,
                 broken down by user object allocations (temp tables, table
                 variables) and internal object allocations (sort spills, hash
                 join spills, etc.).
SQL Server Version: 2005 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is. Sort by user_objects_mb or internal_objects_mb
                 to find the biggest TempDB consumers.
                 If a session is allocating large amounts of internal objects,
                 it may be spilling to disk due to an underestimated sort or
                 hash operation — this often indicates a query plan issue
                 or insufficient memory grant.
Notes:           Allocations and deallocations are tracked in pages (8KB each).
                 A session with net_user_objects_mb > 0 has temp objects
                 that have not yet been dropped.
                 A session with net_internal_objects_mb > 0 has active work
                 space allocated for query operations.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    ssu.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(s.database_id)                                              AS database_name,
    ssu.user_objects_alloc_page_count * 8 / 1024.0                    AS user_objects_alloc_mb,
    ssu.user_objects_dealloc_page_count * 8 / 1024.0                  AS user_objects_dealloc_mb,
    (ssu.user_objects_alloc_page_count - ssu.user_objects_dealloc_page_count) * 8 / 1024.0
                                                                        AS net_user_objects_mb,
    ssu.internal_objects_alloc_page_count * 8 / 1024.0                AS internal_objects_alloc_mb,
    ssu.internal_objects_dealloc_page_count * 8 / 1024.0              AS internal_objects_dealloc_mb,
    (ssu.internal_objects_alloc_page_count - ssu.internal_objects_dealloc_page_count) * 8 / 1024.0
                                                                        AS net_internal_objects_mb,
    -- Active request info if there is one
    r.status                                                            AS request_status,
    r.wait_type,
    r.total_elapsed_time / 1000                                        AS elapsed_seconds,
    SUBSTRING(t.text, 1, 500)                                          AS sql_text
FROM sys.dm_db_session_space_usage AS ssu
INNER JOIN sys.dm_exec_sessions AS s
    ON ssu.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests AS r
    ON ssu.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND (
      ssu.user_objects_alloc_page_count > 0
      OR ssu.internal_objects_alloc_page_count > 0
  )
ORDER BY
    (ssu.user_objects_alloc_page_count + ssu.internal_objects_alloc_page_count) DESC;
