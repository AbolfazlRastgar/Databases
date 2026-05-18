/*
Script Name:     backup-status-last-7-days.sql
Purpose:         Shows backup history from the last 7 days per database.
                 Reports backup type (Full/Diff/Log), start and finish time,
                 duration, uncompressed size, compressed size, compression ratio,
                 and backup file path.
SQL Server Version: 2008 and later (compressed_backup_size column)
Required Permissions: SELECT on msdb.dbo.backupset, msdb.dbo.backupmediafamily
Safety Level:    Read-only
How to Use:      Adjust @DaysBack to change the history window.
                 The @BackupType parameter filters by type:
                   'D' = Full database backup
                   'I' = Differential backup
                   'L' = Log backup
                   NULL = All types
Notes:           Results from msdb depend on backup history retention settings.
                 If msdb history has been trimmed, older backups will not appear
                 even if they exist on disk.
                 The physical_device_name column shows the backup destination as
                 recorded in msdb — it does not verify the file exists on disk.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @DaysBack   INT  = 7;
DECLARE @BackupType CHAR(1) = NULL;  -- NULL = all types, 'D' = Full, 'I' = Diff, 'L' = Log

SELECT
    bs.database_name,
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type
    END                                                            AS backup_type,
    bs.backup_start_date,
    bs.backup_finish_date,
    DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duration_seconds,
    CAST(bs.backup_size / 1024.0 / 1024.0 AS DECIMAL(18,2))      AS backup_size_mb,
    CAST(bs.compressed_backup_size / 1024.0 / 1024.0 AS DECIMAL(18,2))
                                                                   AS compressed_size_mb,
    CASE
        WHEN bs.compressed_backup_size > 0
        THEN CAST(bs.backup_size * 1.0 / bs.compressed_backup_size AS DECIMAL(5,2))
        ELSE NULL
    END                                                            AS compression_ratio,
    bs.server_name,
    bs.recovery_model,
    bmf.physical_device_name                                       AS backup_path
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS bmf
    ON bs.media_set_id = bmf.media_set_id
WHERE bs.backup_finish_date >= DATEADD(DAY, -@DaysBack, GETDATE())
  AND (@BackupType IS NULL OR bs.type = @BackupType)
ORDER BY
    bs.database_name,
    bs.backup_start_date DESC;
