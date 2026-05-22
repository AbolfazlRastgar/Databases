-- ============================================================
-- Project  : SQL Server Extended Events Audit
-- Script   : read_extended_event_output.sql
-- Purpose  : Reads and parses captured login events from the
--            AuditSSMSLogins event_file target.
-- ============================================================
-- Requirements:
--   - The event session must have been running and capturing data
--   - The .xel file path below must match what was set in the
--     create script
--   - VIEW SERVER STATE permission required
-- ============================================================
-- NOTE: This script is read-only. It does not modify any data.
-- ============================================================


-- ============================================================
-- Query 1: All captured SSMS login events, newest first
-- ============================================================
SELECT
    event_data.value('(@timestamp)[1]',                              'datetime2(3)')   AS event_timestamp_utc,
    event_data.value('(action[@name="server_principal_name"]/value)[1]', 'nvarchar(256)') AS login_name,
    event_data.value('(action[@name="nt_username"]/value)[1]',           'nvarchar(256)') AS windows_username,
    event_data.value('(action[@name="client_app_name"]/value)[1]',       'nvarchar(256)') AS application_name,
    event_data.value('(action[@name="client_hostname"]/value)[1]',       'nvarchar(256)') AS host_name,
    event_data.value('(action[@name="database_name"]/value)[1]',         'nvarchar(256)') AS database_name,
    event_data.value('(action[@name="session_id"]/value)[1]',            'int')           AS session_id
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file(
        -- !! Update this path to match your environment !!
        N'C:\XE_Sessions\AuditSSMSLogins*.xel',
        NULL, NULL, NULL
    )
) AS raw_data
ORDER BY event_timestamp_utc DESC;
GO


-- ============================================================
-- Query 2: Summary — distinct host/login combinations seen
-- ============================================================
SELECT
    event_data.value('(action[@name="server_principal_name"]/value)[1]', 'nvarchar(256)') AS login_name,
    event_data.value('(action[@name="nt_username"]/value)[1]',           'nvarchar(256)') AS windows_username,
    event_data.value('(action[@name="client_hostname"]/value)[1]',       'nvarchar(256)') AS host_name,
    event_data.value('(action[@name="client_app_name"]/value)[1]',       'nvarchar(256)') AS application_name,
    COUNT(*)                                                                               AS connection_count,
    MIN(event_data.value('(@timestamp)[1]', 'datetime2(3)'))                              AS first_seen_utc,
    MAX(event_data.value('(@timestamp)[1]', 'datetime2(3)'))                              AS last_seen_utc
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file(
        N'C:\XE_Sessions\AuditSSMSLogins*.xel',
        NULL, NULL, NULL
    )
) AS raw_data
GROUP BY
    event_data.value('(action[@name="server_principal_name"]/value)[1]', 'nvarchar(256)'),
    event_data.value('(action[@name="nt_username"]/value)[1]',           'nvarchar(256)'),
    event_data.value('(action[@name="client_hostname"]/value)[1]',       'nvarchar(256)'),
    event_data.value('(action[@name="client_app_name"]/value)[1]',       'nvarchar(256)')
ORDER BY connection_count DESC;
GO


-- ============================================================
-- Query 3: Filter by a specific login name
-- ============================================================
DECLARE @TargetLogin NVARCHAR(256) = N'your_login_here'; -- change this

SELECT
    event_data.value('(@timestamp)[1]',                                  'datetime2(3)')   AS event_timestamp_utc,
    event_data.value('(action[@name="server_principal_name"]/value)[1]', 'nvarchar(256)') AS login_name,
    event_data.value('(action[@name="client_hostname"]/value)[1]',       'nvarchar(256)') AS host_name,
    event_data.value('(action[@name="client_app_name"]/value)[1]',       'nvarchar(256)') AS application_name,
    event_data.value('(action[@name="session_id"]/value)[1]',            'int')           AS session_id
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file(
        N'C:\XE_Sessions\AuditSSMSLogins*.xel',
        NULL, NULL, NULL
    )
) AS raw_data
WHERE
    event_data.value('(action[@name="server_principal_name"]/value)[1]', 'nvarchar(256)') = @TargetLogin
ORDER BY event_timestamp_utc DESC;
GO
