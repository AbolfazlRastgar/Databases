# SQL Server Extended Events Audit

## Overview

This project provides a lightweight Extended Events session for monitoring and auditing SSMS connection activity on a SQL Server instance.

Extended Events is the recommended alternative to SQL Trace and Profiler. It offers low overhead, fine-grained control over what gets captured, and persistent output via `event_file`. This project uses it to capture login events originating specifically from SQL Server Management Studio — useful for identifying unexpected or unauthorized connections in production environments.

---

## What This Project Captures

The session listens on the `sqlserver.login` event and filters to SSMS connections only. For each matching login, the following is recorded:

- Login name (SQL or Windows)
- Windows username (if using Windows Authentication)
- Client application name
- Client host name
- Default database at login time
- Session ID
- Event timestamp (UTC)

---

## Use Case

This setup is useful when you need to answer questions such as:

- Is anyone connecting to this production instance directly from SSMS?
- Which machines and accounts have been opening SSMS sessions?
- What connection activity occurred during a specific time window?
- Are there unexpected logins that need to be reviewed?

It is practical for lightweight auditing, production troubleshooting, access reviews, and building a personal security/monitoring toolbox.

---

## Files

| File | Description |
|---|---|
| `create_extended_event_session.sql` | Creates and starts the Extended Events session |
| `read_extended_event_output.sql` | Reads and parses the captured event data (3 queries) |
| `README.md` | Project documentation |

---

## How to Use

1. **Review both scripts before running anything.** Update the file path `C:\XE_Sessions\` to a folder that exists on your server and is writable by the SQL Server service account.

2. **Run the creation script:**
   ```sql
   -- Creates the session and starts it
   -- STARTUP_STATE = ON means it will restart with SQL Server
   ```
   Execute `create_extended_event_session.sql` on the target instance.

3. **Confirm the session is running:**
   ```sql
   SELECT name, state_desc, create_time
   FROM sys.dm_xe_sessions
   WHERE name = N'AuditSSMSLogins';
   ```

4. **Review captured data** by running any of the three queries in `read_extended_event_output.sql`:
   - **Query 1** — All events, newest first
   - **Query 2** — Summary grouped by login/host/application
   - **Query 3** — Filter by a specific login name

5. **Stop or drop the session when no longer needed:**
   ```sql
   -- Stop without removing the session definition
   ALTER EVENT SESSION [AuditSSMSLogins] ON SERVER STATE = STOP;

   -- Drop entirely
   DROP EVENT SESSION [AuditSSMSLogins] ON SERVER;
   ```

---

## Script Reference

### create_extended_event_session.sql

```sql
CREATE EVENT SESSION [AuditSSMSLogins] ON SERVER

ADD EVENT sqlserver.login (
    ACTION (
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.server_principal_name,
        sqlserver.nt_username,
        sqlserver.session_id,
        sqlserver.database_name
    )
    WHERE (
        sqlserver.like_i_sql_unicode_string(N'%Management Studio%', sqlserver.client_app_name) = 1
    )
)

ADD TARGET package0.event_file (
    SET
        filename           = N'C:\XE_Sessions\AuditSSMSLogins.xel',
        max_file_size      = 50,
        max_rollover_files = 5
)

WITH (
    MAX_MEMORY             = 4096 KB,
    EVENT_RETENTION_MODE   = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY   = 5 SECONDS,
    STARTUP_STATE          = ON
);

ALTER EVENT SESSION [AuditSSMSLogins] ON SERVER STATE = START;
```

### read_extended_event_output.sql

```sql
-- All captured events, newest first
SELECT
    event_data.value('(@timestamp)[1]',                                  'datetime2(3)')   AS event_timestamp_utc,
    event_data.value('(action[@name="server_principal_name"]/value)[1]', 'nvarchar(256)')  AS login_name,
    event_data.value('(action[@name="nt_username"]/value)[1]',           'nvarchar(256)')  AS windows_username,
    event_data.value('(action[@name="client_app_name"]/value)[1]',       'nvarchar(256)')  AS application_name,
    event_data.value('(action[@name="client_hostname"]/value)[1]',       'nvarchar(256)')  AS host_name,
    event_data.value('(action[@name="database_name"]/value)[1]',         'nvarchar(256)')  AS database_name,
    event_data.value('(action[@name="session_id"]/value)[1]',            'int')            AS session_id
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file(
        N'C:\XE_Sessions\AuditSSMSLogins*.xel',
        NULL, NULL, NULL
    )
) AS raw_data
ORDER BY event_timestamp_utc DESC;
```

---

## Notes

- Run in a non-production environment first to validate the path, permissions, and filter behavior.
- The destination folder (`C:\XE_Sessions\`) must exist before the session is started. SQL Server will not create it automatically.
- Required permission: `ALTER ANY EVENT SESSION`. Reading the output file also requires access to the file path or `VIEW SERVER STATE`.
- `STARTUP_STATE = ON` means the session will restart automatically when SQL Server restarts. Change to `OFF` if you want manual control.
- The `event_file` target uses rollover files. With `max_file_size = 50` MB and `max_rollover_files = 5`, the total disk usage is capped at approximately 250 MB.
- On a busy instance, SSMS connections can be frequent. Review the volume of captured events before running this in production for extended periods.
- This is not a replacement for a proper auditing strategy. For compliance-driven or long-term auditing, use SQL Server Audit.

---

## Disclaimer

This project is intended for learning, troubleshooting, and lightweight monitoring purposes. Review and adapt all scripts before using them in a production environment. The author takes no responsibility for any issues arising from direct use without prior testing and validation.
