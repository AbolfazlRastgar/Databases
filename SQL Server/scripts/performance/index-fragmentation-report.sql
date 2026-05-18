/*
Script Name:     index-fragmentation-report.sql
Purpose:         Reports index fragmentation for the current database using
                 sys.dm_db_index_physical_stats. Filters by a minimum page count
                 to avoid reporting fragmentation on tiny indexes where it has
                 no practical effect.
SQL Server Version: 2005 and later
Required Permissions: VIEW DATABASE STATE (in the target database)
Safety Level:    Read-only — does not rebuild or reorganize any indexes
How to Use:      Connect to the target database before running.
                 Adjust @MinPageCount and @MinFragmentationPct to match your
                 environment. The defaults are conservative.
                 Review the output and decide on REBUILD vs REORGANIZE manually.
Notes:           General guidance (not absolute rules):
                   avg_fragmentation_in_percent < 5%  → No action needed
                   5% - 30%                           → Consider REORGANIZE
                   > 30%                              → Consider REBUILD
                 For indexes with fewer than ~1000 pages, fragmentation rarely
                 affects query performance significantly.
                 sys.dm_db_index_physical_stats with DETAILED mode is thorough
                 but can be slow on large databases. SAMPLED mode is used here
                 as a practical balance.
                 Do not run REBUILD/REORGANIZE operations based on this output
                 without a maintenance window and testing on a representative
                 environment first.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @MinPageCount        INT   = 500;    -- Ignore indexes smaller than this
DECLARE @MinFragmentationPct FLOAT = 5.0;    -- Only show indexes above this % fragmentation

SELECT
    DB_NAME()                                      AS database_name,
    OBJECT_SCHEMA_NAME(ips.object_id)             AS schema_name,
    OBJECT_NAME(ips.object_id)                    AS table_name,
    i.name                                        AS index_name,
    i.type_desc                                   AS index_type,
    ips.index_id,
    ips.avg_fragmentation_in_percent,
    ips.fragment_count,
    ips.page_count,
    ips.avg_page_space_used_in_percent,
    ips.record_count,
    -- Suggested action based on common guidance
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent >= 5  THEN 'REORGANIZE'
        ELSE 'NONE'
    END                                           AS suggested_action
FROM sys.dm_db_index_physical_stats(
    DB_ID(),    -- Current database
    NULL,       -- All tables
    NULL,       -- All indexes
    NULL,       -- All partitions
    'SAMPLED'   -- SAMPLED is faster than DETAILED; use DETAILED for precision
) AS ips
INNER JOIN sys.indexes AS i
    ON ips.object_id = i.object_id
    AND ips.index_id = i.index_id
WHERE ips.page_count >= @MinPageCount
  AND ips.avg_fragmentation_in_percent >= @MinFragmentationPct
  AND ips.index_id > 0   -- Exclude heaps (index_id = 0)
ORDER BY
    ips.avg_fragmentation_in_percent DESC;
