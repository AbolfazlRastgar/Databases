/*
Script Name:     05-check-commandlog-results.sql
Purpose:         Queries the CommandLog table created by Ola Hallengren's
                 maintenance solution to review recent maintenance history.
                 Shows successful and failed operations, durations, and
                 error messages.
SQL Server Version: 2008 and later
Required Permissions: SELECT on dbo.CommandLog in the database where the
                      solution is installed (typically master)
Safety Level:    Read-only
How to Use:      Run as-is. Adjust @DaysBack, @CommandType, and the
                 @ShowFailedOnly parameter to focus the output.
                 Common CommandType values:
                   BACKUP_DATABASE
                   BACKUP_LOG
                   DBCC_CHECKDB
                   ALTER_INDEX_REBUILD
                   ALTER_INDEX_REORGANIZE
                   UPDATE_STATISTICS
Notes:           The CommandLog table is populated only when @LogToTable = 'Y'
                 is set in the maintenance procedure calls.
                 If the table is empty, logging was not enabled.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @DaysBack      INT          = 7;
DECLARE @CommandType   NVARCHAR(50) = NULL;   -- NULL = all types
DECLARE @ShowFailedOnly BIT         = 0;       -- 1 = only show failed commands

SELECT
    cl.ID,
    cl.StartTime,
    cl.EndTime,
    DATEDIFF(SECOND, cl.StartTime, cl.EndTime)  AS duration_seconds,
    cl.DatabaseName,
    cl.CommandType,
    cl.Command,
    cl.ErrorNumber,
    cl.ErrorMessage,
    CASE WHEN cl.ErrorNumber IS NULL THEN 'Success' ELSE 'Failed' END AS result
FROM master.dbo.CommandLog AS cl   -- Adjust database prefix if installed elsewhere
WHERE cl.StartTime >= DATEADD(DAY, -@DaysBack, GETDATE())
  AND (@CommandType IS NULL OR cl.CommandType = @CommandType)
  AND (@ShowFailedOnly = 0 OR cl.ErrorNumber IS NOT NULL)
ORDER BY
    cl.StartTime DESC;
