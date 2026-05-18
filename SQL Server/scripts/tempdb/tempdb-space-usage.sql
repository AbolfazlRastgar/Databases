/*
Script Name:     tempdb-space-usage.sql
Purpose:         Shows TempDB file space usage across all TempDB data files.
                 Reports total allocated space, used space, free space,
                 user object allocations, internal object allocations,
                 and version store size.
SQL Server Version: 2005 and later
Required Permissions: VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is. Review the free_space_mb column to understand
                 how much headroom remains before TempDB fills the disk.
                 High version_store_mb may indicate long-running transactions
                 or SNAPSHOT isolation usage.
Notes:           sys.dm_db_file_space_usage reports per-file allocation in pages.
                 Page size is 8KB. Converted to MB below.
                 User objects: temp tables, table variables, cursors, etc.
                 Internal objects: sort runs, hash join spills, index build buffers, etc.
                 Version store: row versions for SNAPSHOT isolation or Read Committed
                 Snapshot Isolation (RCSI). High version store may indicate long-running
                 transactions that are not releasing their snapshot.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    f.file_id,
    f.physical_name,
    f.size * 8 / 1024.0                                AS file_size_mb,
    fsu.total_page_count * 8 / 1024.0                  AS total_allocated_mb,
    fsu.allocated_extent_page_count * 8 / 1024.0       AS used_mb,
    (fsu.total_page_count - fsu.allocated_extent_page_count) * 8 / 1024.0
                                                        AS free_mb,
    fsu.user_object_reserved_page_count * 8 / 1024.0   AS user_objects_mb,
    fsu.internal_object_reserved_page_count * 8 / 1024.0
                                                        AS internal_objects_mb,
    fsu.version_store_reserved_page_count * 8 / 1024.0 AS version_store_mb,
    fsu.unallocated_extent_page_count * 8 / 1024.0     AS unallocated_mb,
    CAST(
        100.0 * fsu.allocated_extent_page_count / NULLIF(fsu.total_page_count, 0)
    AS DECIMAL(5,2))                                   AS pct_used
FROM sys.dm_db_file_space_usage AS fsu
INNER JOIN tempdb.sys.database_files AS f
    ON fsu.file_id = f.file_id
ORDER BY
    f.file_id;
