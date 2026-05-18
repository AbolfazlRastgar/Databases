/*
Script Name:     disabled-jobs-and-schedules.sql
Purpose:         Lists all disabled SQL Agent jobs and all disabled schedules.
                 Useful for auditing what has been turned off and when it
                 was last modified.
SQL Server Version: 2008 and later
Required Permissions: SQLAgentReaderRole in msdb, or sysadmin
Safety Level:    Read-only
How to Use:      Run as-is. Review the output against your expected configuration.
                 Jobs may be disabled for legitimate reasons (e.g. off-peak
                 maintenance windows) or may have been disabled during
                 an incident and never re-enabled.
Notes:           A job can have an active schedule but still not run if the job
                 itself is disabled. A job can be enabled but its schedule
                 can be disabled — in which case the job will only run
                 when started manually or by another job.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

-- ============================================================
-- Section 1: Disabled jobs
-- ============================================================
SELECT
    'Disabled Job'                          AS item_type,
    j.name                                  AS job_name,
    j.description,
    j.date_created,
    j.date_modified,
    c.name                                  AS category,
    l.name                                  AS owner_login
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.syscategories AS c
    ON j.category_id = c.category_id
LEFT JOIN master.sys.server_principals AS l
    ON j.owner_sid = l.sid
WHERE j.enabled = 0
ORDER BY
    j.name;

-- ============================================================
-- Section 2: Disabled schedules (and which jobs use them)
-- ============================================================
SELECT
    'Disabled Schedule'                     AS item_type,
    s.name                                  AS schedule_name,
    j.name                                  AS job_name,
    s.date_created,
    s.date_modified,
    CASE s.freq_type
        WHEN 1   THEN 'Once'
        WHEN 4   THEN 'Daily'
        WHEN 8   THEN 'Weekly'
        WHEN 16  THEN 'Monthly'
        WHEN 32  THEN 'Monthly relative'
        WHEN 64  THEN 'SQL Agent starts'
        WHEN 128 THEN 'Computer idle'
        ELSE CAST(s.freq_type AS VARCHAR(10))
    END                                     AS frequency_type
FROM msdb.dbo.sysschedules AS s
LEFT JOIN msdb.dbo.sysjobschedules AS js
    ON s.schedule_id = js.schedule_id
LEFT JOIN msdb.dbo.sysjobs AS j
    ON js.job_id = j.job_id
WHERE s.enabled = 0
ORDER BY
    s.name,
    j.name;
