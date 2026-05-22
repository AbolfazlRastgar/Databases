-- ============================================================
-- Project  : SQL Server Extended Events Audit
-- Script   : create_extended_event_session.sql
-- Purpose  : Creates and starts an Extended Events session that
--            captures login events from SQL Server Management
--            Studio (SSMS) connections only.
-- Target   : event_file (persistent, writes to disk)
-- ============================================================
-- Requirements:
--   - ALTER ANY EVENT SESSION permission on the server
--   - The destination folder must exist and SQL Server service
--     account must have write access to it
--   - Tested on SQL Server 2016 and later
-- ============================================================
-- IMPORTANT: Review the file path below before running.
--            Adjust it to match your environment.
-- ============================================================


-- Step 1: Drop the session if it already exists
IF EXISTS (
    SELECT 1
    FROM sys.server_event_sessions
    WHERE name = N'AuditSSMSLogins'
)
BEGIN
    DROP EVENT SESSION [AuditSSMSLogins] ON SERVER;
END
GO


-- Step 2: Create the Extended Events session
CREATE EVENT SESSION [AuditSSMSLogins] ON SERVER

ADD EVENT sqlserver.login (
    -- Collect these fields on every matching login event
    ACTION (
        sqlserver.client_app_name,      -- Application name (e.g. "Microsoft SQL Server Management Studio")
        sqlserver.client_hostname,      -- Machine name of the connecting client
        sqlserver.server_principal_name,-- SQL Server login name
        sqlserver.nt_username,          -- Windows username if using Windows Authentication
        sqlserver.session_id,           -- Session ID assigned to this connection
        sqlserver.database_name         -- Default database at login time
    )
    -- Filter: capture only connections coming from SSMS
    WHERE (
        sqlserver.like_i_sql_unicode_string(N'%Management Studio%', sqlserver.client_app_name) = 1
    )
)

ADD TARGET package0.event_file (
    SET
        -- !! Update this path to a folder that exists on your server !!
        filename          = N'C:\XE_Sessions\AuditSSMSLogins.xel',
        max_file_size     = 50,     -- MB per file
        max_rollover_files = 5      -- Keep last 5 files, then roll over
)

WITH (
    MAX_MEMORY                = 4096 KB,
    EVENT_RETENTION_MODE      = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY      = 5 SECONDS,   -- Flush to file every 5 seconds
    MAX_EVENT_SIZE            = 0 KB,
    MEMORY_PARTITION_MODE     = NONE,
    TRACK_CAUSALITY           = OFF,
    STARTUP_STATE             = ON           -- Session restarts automatically with SQL Server
);
GO


-- Step 3: Start the session
ALTER EVENT SESSION [AuditSSMSLogins] ON SERVER STATE = START;
GO


-- Step 4: Confirm the session is running
SELECT
    name,
    state_desc,
    create_time
FROM sys.dm_xe_sessions
WHERE name = N'AuditSSMSLogins';
GO

-- ============================================================
-- To stop the session without dropping it:
--   ALTER EVENT SESSION [AuditSSMSLogins] ON SERVER STATE = STOP;
--
-- To drop the session entirely:
--   DROP EVENT SESSION [AuditSSMSLogins] ON SERVER;
-- ============================================================
