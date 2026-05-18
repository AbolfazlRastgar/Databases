/*
Script Name:     04-example-log-backup-job.sql
Purpose:         Example SQL Agent job step command for transaction log backups
                 using Ola Hallengren's DatabaseBackup procedure.
SQL Server Version: 2008 and later
Required Permissions: sysadmin (for SQL Agent job creation and backup operations)
Safety Level:    Changes server state — creates backups to disk
How to Use:      Copy the EXEC statement into a SQL Agent job step.
                 Log backups should run frequently — every 15-60 minutes is
                 typical, depending on your RPO requirements and log volume.
                 Only applies to databases in FULL or BULK_LOGGED recovery model.
Notes:           Log backups truncate the active portion of the log after the
                 backup completes, allowing the log file space to be reused.
                 If log backups are not running, the log file will grow
                 indefinitely.
                 Ola Hallengren's DatabaseBackup must be installed before use.
                 Download from: https://ola.hallengren.com
Author:          Abolfazl Rastgar
*/

EXECUTE master.dbo.DatabaseBackup
    @Databases              = 'USER_DATABASES',
    @Directory              = 'D:\SQLBackups',      -- Change to your backup path
    @BackupType             = 'LOG',
    @Verify                 = 'Y',
    @CleanupTime            = 24,                   -- Adjust based on your log retention needs
    @CleanupMode            = 'AFTER_BACKUP',
    @Compress               = 'Y',
    @CheckSum               = 'Y',
    @LogToTable             = 'Y';
