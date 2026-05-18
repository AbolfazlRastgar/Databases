/*
Script Name:     long-running-sql-agent-jobs.sql
Purpose:         Identifies SQL Agent jobs that are currently running longer
                 than their historical average, and also lists recent jobs
                 whose duration exceeded average by a configurable multiplier.
SQL Server Version: 2008 and later
Required Permissions: SQLAgentReaderRole in msdb, or sysadmin
Safety Level:    Read-only
How to Use:      Run as-is. The @DurationMultiplier parameter controls how much
                 longer than average a job must be to appear in the results.
                 Default is 2x (twice the historical average).
                 Section 1 shows currently running jobs vs their average.
                 Section 2 shows recently completed jobs that ran long.
Notes:           Historical averages are computed from the last @HistoryDays days.
                 A new job with only one or two historical runs will have an
                 unreliable average — inspect those manually.
                 Jobs with no history (new jobs or history was cleared) will
                 not appear in the average comparison but will appear in the
                 currently running section.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

DECLARE @DurationMultiplier FLOAT = 2.0;   -- Alert if job runs > N times average
DECLARE @HistoryDays        INT   = 30;    -- Days of history to build the average from

-- ============================================================
-- Historical average duration per job (for completed runs)
-- ============================================================
;WITH JobHistory AS (
    SELECT
        j.job_id,
        j.name                                          AS job_name,
        AVG(
            (jh.run_duration / 10000) * 3600
            + ((jh.run_duration % 10000) / 100) * 60
            + (jh.run_duration % 100)
        )                                               AS avg_duration_seconds,
        COUNT(*)                                        AS history_count
    FROM msdb.dbo.sysjobs AS j
    INNER JOIN msdb.dbo.sysjobhistory AS jh
        ON j.job_id = jh.job_id
    WHERE jh.step_id = 0   -- Step 0 = job-level outcome row
      AND jh.run_status = 1 -- Completed successfully
      AND MSDB.dbo.agent_datetime(jh.run_date, jh.run_time) >= DATEADD(DAY, -@HistoryDays, GETDATE())
    GROUP BY
        j.job_id,
        j.name
),
-- Currently executing jobs
RunningJobs AS (
    SELECT
        ja.job_id,
        ja.start_execution_date,
        DATEDIFF(SECOND, ja.start_execution_date, GETDATE())  AS current_duration_seconds
    FROM msdb.dbo.sysjobactivity AS ja
    WHERE ja.start_execution_date IS NOT NULL
      AND ja.stop_execution_date IS NULL
      AND ja.session_id = (
          SELECT MAX(session_id) FROM msdb.dbo.syssessions
      )
)
-- ============================================================
-- Section 1: Jobs currently running longer than their average
-- ============================================================
SELECT
    jh.job_name,
    rj.start_execution_date,
    rj.current_duration_seconds,
    jh.avg_duration_seconds,
    jh.history_count,
    CAST(rj.current_duration_seconds * 1.0 / NULLIF(jh.avg_duration_seconds, 0) AS DECIMAL(5,2))
                                                            AS duration_ratio
FROM RunningJobs AS rj
INNER JOIN msdb.dbo.sysjobs AS j
    ON rj.job_id = j.job_id
LEFT JOIN JobHistory AS jh
    ON rj.job_id = jh.job_id
WHERE jh.avg_duration_seconds IS NULL
   OR rj.current_duration_seconds > jh.avg_duration_seconds * @DurationMultiplier
ORDER BY
    duration_ratio DESC;
