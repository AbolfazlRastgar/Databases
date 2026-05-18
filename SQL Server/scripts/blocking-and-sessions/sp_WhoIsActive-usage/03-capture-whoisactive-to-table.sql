/*
Script Name:     03-capture-whoisactive-to-table.sql
Purpose:         Captures sp_WhoIsActive output to a table for later analysis.
                 Useful for recording activity during a known performance
                 window, or for automated interval-based capture via SQL Agent.
SQL Server Version: sp_WhoIsActive supports SQL Server 2005 and later
Required Permissions: VIEW SERVER STATE; CREATE TABLE in target database
Safety Level:    Read-only (the capture itself does not change server state)
How to Use:      1. Create the capture table using sp_WhoIsActive's built-in
                    schema helper (Section 1 below).
                 2. Run the capture loop (Section 2) or schedule it as a job.
                 3. Query the table afterward (Section 3).
Notes:           sp_WhoIsActive must be installed before running these examples.
                 Download from: http://whoisactive.com

                 The schema of the output table depends on which parameters
                 you pass to sp_WhoIsActive. If you change parameters, you
                 may need to drop and recreate the table.

                 For long-running captures, use a SQL Agent job rather than
                 a WHILE loop in SSMS to avoid connection timeouts.
Author:          Abolfazl Rastgar
*/

-- ============================================================
-- SECTION 1: Create the capture table
-- Run this once to create the table with the correct schema.
-- sp_WhoIsActive generates the CREATE TABLE statement based on
-- the parameters you intend to use.
-- ============================================================

DECLARE @schema NVARCHAR(MAX);
DECLARE @create NVARCHAR(MAX);

EXEC sp_WhoIsActive
    @get_full_inner_text = 1,
    @return_schema       = 1,
    @schema              = @schema OUTPUT;

-- Target table: change database/schema/table name as needed
SET @create = REPLACE(@schema, '<table_name>', '[dbo].[WhoIsActiveCapture]');
EXEC (@create);

-- Optionally add a capture timestamp column (not included by default)
ALTER TABLE [dbo].[WhoIsActiveCapture]
ADD capture_time DATETIME NOT NULL DEFAULT GETDATE();


-- ============================================================
-- SECTION 2: Capture loop — runs every N seconds for N minutes
-- For production use, replace this loop with a SQL Agent job
-- ============================================================

DECLARE @Iterations  INT = 12;      -- Number of captures
DECLARE @IntervalSec INT = 5;       -- Seconds between captures
DECLARE @i INT = 0;

WHILE @i < @Iterations
BEGIN
    EXEC sp_WhoIsActive
        @get_full_inner_text = 1,
        @destination_table   = '[dbo].[WhoIsActiveCapture]';

    SET @i += 1;

    IF @i < @Iterations
        WAITFOR DELAY '00:00:05';   -- Match @IntervalSec value above
END


-- ============================================================
-- SECTION 3: Review captured data
-- ============================================================

-- All captures ordered by time
SELECT *
FROM [dbo].[WhoIsActiveCapture]
ORDER BY capture_time DESC;

-- Sessions that appeared most frequently (sustained activity)
SELECT
    login_name,
    host_name,
    program_name,
    database_name,
    COUNT(*)    AS appearance_count,
    MAX(CAST(REPLACE(REPLACE(cpu, ',', ''), ' ', '') AS BIGINT)) AS peak_cpu
FROM [dbo].[WhoIsActiveCapture]
GROUP BY
    login_name,
    host_name,
    program_name,
    database_name
ORDER BY
    appearance_count DESC;
