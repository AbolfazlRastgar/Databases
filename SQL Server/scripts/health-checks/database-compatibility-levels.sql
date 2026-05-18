/*
Script Name:     database-compatibility-levels.sql
Purpose:         Shows compatibility level, recovery model, page verify option,
                 auto close, auto shrink, and other relevant database settings
                 for all online databases. Flags configurations that typically
                 warrant review.
SQL Server Version: 2008 and later
Required Permissions: VIEW ANY DATABASE
Safety Level:    Read-only
How to Use:      Run as-is. Review the flags for AUTO_CLOSE, AUTO_SHRINK,
                 and compatibility level. Focus on databases whose compatibility
                 level is significantly behind the current SQL Server version —
                 these miss optimizer improvements and may have different
                 behavior for certain query constructs.
Notes:           AUTO_CLOSE causes the database to detach and reattach on each
                 connection, which is expensive. It should be OFF on all
                 production databases.
                 AUTO_SHRINK causes regular shrink operations that cause
                 fragmentation and contention. It should be OFF on all
                 production databases.
                 PAGE_VERIFY CHECKSUM is the recommended setting. TORN_PAGE_DETECTION
                 is an older, less reliable option. NONE provides no protection.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    d.name                                          AS database_name,
    d.compatibility_level,
    -- Show the SQL Server version this compat level corresponds to
    CASE d.compatibility_level
        WHEN 160 THEN 'SQL Server 2022'
        WHEN 150 THEN 'SQL Server 2019'
        WHEN 140 THEN 'SQL Server 2017'
        WHEN 130 THEN 'SQL Server 2016'
        WHEN 120 THEN 'SQL Server 2014'
        WHEN 110 THEN 'SQL Server 2012'
        WHEN 100 THEN 'SQL Server 2008/2008R2'
        WHEN 90  THEN 'SQL Server 2005'
        ELSE 'Unknown (' + CAST(d.compatibility_level AS VARCHAR(5)) + ')'
    END                                             AS compat_level_version,
    d.recovery_model_desc,
    d.page_verify_option_desc,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    d.is_auto_update_stats_on,
    d.is_auto_update_stats_async_on,
    d.is_read_committed_snapshot_on,
    d.snapshot_isolation_state_desc,
    d.state_desc,
    d.create_date,
    -- Flag notable configurations
    CASE
        WHEN d.is_auto_close_on = 1
            THEN 'AUTO_CLOSE ON; '
        ELSE ''
    END
    + CASE
        WHEN d.is_auto_shrink_on = 1
            THEN 'AUTO_SHRINK ON; '
        ELSE ''
    END
    + CASE
        WHEN d.page_verify_option_desc <> 'CHECKSUM'
            THEN 'PAGE_VERIFY not CHECKSUM; '
        ELSE ''
    END
    + CASE
        WHEN d.recovery_model_desc = 'SIMPLE'
         AND d.name NOT IN ('master', 'tempdb', 'msdb', 'model')
            THEN 'SIMPLE recovery (log backups not possible); '
        ELSE ''
    END                                             AS configuration_flags
FROM sys.databases AS d
WHERE d.state_desc = 'ONLINE'
ORDER BY
    configuration_flags DESC,
    d.name;
