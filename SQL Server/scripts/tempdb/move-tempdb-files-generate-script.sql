/*
Script Name:     move-tempdb-files-generate-script.sql
Purpose:         Generates ALTER DATABASE tempdb MODIFY FILE commands to move
                 TempDB data and log files to a new path. Does NOT execute
                 the commands. Output must be reviewed and run manually.
SQL Server Version: 2005 and later
Required Permissions: VIEW SERVER STATE (to read current file locations);
                      sysadmin (to execute the generated ALTER DATABASE commands)
Safety Level:    Generates commands only — does NOT execute changes
How to Use:      1. Set @NewDataPath and @NewLogPath to your target directories.
                    Include the trailing backslash.
                 2. Run this script and review the output.
                 3. Execute the generated ALTER DATABASE statements in SSMS.
                 4. Restart the SQL Server service.
                 5. Verify the new file locations are in use.
                 6. Manually copy or delete the old files as appropriate.
Notes:           *** SQL Server service restart is required after running the
                 generated commands. TempDB is recreated at startup, so
                 the actual file move happens when SQL Server restarts. ***
                 Do not delete the old TempDB files until you have confirmed
                 that SQL Server has successfully restarted and is using
                 the new paths.
                 The new directory must exist and the SQL Server service account
                 must have read/write/create permissions on it before restart.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

-- ============================================================
-- Set target paths — must include trailing backslash
-- ============================================================
DECLARE @NewDataPath NVARCHAR(500) = N'E:\SQLTempDB\';   -- Target for data files
DECLARE @NewLogPath  NVARCHAR(500) = N'E:\SQLTempDB\';   -- Target for log file

-- ============================================================
-- Generate ALTER DATABASE commands — review before executing
-- ============================================================
SELECT
    'ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'''
    + f.name + ''', FILENAME = N'''
    + CASE
        WHEN f.type_desc = 'LOG'
        THEN @NewLogPath
        ELSE @NewDataPath
      END
    + REVERSE(SUBSTRING(REVERSE(f.physical_name), 1, CHARINDEX('\', REVERSE(f.physical_name)) - 1))
    + ''' );'                                           AS alter_database_command,
    f.file_id,
    f.name                                             AS logical_name,
    f.type_desc,
    f.physical_name                                    AS current_path,
    CASE
        WHEN f.type_desc = 'LOG'
        THEN @NewLogPath
        ELSE @NewDataPath
      END
    + REVERSE(SUBSTRING(REVERSE(f.physical_name), 1, CHARINDEX('\', REVERSE(f.physical_name)) - 1))
                                                       AS new_path
FROM tempdb.sys.database_files AS f
ORDER BY
    f.file_id;

PRINT '';
PRINT '=================================================================';
PRINT 'IMPORTANT: After executing the ALTER DATABASE statements above,';
PRINT 'you MUST restart the SQL Server service for the changes to take';
PRINT 'effect. TempDB will be recreated in the new location at startup.';
PRINT '';
PRINT 'Do not delete the old TempDB files until after a successful';
PRINT 'restart and verification.';
PRINT '=================================================================';
