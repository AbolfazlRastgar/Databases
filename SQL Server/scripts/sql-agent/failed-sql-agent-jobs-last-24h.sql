/*
Script Name:     failed-sql-agent-jobs-last-24h.sql
Purpose:         Shows SQL Agent jobs that failed in the last 24 hours.
                 Reports job name, step name, run date and time, duration,
                 and the error message recorded in job history.
SQL Server Version: 2008 and later
Required Permissions: SELECT on msdb job history tables;
                      SQLAgentReaderRole in msdb is sufficient.
Safety Level:    Read-only
How to Use:      Run as-is for the last 24 hours.
                 Adjust @HoursBack to extend the search window.
                 The message column contains the error text logged by SQL Agent,
                 which may include the actual T-SQL error if the job step
                 captured it.
Notes:           run_status values: 0=Failed, 1=Succeeded, 2=Retry, 3=Cancelled
                 This script filters for run_status = 0 (Failed) only.
                 The run_date and run_time columns in msdb are stored as integers
                 (YYYYMMDD and HHMMSS). They are converted to datetime below.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @HoursBack INT = 24;

SELECT
    j.name                                                          AS job_name,
    js.step_id,
    js.step_name,
    jh.run_status,
    -- Convert msdb integer date/time to datetime
    MSDB.dbo.agent_datetime(jh.run_date, jh.run_time)             AS run_start_datetime,
    -- Duration stored as HHMMSS integer
    (jh.run_duration / 10000) * 3600
    + ((jh.run_duration % 10000) / 100) * 60
    + (jh.run_duration % 100)                                      AS duration_seconds,
    jh.message                                                      AS error_message,
    j.enabled                                                       AS job_enabled,
    j.description                                                   AS job_description
FROM msdb.dbo.sysjobhistory AS jh
INNER JOIN msdb.dbo.sysjobs AS j
    ON jh.job_id = j.job_id
INNER JOIN msdb.dbo.sysjobsteps AS js
    ON jh.job_id = js.job_id
    AND jh.step_id = js.step_id
WHERE jh.run_status = 0   -- Failed
  AND MSDB.dbo.agent_datetime(jh.run_date, jh.run_time) >= DATEADD(HOUR, -@HoursBack, GETDATE())
ORDER BY
    MSDB.dbo.agent_datetime(jh.run_date, jh.run_time) DESC;
