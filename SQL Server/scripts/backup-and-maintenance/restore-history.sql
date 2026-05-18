/*
Script Name:     restore-history.sql
Purpose:         Shows recent restore operations recorded in msdb.
                 Useful for auditing what was restored, when, and by whom.
SQL Server Version: 2008 and later
Required Permissions: SELECT on msdb.dbo.restorehistory, msdb.dbo.backupset,
                      msdb.dbo.restorefile
Safety Level:    Read-only
How to Use:      Adjust @DaysBack to change the history window.
                 The destination_database column shows the database that was
                 restored (which may differ from the original backup source).
Notes:           msdb restore history may be incomplete if history cleanup
                 jobs have run. sp_delete_backuphistory removes both backup
                 and restore history.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @DaysBack INT = 30;

SELECT
    rh.destination_database_name,
    rh.restore_date,
    rh.user_name,
    CASE rh.restore_type
        WHEN 'D' THEN 'Database'
        WHEN 'F' THEN 'File'
        WHEN 'G' THEN 'Filegroup'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        WHEN 'V' THEN 'Verifyonly'
        WHEN 'R' THEN 'Revert'
        ELSE rh.restore_type
    END                                     AS restore_type,
    rh.replace,
    rh.recovery,
    rh.restart,
    -- Source backup info
    bs.database_name                        AS source_database,
    bs.backup_start_date                    AS source_backup_date,
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type
    END                                     AS source_backup_type,
    bs.server_name                          AS source_server
FROM msdb.dbo.restorehistory AS rh
LEFT JOIN msdb.dbo.backupset AS bs
    ON rh.backup_set_id = bs.backup_set_id
WHERE rh.restore_date >= DATEADD(DAY, -@DaysBack, GETDATE())
ORDER BY
    rh.restore_date DESC;
