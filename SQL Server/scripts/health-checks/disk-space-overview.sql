/*
Script Name:     disk-space-overview.sql
Purpose:         Shows disk volume capacity, free space, and the database files
                 located on each volume. Uses sys.dm_os_volume_stats to get
                 live disk space information for volumes that host SQL Server
                 database files.
SQL Server Version: 2008 R2 SP1 and later
Required Permissions: VIEW SERVER STATE; VIEW ANY DATABASE
Safety Level:    Read-only
How to Use:      Run as-is. The result shows one row per database file,
                 with volume-level capacity and free space alongside the
                 file details. Filter by volume_free_mb to find drives
                 under pressure.
Notes:           sys.dm_os_volume_stats returns one row per unique volume
                 per file. Files on the same volume will show the same
                 capacity and free space numbers.
                 The function only returns data for volumes that host at
                 least one SQL Server database file. It does not enumerate
                 all drives on the server.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    vs.volume_mount_point                               AS drive,
    vs.logical_volume_name                              AS volume_name,
    vs.file_system_type,
    vs.total_bytes / 1024.0 / 1024 / 1024             AS volume_total_gb,
    vs.available_bytes / 1024.0 / 1024 / 1024         AS volume_free_gb,
    CAST(
        100.0 * vs.available_bytes / NULLIF(vs.total_bytes, 0)
    AS DECIMAL(5,2))                                   AS pct_free,
    d.name                                             AS database_name,
    f.name                                             AS logical_file_name,
    CASE f.type_desc
        WHEN 'ROWS' THEN 'Data'
        WHEN 'LOG'  THEN 'Log'
        ELSE f.type_desc
    END                                                AS file_type,
    f.physical_name,
    f.size * 8 / 1024.0                               AS file_size_mb,
    -- Flag volumes with less than 15% or 10GB free
    CASE
        WHEN vs.available_bytes / 1024.0 / 1024 / 1024 < 10
          OR 100.0 * vs.available_bytes / NULLIF(vs.total_bytes, 0) < 15
        THEN 'Low disk space'
        ELSE ''
    END                                                AS review_flag
FROM sys.master_files AS f
INNER JOIN sys.databases AS d
    ON f.database_id = d.database_id
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) AS vs
WHERE d.state_desc = 'ONLINE'
ORDER BY
    vs.available_bytes ASC,   -- Most critical volumes first
    d.name,
    f.file_id;
