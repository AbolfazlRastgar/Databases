/*
Script Name:     kill-command-generator.sql
Purpose:         Generates KILL statements for sessions matching specified criteria.
                 Does NOT execute them. Output is a list of KILL commands
                 for review and manual execution.
SQL Server Version: 2008 R2 and later
Required Permissions: VIEW SERVER STATE (to run this script)
                      sysadmin or ALTER ANY CONNECTION (to execute the KILL output)
Safety Level:    Generates commands only — review all output before executing
How to Use:      Set the parameters below to target the sessions you want.
                 Run the script, review the KILL statements in the output,
                 and only then execute them — one at a time if possible.
Notes:           *** WARNING ***
                 Killing a session terminates the connection immediately and
                 rolls back any open transaction. This can cause data changes
                 to be lost and may temporarily increase transaction log usage
                 during rollback.
                 Never run KILL statements in production without understanding
                 which session you are terminating and why.
                 Killing the wrong session can cause application errors or
                 data inconsistency.
                 KILL does not guarantee instant termination — SQL Server must
                 complete the rollback of any in-progress transaction first.
                 Use KILL <session_id> WITH STATUSONLY to check rollback progress.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

-- ============================================================
-- Parameters: adjust to target specific sessions
-- ============================================================
DECLARE @KillSleepingWithOpenTxn  BIT = 1;    -- Sessions sleeping with open transactions
DECLARE @KillBlockedLongerThan    INT = 0;     -- Kill sessions blocked longer than N seconds (0 = disabled)
DECLARE @KillIdleLongerThan       INT = 0;     -- Kill sessions idle longer than N seconds (0 = disabled)
DECLARE @ExcludeSessionId         INT = @@SPID; -- Always exclude the current session

-- ============================================================
-- Generate KILL statements — NO auto-execution
-- ============================================================
SELECT
    'KILL ' + CAST(s.session_id AS VARCHAR(10)) + '; -- '
    + s.login_name + ' | '
    + ISNULL(s.host_name, '') + ' | '
    + ISNULL(s.program_name, '') + ' | '
    + 'Status: ' + s.status + ' | '
    + 'OpenTxn: ' + CAST(s.open_transaction_count AS VARCHAR(5)) + ' | '
    + 'IdleSeconds: ' + CAST(DATEDIFF(SECOND, s.last_request_end_time, GETDATE()) AS VARCHAR(10))
    AS kill_command
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r
    ON s.session_id = r.session_id
WHERE s.is_user_process = 1
  AND s.session_id <> @ExcludeSessionId
  AND (
      -- Sleeping with open transaction
      (@KillSleepingWithOpenTxn = 1
       AND s.status = 'sleeping'
       AND s.open_transaction_count > 0)

      -- Blocked longer than threshold
      OR (@KillBlockedLongerThan > 0
          AND r.blocking_session_id > 0
          AND r.wait_time / 1000 >= @KillBlockedLongerThan)

      -- Idle longer than threshold
      OR (@KillIdleLongerThan > 0
          AND s.status = 'sleeping'
          AND DATEDIFF(SECOND, s.last_request_end_time, GETDATE()) >= @KillIdleLongerThan)
  )
ORDER BY
    s.open_transaction_count DESC,
    s.session_id;
