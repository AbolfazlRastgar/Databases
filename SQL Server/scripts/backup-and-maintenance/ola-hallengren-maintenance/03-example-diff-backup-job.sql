/*
Script Name:     03-example-diff-backup-job.sql
Purpose:         Example SQL Agent job step command for differential database
                 backups using Ola Hallengren's DatabaseBackup procedure.
SQL Server Version: 2008 and later
Required Permissions: sysadmin (for SQL Agent job creation and backup operations)
Safety Level:    Changes server state — creates backups to disk
How to Use:      Copy the EXEC statement into a SQL Agent job step.
                 Differential backups are typically scheduled several times
                 per day between full backups. They only contain changes since
                 the last full backup.
Notes:           Differential backups are only useful in restore scenarios when
                 combined with the most recent full backup. Ensure your restore
                 procedures account for this dependency.
                 Ola Hallengren's DatabaseBackup must be installed before use.
                 Download from: https://ola.hallengren.com
Author:          Abolfazl Rastgar
*/

EXECUTE master.dbo.DatabaseBackup
    @Databases              = 'USER_DATABASES',
    @Directory              = 'D:\SQLBackups',      -- Change to your backup path
    @BackupType             = 'DIFF',
    @Verify                 = 'Y',
    @CleanupTime            = 48,                   -- Differential files can be cleaned sooner
    @CleanupMode            = 'AFTER_BACKUP',
    @Compress               = 'Y',
    @CheckSum               = 'Y',
    @LogToTable             = 'Y';
