/*
Script Name:     database-file-growth-settings.sql
Purpose:         Shows all database files (data and log) across all online
                 databases, including current size, autogrowth settings,
                 max size, and flags for percentage-based autogrowth.
SQL Server Version: 2008 and later
Required Permissions: VIEW ANY DATABASE; VIEW SERVER STATE
Safety Level:    Read-only
How to Use:      Run as-is. Review the review_flag column.
                 Percentage-based autogrowth is a common misconfiguration —
                 on large databases it causes unpredictable, oversized growths
                 that can fill a drive quickly.
                 Best practice is fixed-size autogrowth (e.g. 256MB or 512MB
                 for data files, 64MB-128MB for log files).
Notes:           is_percent_growth = 1 means autogrowth is percentage-based.
                 growth column: when is_percent_growth = 1, the value is a
                 percentage; when 0, it is in 8KB pages.
                 max_size = -1 means unlimited growth (bounded only by disk).
                 max_size = 0 means no autogrowth (fixed size).
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    d.name                                              AS database_name,
    f.name                                             AS logical_file_name,
    f.physical_name,
    CASE f.type_desc
        WHEN 'ROWS' THEN 'Data'
        WHEN 'LOG'  THEN 'Log'
        ELSE f.type_desc
    END                                                AS file_type,
    f.size * 8 / 1024.0                               AS current_size_mb,
    CASE
        WHEN f.max_size = -1 THEN -1
        WHEN f.max_size = 0  THEN 0
        ELSE f.max_size * 8 / 1024.0
    END                                                AS max_size_mb,
    f.is_percent_growth,
    CASE
        WHEN f.growth = 0          THEN 'No autogrowth'
        WHEN f.is_percent_growth = 1 THEN CAST(f.growth AS VARCHAR(10)) + '%'
        ELSE CAST(f.growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
    END                                                AS autogrowth_setting,
    -- Flag problematic configurations
    CASE
        WHEN f.is_percent_growth = 1 AND f.growth > 0
            THEN 'Percent growth — change to fixed MB'
        WHEN f.growth = 0
            THEN 'Autogrowth disabled — monitor size'
        WHEN f.max_size = -1
            THEN 'Unlimited max size — verify disk capacity'
        ELSE ''
    END                                                AS review_flag
FROM sys.databases AS d
INNER JOIN sys.master_files AS f
    ON d.database_id = f.database_id
WHERE d.state_desc = 'ONLINE'
ORDER BY
    review_flag DESC,
    d.name,
    f.type_desc,
    f.file_id;
