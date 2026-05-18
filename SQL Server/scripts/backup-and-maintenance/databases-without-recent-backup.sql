/*
Script Name:     databases-without-recent-backup.sql
Purpose:         Identifies databases that have not had a successful backup
                 within configurable time thresholds. Checks separately for
                 full, differential, and log backups.
SQL Server Version: 2008 and later
Required Permissions: SELECT on msdb.dbo.backupset; VIEW ANY DATABASE
Safety Level:    Read-only
How to Use:      Adjust the threshold variables to match your RPO requirements.
                 Databases without any backup record in msdb (e.g. new databases,
                 or databases where history was cleared) will show NULL dates
                 and will appear as missing.
                 System databases (master, model, msdb) are included by default.
                 Tempdb is excluded — it cannot be backed up.
Notes:           A database on SIMPLE recovery model will not have log backups
                 and should not be expected to. The script uses the recovery
                 model from sys.databases to contextualize missing log backups.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @FullBackupThresholdHours  INT = 25;   -- Alert if no full backup in this many hours
DECLARE @DiffBackupThresholdHours  INT = 0;    -- 0 = do not check for diff backups
DECLARE @LogBackupThresholdMinutes INT = 60;   -- Alert if no log backup in this many minutes

SELECT
    d.name                                      AS database_name,
    d.recovery_model_desc,
    d.state_desc,
    -- Last full backup
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END)
                                                AS last_full_backup,
    -- Last differential backup
    MAX(CASE WHEN bs.type = 'I' THEN bs.backup_finish_date END)
                                                AS last_diff_backup,
    -- Last log backup
    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END)
                                                AS last_log_backup,
    -- Flags for missing backups
    CASE
        WHEN MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) IS NULL
          OR DATEDIFF(HOUR,
                MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END),
                GETDATE()) > @FullBackupThresholdHours
        THEN 'MISSING'
        ELSE 'OK'
    END                                         AS full_backup_status,
    CASE
        WHEN d.recovery_model_desc <> 'SIMPLE'
          AND (
            MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) IS NULL
            OR DATEDIFF(MINUTE,
                MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END),
                GETDATE()) > @LogBackupThresholdMinutes
          )
        THEN 'MISSING'
        WHEN d.recovery_model_desc = 'SIMPLE'
        THEN 'N/A (SIMPLE)'
        ELSE 'OK'
    END                                         AS log_backup_status
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON d.name = bs.database_name
WHERE d.name <> 'tempdb'
  AND d.state_desc = 'ONLINE'
GROUP BY
    d.name,
    d.recovery_model_desc,
    d.state_desc
HAVING
    -- Only show databases with at least one missing backup
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) IS NULL
    OR DATEDIFF(HOUR,
            MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END),
            GETDATE()) > @FullBackupThresholdHours
    OR (
        d.recovery_model_desc <> 'SIMPLE'
        AND (
            MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) IS NULL
            OR DATEDIFF(MINUTE,
                    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END),
                    GETDATE()) > @LogBackupThresholdMinutes
        )
    )
ORDER BY
    d.name;
