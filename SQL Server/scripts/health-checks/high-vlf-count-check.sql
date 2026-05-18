/*
Script Name:     high-vlf-count-check.sql
Purpose:         Checks VLF (Virtual Log File) count per database.
                 Reports total VLF count and flags databases with a high number.
                 Uses sys.dm_db_log_info (SQL Server 2016 SP2+) when available,
                 and falls back to DBCC LOGINFO for older versions.
SQL Server Version: 2008 and later
                 sys.dm_db_log_info: SQL Server 2016 SP2 / SQL Server 2017 CU1+
Required Permissions: VIEW SERVER STATE; VIEW ANY DATABASE
                      sysadmin for DBCC LOGINFO on older versions
Safety Level:    Read-only
How to Use:      Run as-is. Databases with VLF counts above 1000 are flagged.
                 High VLF counts are caused by frequent small autogrowths
                 of the transaction log. They slow down SQL Server startup,
                 database recovery, and log backup operations.
                 To reduce VLF count: grow the log file to its intended size
                 in one or two operations, then set autogrowth to a fixed size
                 that matches expected log usage.
Notes:           What counts as "high" depends on context:
                   < 200     Normal
                   200-1000  Worth monitoring
                   > 1000    Likely to cause noticeable overhead
                   > 10000   Should be addressed
                 VLF count alone does not cause downtime, but it compounds
                 other problems during recovery and high-log-activity periods.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

-- Detect SQL Server version to choose the right method
DECLARE @MajorVersion INT;
DECLARE @MinorVersion INT;
DECLARE @BuildNumber  INT;

SELECT
    @MajorVersion = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT),
    @BuildNumber  = CAST(SERVERPROPERTY('ProductBuild') AS INT);

-- sys.dm_db_log_info is available in SQL Server 2016 SP2+ (build >= 13.0.5026)
-- and SQL Server 2017 CU1+ (build >= 14.0.3006)
IF (
    (@MajorVersion = 13 AND @BuildNumber >= 5026)   -- 2016 SP2+
    OR @MajorVersion >= 14                           -- 2017+
)
BEGIN
    -- Modern approach: use sys.dm_db_log_info
    -- Collect VLF counts per database into a temp table
    IF OBJECT_ID('tempdb..#VLFCounts') IS NOT NULL
        DROP TABLE #VLFCounts;

    CREATE TABLE #VLFCounts
    (
        database_id   INT,
        database_name SYSNAME,
        vlf_count     INT
    );

    INSERT INTO #VLFCounts (database_id, database_name, vlf_count)
    SELECT
        d.database_id,
        d.name,
        COUNT(*) AS vlf_count
    FROM sys.databases AS d
    CROSS APPLY sys.dm_db_log_info(d.database_id)
    WHERE d.state_desc = 'ONLINE'
    GROUP BY
        d.database_id,
        d.name;

    SELECT
        vc.database_name,
        vc.vlf_count,
        CASE
            WHEN vc.vlf_count > 10000 THEN 'Critical — address soon'
            WHEN vc.vlf_count > 1000  THEN 'High — review log file growth settings'
            WHEN vc.vlf_count > 200   THEN 'Elevated — monitor'
            ELSE 'Normal'
        END                           AS status,
        f.size * 8 / 1024.0          AS log_file_size_mb,
        f.is_percent_growth,
        CASE
            WHEN f.growth = 0           THEN 'No autogrowth'
            WHEN f.is_percent_growth = 1 THEN CAST(f.growth AS VARCHAR(10)) + '%'
            ELSE CAST(f.growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
        END                           AS log_autogrowth_setting
    FROM #VLFCounts AS vc
    INNER JOIN sys.master_files AS f
        ON vc.database_id = f.database_id
        AND f.type_desc = 'LOG'
    ORDER BY
        vc.vlf_count DESC;

    DROP TABLE #VLFCounts;
END
ELSE
BEGIN
    -- Fallback for SQL Server 2014 / 2016 pre-SP2
    -- DBCC LOGINFO cannot be queried per-database in a set-based way here;
    -- run it manually per database:
    PRINT 'sys.dm_db_log_info is not available on this SQL Server version.';
    PRINT 'To check VLF count on this instance, run the following for each database:';
    PRINT '';

    SELECT 'DBCC LOGINFO([' + name + ']);' AS manual_check_command
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;
END
