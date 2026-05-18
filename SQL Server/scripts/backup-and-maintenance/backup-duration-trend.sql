/*
Script Name:     backup-duration-trend.sql
Purpose:         Shows backup duration trends from msdb history, grouped by
                 database and backup type. Useful for identifying databases
                 whose backups are taking progressively longer, or for spotting
                 recent backup slowdowns.
SQL Server Version: 2008 and later
Required Permissions: SELECT on msdb.dbo.backupset
Safety Level:    Read-only
How to Use:      Run as-is to see the trend over the last 30 days.
                 Adjust @DaysBack and @BackupType as needed.
                 Use the avg_duration_seconds and max_duration_seconds columns
                 to identify databases that deserve attention.
Notes:           Duration is calculated as the difference between
                 backup_start_date and backup_finish_date, which may include
                 some overhead not specific to I/O (e.g. VSS initialization).
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @DaysBack   INT    = 30;
DECLARE @BackupType CHAR(1) = 'D';  -- 'D' = Full, 'I' = Diff, 'L' = Log

SELECT
    bs.database_name,
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type
    END                                                             AS backup_type,
    COUNT(*)                                                        AS backup_count,
    MIN(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date))
                                                                    AS min_duration_seconds,
    MAX(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date))
                                                                    AS max_duration_seconds,
    AVG(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date))
                                                                    AS avg_duration_seconds,
    MIN(bs.backup_finish_date)                                      AS oldest_backup_in_range,
    MAX(bs.backup_finish_date)                                      AS most_recent_backup,
    AVG(CAST(bs.backup_size / 1024.0 / 1024.0 AS DECIMAL(18,2)))   AS avg_size_mb,
    AVG(CAST(bs.compressed_backup_size / 1024.0 / 1024.0 AS DECIMAL(18,2)))
                                                                    AS avg_compressed_size_mb
FROM msdb.dbo.backupset AS bs
WHERE bs.backup_finish_date >= DATEADD(DAY, -@DaysBack, GETDATE())
  AND bs.type = @BackupType
GROUP BY
    bs.database_name,
    bs.type
ORDER BY
    avg_duration_seconds DESC;
