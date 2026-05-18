/*
Script Name:     02-example-full-backup-job.sql
Purpose:         Example SQL Agent job step command for running full database
                 backups using Ola Hallengren's DatabaseBackup procedure.
                 This is an example only — adjust parameters to match your
                 environment before using.
SQL Server Version: 2008 and later
Required Permissions: sysadmin (for SQL Agent job creation and backup operations)
Safety Level:    Changes server state — creates backups to disk
How to Use:      Copy the EXEC statement into a SQL Agent job step.
                 The job step type should be "Transact-SQL script (T-SQL)".
                 Adjust all parameters, especially @Directory and @CleanupTime.
Notes:           Ola Hallengren's DatabaseBackup must be installed before use.
                 Download from: https://ola.hallengren.com
                 This script does not install or modify DatabaseBackup.
Author:          Abolfazl Rastgar
*/

-- ============================================================
-- Full backup of all user databases
-- Adjust parameters to match your environment
-- ============================================================
EXECUTE master.dbo.DatabaseBackup
    @Databases              = 'USER_DATABASES',
    @Directory              = 'D:\SQLBackups',      -- Change to your backup path
    @BackupType             = 'FULL',
    @Verify                 = 'Y',
    @CleanupTime            = 72,                   -- Delete files older than 72 hours
    @CleanupMode            = 'AFTER_BACKUP',
    @Compress               = 'Y',
    @CheckSum               = 'Y',
    @LogToTable             = 'Y';

-- ============================================================
-- Full backup of system databases (run separately or in a
-- separate job step)
-- ============================================================
/*
EXECUTE master.dbo.DatabaseBackup
    @Databases              = 'SYSTEM_DATABASES',
    @Directory              = 'D:\SQLBackups',
    @BackupType             = 'FULL',
    @Verify                 = 'Y',
    @CleanupTime            = 72,
    @CleanupMode            = 'AFTER_BACKUP',
    @Compress               = 'Y',
    @CheckSum               = 'Y',
    @LogToTable             = 'Y';
*/
