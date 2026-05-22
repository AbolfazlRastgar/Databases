# SQL Server Crisis Toolbox: Practical Checks When Production Is on Fire

> **Who this is for:** SQL Server DBAs, Data Engineers, Backend/Platform Engineers.  
> **What this is:** A runbook for real incidents. Not a tutorial.  
> **Versions:** SQL Server 2019, 2022, Azure SQL Managed Instance.  
> **Revision notes:** This version corrects three script bugs, removes an outdated PLE threshold, adds the DAC section, adds permissions requirements, and fixes the CXPACKET/CXCONSUMER and `dm_exec_query_stats` descriptions from the previous edition.

---

## Table of Contents

1. [First 5 Minutes: Do Not Guess](#1-first-5-minutes-do-not-guess)
2. [Quick Incident Flow](#2-quick-incident-flow)
3. [Permissions Reference](#3-permissions-reference)
4. [Tool / Script Sections](#4-tool--script-sections)
   - [4.1 sp_WhoIsActive](#41-sp_whoisactive)
   - [4.2 Find the Head Blocker](#42-find-the-head-blocker)
   - [4.3 Check Current Waits](#43-check-current-waits)
   - [4.4 High CPU Investigation](#44-high-cpu-investigation)
   - [4.5 Memory Pressure Investigation](#45-memory-pressure-investigation)
   - [4.6 I/O Pressure Investigation](#46-io-pressure-investigation)
   - [4.7 Query Store Emergency Usage](#47-query-store-emergency-usage)
   - [4.8 SQL Agent Jobs](#48-sql-agent-jobs)
   - [4.9 Always On AG Health Check](#49-always-on-ag-health-check)
   - [4.10 TempDB Emergency Check](#410-tempdb-emergency-check)
   - [4.11 Long Transactions and Log Growth](#411-long-transactions-and-log-growth)
   - [4.12 Deadlocks](#412-deadlocks)
   - [4.13 Error Log and Recent Critical Events](#413-error-log-and-recent-critical-events)
   - [4.14 Security / Suspicious Activity Quick Checks](#414-security--suspicious-activity-quick-checks)
   - [4.15 Backup / Restore Risk Check](#415-backup--restore-risk-check)
5. [Crisis Decision Matrix](#5-crisis-decision-matrix)
6. [What Not To Do During a SQL Server Incident](#6-what-not-to-do-during-a-sql-server-incident)
7. [Final Printable Checklist](#7-final-printable-checklist)
8. [References](#8-references)

---

## 1. First 5 Minutes: Do Not Guess

You got an alert. Users are complaining. The dashboard is red.

**Stop. Gather evidence before touching anything.**

### Step 1 — Can you connect at all?

Try connecting from SSMS or `sqlcmd`. If you cannot connect:

**Option A — Normal connection attempt:**
```
sqlcmd -S <server_name> -E
```

**Option B — DAC (Dedicated Administrator Connection):**

If all normal connections are exhausted (you get "maximum number of connections" or "THREADPOOL" errors), the DAC is the only way in. SQL Server reserves one DAC slot that bypasses the normal connection pool.

```
-- Command line (local):
sqlcmd -S admin:<server_name> -E

-- Command line (remote — requires remote admin connections = 1):
sqlcmd -S admin:<server_name>,1433 -E

-- SSMS: In the server name box, type:
admin:<server_name>
```

> ⚠️ **DAC important notes:**
> - Only ONE DAC connection is allowed at a time. Do not open multiple.
> - Remote DAC requires `sp_configure 'remote admin connections', 1` to have been set beforehand. Check this in advance on all production servers — you cannot set it during an incident if you cannot connect.
> - The DAC uses a reserved scheduler and is much slower than normal connections. Use it only for diagnosis, not for running workloads.
> - Requires sysadmin role.

```sql
-- Verify remote DAC is enabled (run before an incident, from a normal connection):
SELECT name, value_in_use 
FROM sys.configurations 
WHERE name = 'remote admin connections';
-- value_in_use = 1 means remote DAC is available
```

If SQL Server is not reachable even via DAC, the problem is at the OS, network, or service level — check:
- Is the SQL Server service running? (`sc query mssqlserver` or Cluster Admin)
- Is port 1433 open? (`Test-NetConnection -ComputerName <server> -Port 1433`)
- Is the AG listener resolving? (DNS / VNN issue)

### Step 2 — Is it the instance or one database?

```sql
-- Read-only. Requires VIEW ANY DATABASE or sysadmin.
SELECT name, state_desc, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases
ORDER BY name;
```

Look for: `OFFLINE`, `SUSPECT`, `RECOVERING`, `RESTORING`. Any of these on a production database is immediate priority.

### Step 3 — Identify the category before running anything else

| Symptom | Likely Category |
|---|---|
| Everything slow, waits everywhere | Instance-level: CPU, memory, or I/O |
| One query or one app is slow | Query-level |
| App hangs waiting for locks | Blocking |
| AG alert fired, reads failing | HA/DR |
| Disk alerts, backup failures | Storage / I/O |
| Errors in logs, no connections available | Service / configuration |
| Deadlock errors in application | Concurrency |

Do not assume CPU is the root cause because Task Manager shows 100%. CPU can be a *symptom* of blocking, excessive parallelism, memory pressure, or a missing index — not a standalone cause.

### Step 4 — What NOT to do immediately

> ⚠️ **Do not do any of the following without evidence:**
>
> - Restart the SQL Server service
> - `KILL` sessions blindly
> - `DBCC FREEPROCCACHE` without a specific target plan handle
> - Fail over an Availability Group
> - Shrink database files
> - Run index rebuilds
>
> Each of these can worsen the incident and destroys the forensic evidence needed to find the root cause.

---

## 2. Quick Incident Flow

```
Users report slowness or errors
        │
        ▼
[ 4.1 sp_WhoIsActive ] ─── What is running right now?
        │
        ├─ Cannot connect? ────────────────────► Use DAC [ Section 1, Step 1 ]
        │
        ├─ Blocked sessions? ──────────────────► [ 4.2 Head Blocker ]
        │
        ├─ High waits? ────────────────────────► [ 4.3 Current Waits ]
        │
        ├─ CPU high? ──────────────────────────► [ 4.4 CPU Investigation ]
        │
        ├─ Memory pressure? ───────────────────► [ 4.5 Memory Investigation ]
        │
        ├─ Disk/I/O alerts? ───────────────────► [ 4.6 I/O Investigation ]
        │
        ├─ Query suddenly slow? ───────────────► [ 4.7 Query Store ]
        │
        ├─ Maintenance job running? ───────────► [ 4.8 SQL Agent Jobs ]
        │
        ├─ AG unhealthy / failover? ───────────► [ 4.9 AG Health Check ]
        │
        ├─ TempDB full? ───────────────────────► [ 4.10 TempDB Check ]
        │
        ├─ Log file growing? ──────────────────► [ 4.11 Long Transactions ]
        │
        ├─ Deadlock errors? ───────────────────► [ 4.12 Deadlocks ]
        │
        ├─ Corruption / critical errors? ─────► [ 4.13 Error Log ]
        │
        ├─ Suspicious sessions? ───────────────► [ 4.14 Security Checks ]
        │
        └─ Before any risky action: ───────────► [ 4.15 Backup Risk Check ]
```

---

## 3. Permissions Reference

Most scripts in this guide require at minimum **`VIEW SERVER STATE`**. Some require sysadmin. If you arrive on scene without sysadmin, request the following:

| Permission | Grants access to |
|---|---|
| `VIEW SERVER STATE` | Most DMVs: `dm_exec_*`, `dm_os_*`, `dm_io_*`, `dm_hadr_*`, `dm_tran_*` |
| `VIEW ANY DATABASE` | `sys.databases` across all databases |
| `VIEW DATABASE STATE` | Database-scoped DMVs when not sysadmin |
| `SQLAgentReaderRole` in msdb | `msdb.dbo.sysjobhistory`, `sysjobactivity`, `sysjobs` |
| `sysadmin` | DAC, `xp_readerrorlog`, `sp_configure`, all of the above |
| `CONTROL SERVER` | `xp_readerrorlog` (alternative to sysadmin for some operations) |

```sql
-- Check what permissions the current login has:
SELECT 
    spr.name        AS role_name,
    sp.name         AS login_name
FROM sys.server_role_members srm
JOIN sys.server_principals spr ON srm.role_principal_id = spr.principal_id
JOIN sys.server_principals sp  ON srm.member_principal_id = sp.principal_id
WHERE sp.name = SUSER_SNAME()
ORDER BY spr.name;

-- Check server-level permissions explicitly granted:
SELECT permission_name, state_desc
FROM sys.server_permissions
WHERE grantee_principal_id = SUSER_ID();
```

---

## 4. Tool / Script Sections

---

### 4.1 sp_WhoIsActive

**Permissions required:** `VIEW SERVER STATE`, plus the permissions of the account the procedure was installed under. Typically needs sysadmin or VIEW SERVER STATE at minimum.

#### When to use it
Always. First. Every incident. Run it within 60 seconds of starting any investigation.

#### What question it answers
> *What is SQL Server doing right now — who is running, waiting, blocking, or consuming resources?*

#### Installation
`sp_WhoIsActive` is a free stored procedure by Adam Machanic. It is not built into SQL Server.

- **Official repository:** https://github.com/amachanic/sp_whoisactive  
- **Direct download:** http://whoisactive.com

Install it in a DBA utility database (e.g., `DBATools` or `master`). Do this **before** an incident — not during one.

#### Core usage examples

**1 — See all active sessions:**
```sql
EXEC sp_WhoIsActive;
```

**2 — Include blocking info and open transactions:**
```sql
EXEC sp_WhoIsActive @show_sleeping_spids = 1, @get_locks = 1;
```

**3 — Include wait detail:**
```sql
EXEC sp_WhoIsActive @get_task_info = 2;
```

**4 — Include tempdb usage and transaction info:**
```sql
EXEC sp_WhoIsActive @get_additional_info = 1;
```

**5 — Include the actual SQL text and execution plan:**
```sql
EXEC sp_WhoIsActive @get_plans = 1;
```

**6 — Capture to a table in a loop (use during intermittent or ongoing incidents):**
```sql
-- Step 1: Create the capture table once.
-- The schema is dynamically generated based on the parameters you pass.
-- Use the same parameters in @return_schema as you will use in the loop.
DECLARE @schema VARCHAR(4000);
EXEC sp_WhoIsActive
    @get_plans         = 1,
    @get_task_info     = 2,
    @get_additional_info = 1,
    @return_schema     = 1,
    @schema            = @schema OUTPUT;
EXEC('CREATE TABLE dbo.WhoIsActiveCapture ' + @schema);

-- Step 2: Loop every 10 seconds for 5 minutes (30 iterations).
-- Run this in a separate SSMS window. Press Stop to end early.
DECLARE @i INT = 0;
WHILE @i < 30
BEGIN
    EXEC sp_WhoIsActive
        @get_plans           = 1,
        @get_task_info       = 2,
        @get_additional_info = 1,
        @destination_table   = 'dbo.WhoIsActiveCapture';
    WAITFOR DELAY '00:00:10';
    SET @i += 1;
END

-- Step 3: Query the captures after the fact.
SELECT * FROM dbo.WhoIsActiveCapture ORDER BY collection_time DESC;
```

> Note: The `@destination_table` parameter requires that the table was created with a matching schema from `@return_schema`. If you change the parameters between the schema creation and the loop, the INSERT will fail. Keep them consistent.

#### How to interpret the output

| Column | What it tells you |
|---|---|
| `session_id` | SPID. You can KILL this — but see Section 4.2 before doing so. |
| `blocking_session_id` | Non-zero = this session is blocked by that SPID. |
| `wait_info` | Current wait type and duration. The most important column for root cause. |
| `sql_text` | The query being executed. Look for table scans, large sorts. |
| `query_plan` | XML plan. Click in SSMS to visualize. Check for warning triangles. |
| `tran_log_writes` | High = large transaction. Watch for log growth. |
| `memory_grant` | High = query reserved significant memory. |
| `tempdb_allocations` | Non-zero = session is using tempdb (sorts, spills, temp tables). |
| `CPU` | Cumulative CPU (ms) for this request. |
| `reads` | Logical reads. High reads = likely full scan or missing index. |
| `duration` | How long this request has been running. |

#### Red flags
- `blocking_session_id` > 0 on multiple sessions and growing every capture
- `wait_info` showing `LCK_M_X`, `PAGEIOLATCH_SH`, `RESOURCE_SEMAPHORE`, `THREADPOOL`
- One session with enormous `reads` or `CPU` relative to others (runaway query)
- `tran_log_writes` growing across multiple captures (long open transaction)
- No active requests at all but users are complaining — look at `@show_sleeping_spids = 1` for sleeping sessions with open transactions

#### Common mistakes
- Running `sp_WhoIsActive` once and treating it as representative — capture in a loop
- Ignoring sleeping sessions (`@show_sleeping_spids = 1` reveals open transactions)
- Missing the `@get_task_info = 2` parameter that shows actual wait details per task

---

### 4.2 Find the Head Blocker

**Permissions required:** `VIEW SERVER STATE`

#### When to use it
When `sp_WhoIsActive` shows multiple sessions with a non-zero `blocking_session_id`.

#### What question it answers
> *Which session is at the top of the blocking chain, and is it safe to do anything about it?*

#### Terminology
- **Head blocker:** The session not waiting on anyone else, but holding locks that block others.
- **Victim session:** Any session blocked directly or transitively by the head blocker.
- **Blocking chain:** A → blocks B → blocks C. Killing only A resolves the entire chain.

#### Script: Find all blocking chains and the head blocker

```sql
-- Read-only. Safe to run at any time.
WITH BlockingChain AS (
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time / 1000.0            AS wait_seconds,
        r.status,
        DB_NAME(r.database_id)          AS database_name,
        SUBSTRING(
            st.text,
            (r.statement_start_offset / 2) + 1,
            (CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE r.statement_end_offset
             END - r.statement_start_offset) / 2 + 1
        )                               AS current_statement,
        s.host_name,
        s.program_name,
        s.login_name,
        s.last_request_start_time,
        s.open_transaction_count
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions  s  ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
    WHERE r.blocking_session_id > 0
),
HeadBlockers AS (
    -- Head blocker: referenced as a blocker but has no row in BlockingChain as a victim
    SELECT DISTINCT blocking_session_id AS head_blocker_session_id
    FROM BlockingChain bc
    WHERE NOT EXISTS (
        SELECT 1 FROM BlockingChain bc2
        WHERE bc2.session_id = bc.blocking_session_id
    )
)
SELECT
    hb.head_blocker_session_id,
    bc.session_id                AS blocked_session_id,
    bc.wait_type,
    bc.wait_seconds,
    bc.database_name,
    bc.host_name,
    bc.program_name,
    bc.login_name,
    bc.current_statement,
    bc.open_transaction_count
FROM HeadBlockers hb
JOIN BlockingChain bc ON bc.blocking_session_id = hb.head_blocker_session_id
ORDER BY bc.wait_seconds DESC;
```

#### Script: Get the head blocker's details (it may be sleeping)

The head blocker often has NO active request — it is sleeping with an open uncommitted transaction. That is why it does not appear in `BlockingChain` itself.

```sql
-- Replace @HeadBlockerSPID with the session_id from the query above.
DECLARE @HeadBlockerSPID INT = <replace_with_spid>;

SELECT
    s.session_id,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    s.last_request_start_time,
    s.last_request_end_time,
    s.open_transaction_count,
    r.wait_type,
    r.wait_time / 1000.0    AS wait_seconds,
    r.cpu_time,
    r.reads,
    r.writes,
    r.status                AS request_status,
    SUBSTRING(st.text,
        (r.statement_start_offset / 2) + 1,
        (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1
    ) AS last_or_current_statement
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r    ON s.session_id = r.session_id
OUTER APPLY (
    SELECT text FROM sys.dm_exec_sql_text(r.sql_handle)
) st
WHERE s.session_id = @HeadBlockerSPID;
```

#### Interpreting the head blocker

| Head blocker state | Meaning | Action |
|---|---|---|
| `status = sleeping`, `open_transaction_count > 0`, no active request | Application left a transaction open — network disconnect, application bug, forgotten BEGIN TRAN | Investigate application; KILL is often appropriate after verifying rollback will be fast |
| `status = running`, actively executing a long query | Blocking will resolve when the query finishes | Evaluate whether wait is acceptable; check if the query can be optimized |
| `status = sleeping`, `open_transaction_count = 0` | The lock may have already released; re-run the blocking chain script | Wait and re-check |
| Head blocker is a system session (spid < 50) | Internal SQL Server process; do not kill | Investigate what the system process is doing (often AG operations, log writer) |

#### Should you KILL the session?

> ⚠️ **KILL is a last resort. Before issuing it, know:**
>
> - How large is the transaction? Check `tran_log_writes` in `sp_WhoIsActive` or `dm_tran_database_transactions.database_transaction_log_bytes_used`. A multi-gigabyte transaction can take **longer to roll back than it took to run**.
> - Will killing cause data inconsistency at the application level (e.g., a payment was half-committed)?
> - Will the application immediately reconnect and start the same transaction again?

```sql
-- DANGEROUS: Only run after the evaluation above.
KILL <session_id>;
```

#### Monitor rollback progress after KILL

After issuing KILL, the session status changes to `KILLED/ROLLBACK`. Do not assume it completes instantly.

```sql
-- Check rollback progress. Re-run every 30 seconds.
SELECT
    session_id,
    command,
    status,
    percent_complete,
    estimated_completion_time / 1000 / 60  AS estimated_minutes_remaining,
    cpu_time,
    reads,
    writes
FROM sys.dm_exec_requests
WHERE command = 'KILLED/ROLLBACK';
```

If `estimated_minutes_remaining` is large (30+ minutes), inform stakeholders that the rollback is in progress. Do not kill the session again — a second KILL on an already-killed session in rollback has no effect and can cause confusion.

#### References
- [sys.dm_exec_requests — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql)
- [Understand and resolve blocking — Microsoft Docs](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/understand-resolve-blocking)

---

### 4.3 Check Current Waits

**Permissions required:** `VIEW SERVER STATE`

#### When to use it
After `sp_WhoIsActive` — to understand *why* sessions are waiting, not just *that* they are waiting.

#### What question it answers
> *What are sessions waiting for right now, and what does the pattern point to?*

#### Script 1: Active waits per session right now

```sql
SELECT
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    wt.blocking_session_id,
    wt.resource_description,
    r.status,
    r.cpu_time,
    r.reads,
    DB_NAME(r.database_id) AS database_name,
    SUBSTRING(st.text,
        (r.statement_start_offset / 2) + 1,
        (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1
    ) AS current_statement
FROM sys.dm_os_waiting_tasks wt
JOIN sys.dm_exec_requests r  ON wt.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE wt.session_id > 50
ORDER BY wt.wait_duration_ms DESC;
```

#### Script 2: Cumulative waits since the plan last cached — take a delta, do not clear

The `sys.dm_os_wait_stats` values accumulate since the last restart **or** the last time the stats were cleared. On a server that has been running for months, the cumulative view is useful for long-term trending, not for a current incident. Use a delta snapshot instead.

```sql
-- Step 1: Capture baseline
SELECT wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms, signal_wait_time_ms
INTO #wait_snap1
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','SLEEP_SYSTEMTASK','SLEEP_DBSTARTUP','SLEEP_DBREC',
    'SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED',
    'SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT','DISPATCHER_QUEUE_SEMAPHORE',
    'BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT','CLR_MANUAL_EVENT',
    'DBMIRROR_EVENTS_QUEUE','SQLTRACE_BUFFER_FLUSH','WAITFOR',
    'XE_DISPATCHER_WAIT','XE_TIMER_EVENT','BROKER_EVENTHANDLER',
    'CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE',
    'SERVER_IDLE_CHECK','SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
    'HADR_WORK_QUEUE','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    'FT_IFTS_SCHEDULER_IDLE_WAIT','DIRTY_PAGE_POLL',
    'HADR_TIMER_TASK','XIO_IDLE','BROKER_RECEIVE_WAITFOR',
    'ONDEMAND_TASK_QUEUE','DBMIRROR_WORKER_QUEUE'
);

WAITFOR DELAY '00:01:00';   -- Wait 60 seconds

-- Step 2: Compare delta — these are the waits that accumulated in the last 60 seconds
SELECT TOP 20
    s2.wait_type,
    s2.waiting_tasks_count - s1.waiting_tasks_count AS delta_tasks,
    s2.wait_time_ms        - s1.wait_time_ms        AS delta_wait_ms,
    s2.max_wait_time_ms                             AS max_wait_ms,
    CAST(100.0 * (s2.wait_time_ms - s1.wait_time_ms)
        / NULLIF(SUM(s2.wait_time_ms - s1.wait_time_ms) OVER (), 0)
        AS DECIMAL(5,2))                             AS pct_of_delta
FROM sys.dm_os_wait_stats s2
JOIN #wait_snap1 s1 ON s2.wait_type = s1.wait_type
WHERE (s2.wait_time_ms - s1.wait_time_ms) > 0
ORDER BY delta_wait_ms DESC;

DROP TABLE #wait_snap1;
```

> Do not use `DBCC SQLPERF('waitstats', CLEAR)` on a production system. It resets all wait statistics and destroys the historical baseline needed for comparison.

#### Common wait types explained

| Wait Type | Meaning | What to investigate |
|---|---|---|
| `LCK_M_*` | Lock wait (shared, exclusive, update, etc.) | Blocking — see [4.2](#42-find-the-head-blocker) |
| `PAGEIOLATCH_SH` | Waiting to read a page from disk into buffer pool | I/O latency or cold buffer — see [4.6](#46-io-pressure-investigation) |
| `PAGEIOLATCH_EX` | Waiting to latch a page exclusively before writing | I/O latency — see [4.6](#46-io-pressure-investigation) |
| `PAGELATCH_UP` | Non-I/O latch on a buffer page | TempDB allocation contention (GAM/SGAM) — see [4.10](#410-tempdb-emergency-check) |
| `WRITELOG` | Waiting for transaction log flush to disk | Log drive I/O bottleneck — see [4.6](#46-io-pressure-investigation) |
| `CXPACKET` | Parallel query: parent thread waiting for worker threads (SQL 2019+: only the non-trivial waits remain here) | See CXPACKET note below |
| `CXCONSUMER` | Parallel query: consumer thread waiting for data from producer (SQL 2019+, generally benign) | Only investigate if combined with high elapsed time |
| `ASYNC_NETWORK_IO` | SQL is ready but client is not consuming results | Slow client, large result sets, SSRS, row-by-row ETL |
| `RESOURCE_SEMAPHORE` | Query waiting for a memory grant | Memory pressure — see [4.5](#45-memory-pressure-investigation) |
| `THREADPOOL` | No worker thread available — new queries are queueing | **Use DAC to connect.** See THREADPOOL note below. |
| `SOS_SCHEDULER_YIELD` | Thread voluntarily yielded the CPU scheduler | CPU-bound workload, runaway query |
| `LATCH_EX` / `LATCH_SH` | Non-page in-memory latch contention | Could be TempDB allocation, PFS page hotspot |
| `HADR_SYNC_COMMIT` | Primary waiting for synchronous secondary to harden log | Slow secondary disk or network — see [4.9](#49-always-on-ag-health-check) |
| `IO_COMPLETION` | Waiting for an async I/O to complete (not buffer pool) | Backup, restore, DBCC I/O operations |
| `DBMIRROR_SEND` | Database mirroring send queue (legacy feature) | Mirroring partner is behind |

#### CXPACKET — what actually changed in SQL 2019

Before SQL 2019, all parallel query waits were lumped into `CXPACKET`, including harmless inter-thread synchronisation. This made it hard to distinguish real problems.

SQL 2019 split them:
- **`CXPACKET`** — parent thread waiting for child threads to produce results. This is now the *actionable* signal. High `CXPACKET` on SQL 2019+ is more meaningful than it was before.
- **`CXCONSUMER`** — consumer thread waiting for its producer. Generally benign, expected in parallel queries.

**On SQL 2019+: CXPACKET alone does not prove a problem, but it is now a stronger signal than it was on SQL 2016/2017.** Investigate when combined with long elapsed time or many blocked parallel workers.

#### THREADPOOL — what to do

`THREADPOOL` means SQL Server has no worker threads to assign to new requests. New queries queue and time out. This is an emergency.

Steps:
1. **Connect via DAC immediately** — normal connections may not get a thread.
2. Find what is holding threads:
```sql
-- How many threads are in use vs. available?
SELECT
    scheduler_id,
    current_tasks_count,
    runnable_tasks_count,
    current_workers_count,
    active_workers_count,
    work_queue_count,           -- Non-zero = requests waiting for a thread
    pending_disk_io_count
FROM sys.dm_os_schedulers
WHERE scheduler_id < 255        -- Exclude hidden schedulers
ORDER BY work_queue_count DESC;
```
3. Find long-running or hung sessions consuming threads:
```sql
SELECT TOP 30
    session_id, status, wait_type, wait_time / 1000 AS wait_seconds,
    cpu_time, reads, DB_NAME(database_id) AS db_name,
    blocking_session_id
FROM sys.dm_exec_requests
WHERE session_id > 50
ORDER BY wait_time DESC;
```
4. Consider killing the longest-running, highest-impact sessions after identifying them.
5. If THREADPOOL persists: check `max worker threads` in `sys.configurations`. The default (0 = auto-calculated) is usually correct. Do not change it during an incident without understanding the current thread count.

#### References
- [sys.dm_os_wait_stats — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-wait-stats-transact-sql)
- [sys.dm_os_waiting_tasks — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-waiting-tasks-transact-sql)
- [Waits and Queues troubleshooting — Microsoft Docs](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/waits-and-queues)

---

### 4.4 High CPU Investigation

**Permissions required:** `VIEW SERVER STATE`

#### When to use it
CPU is at or near 100%, or sessions show `SOS_SCHEDULER_YIELD` waits in `sp_WhoIsActive`.

#### What question it answers
> *Which query is consuming the CPU, and why — missing index, parallelism, sniffing, or workload volume?*

#### Script 1: Currently running CPU-heavy requests

```sql
SELECT TOP 20
    r.session_id,
    r.status,
    r.cpu_time,
    r.total_elapsed_time / 1000  AS elapsed_seconds,
    r.reads,
    r.logical_reads,
    r.wait_type,
    DB_NAME(r.database_id)       AS database_name,
    s.program_name,
    s.host_name,
    s.login_name,
    SUBSTRING(st.text,
        (r.statement_start_offset / 2) + 1,
        (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1
    ) AS current_statement,
    qp.query_plan
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions  s   ON r.session_id  = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) qp
WHERE r.session_id > 50
ORDER BY r.cpu_time DESC;
```

#### Script 2: Cached plans with highest total CPU

> **Important:** `sys.dm_exec_query_stats` accumulates CPU since the plan was **last compiled and cached** — not since the last SQL Server restart. Plans are evicted under memory pressure and recompiled, resetting their counters. A query that ran once for 10 hours yesterday will not appear here if its plan was evicted. Use `total_worker_time / execution_count` (average CPU per execution) alongside `total_worker_time` (total) to avoid misreading the data.

```sql
SELECT TOP 20
    qs.total_worker_time / 1000                          AS total_cpu_ms,
    qs.execution_count,
    qs.total_worker_time / qs.execution_count / 1000.0  AS avg_cpu_ms,
    qs.total_logical_reads,
    qs.total_logical_reads / qs.execution_count          AS avg_logical_reads,
    qs.creation_time                                     AS plan_cache_entry_created,
    DB_NAME(qp.dbid)                                     AS database_name,
    SUBSTRING(st.text,
        (qs.statement_start_offset / 2) + 1,
        (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2 + 1
    )                                                    AS statement_text,
    qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY qs.total_worker_time DESC;
```

#### Script 3: Query Store — top CPU consumers in the last 2 hours

Use this when `dm_exec_query_stats` does not show the culprit (plan was evicted) or when you need trend data.

```sql
-- Run in the context of the target database. Query Store must be enabled.
SELECT TOP 20
    qsq.query_id,
    OBJECT_NAME(qsq.object_id)                           AS object_name,
    qsrs.count_executions,
    CAST(qsrs.avg_cpu_time / 1000.0 AS DECIMAL(18,2))   AS avg_cpu_ms,
    CAST(qsrs.avg_duration   / 1000.0 AS DECIMAL(18,2)) AS avg_duration_ms,
    qsrs.avg_logical_io_reads,
    qst.query_sql_text,
    qsp.plan_id
FROM sys.query_store_query          qsq
JOIN sys.query_store_query_text     qst  ON qsq.query_text_id = qst.query_text_id
JOIN sys.query_store_plan           qsp  ON qsq.query_id      = qsp.query_id
JOIN sys.query_store_runtime_stats  qsrs ON qsp.plan_id       = qsrs.plan_id
JOIN sys.query_store_runtime_stats_interval qsrsi
     ON qsrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
-- Query Store stores times in UTC. Always use GETUTCDATE() here.
WHERE qsrsi.start_time >= DATEADD(HOUR, -2, GETUTCDATE())
ORDER BY qsrs.avg_cpu_time DESC;
```

#### Identifying the cause of high CPU

| Observation | Likely cause | Next step |
|---|---|---|
| One query with huge `cpu_time` and very high `logical_reads` | Missing index — full scan | Look at the execution plan; find table scan operators |
| Many short similar queries all using moderate CPU | Workload volume / connection pool | Look at application-level connection counts; connection storm |
| High `avg_cpu_ms` but low `avg_logical_reads` | Excessive parallelism | Check MAXDOP, look at CXPACKET in wait stats, review query plan |
| CPU was fine yesterday, now high with the same query | Parameter sniffing or plan regression | Go to Query Store (Section 4.7) — check if plan changed |
| Many single-use ad-hoc queries each causing a CPU spike | Compile storms, no plan reuse | Check `sys.dm_exec_cached_plans` for single-use plan bloat |

#### Confirm parameter sniffing — then go to Query Store

```sql
-- Identify stored procedures with multiple plans in cache.
-- Multiple cached plans for one procedure = likely parameter sniffing.
-- Once confirmed, go to Section 4.7 to force the good plan.
SELECT
    OBJECT_NAME(st.objectid)    AS procedure_name,
    COUNT(*)                    AS cached_plan_count,
    SUM(cp.usecounts)           AS total_executions
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE cp.objtype = 'Proc'
  AND st.objectid IS NOT NULL
GROUP BY st.objectid
HAVING COUNT(*) > 1
ORDER BY cached_plan_count DESC;
```

If sniffing is confirmed, the crisis mitigation path is:
1. Go to Query Store (Section 4.7) to identify the regressed plan
2. Force the previously good plan via Query Store
3. Do NOT flush the entire plan cache with `DBCC FREEPROCCACHE` — that penalises every query on the instance

#### References
- [sys.dm_exec_query_stats — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-stats-transact-sql)
- [Diagnose and resolve high CPU — Microsoft Docs](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/high-cpu-usage-in-sql-server)

---

### 4.5 Memory Pressure Investigation

**Permissions required:** `VIEW SERVER STATE`

#### When to use it
When `sp_WhoIsActive` shows `RESOURCE_SEMAPHORE` waits, when queries are running slower without a CPU or I/O explanation, or when memory alerts fire.

#### What question it answers
> *Is SQL Server experiencing memory pressure? Where is the memory going, and what is the actionable fix right now?*

#### Crisis-first approach to memory pressure

During an incident, the investigation has two phases:

**Phase A — Is there real memory pressure right now?**
```sql
-- 1. Is SQL Server returning pages to the OS (signs of OS-level pressure)?
SELECT
    physical_memory_in_use_kb / 1024         AS sql_mem_used_mb,
    memory_utilization_percentage,
    page_fault_count
FROM sys.dm_os_process_memory;

-- 2. Is the OS itself under memory pressure?
SELECT
    physical_memory_kb / 1024              AS total_physical_mb,
    available_physical_memory_kb / 1024    AS available_physical_mb,
    system_memory_state_desc               -- 'Available physical memory is high' = healthy
FROM sys.dm_os_sys_memory;

-- 3. Are queries currently waiting for a memory grant?
SELECT
    resource_semaphore_id,
    target_memory_kb   / 1024  AS target_mb,
    available_memory_kb / 1024 AS available_mb,
    granted_memory_kb   / 1024 AS granted_mb,
    grantee_count,
    waiter_count,               -- Non-zero = queries queuing for memory RIGHT NOW
    timeout_error_count
FROM sys.dm_exec_query_resource_semaphores;
```

If `waiter_count > 0` in the resource semaphores: real, active memory pressure. Proceed to Phase B.

If `waiter_count = 0` and `system_memory_state_desc` is healthy: memory may not be the root cause. Re-check other categories.

**Phase B — Find what is consuming the grant and decide what to do**

```sql
-- Which queries are waiting for a memory grant right now?
SELECT
    r.session_id,
    mg.requested_memory_kb / 1024    AS requested_mb,
    mg.granted_memory_kb   / 1024    AS granted_mb,
    mg.required_memory_kb  / 1024    AS required_mb,
    mg.wait_time_ms,
    mg.queue_id,
    SUBSTRING(st.text, 1, 300)       AS query_snippet
FROM sys.dm_exec_query_memory_grants mg
JOIN sys.dm_exec_requests r ON mg.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE mg.grant_time IS NULL    -- NULL = still waiting; populated = already granted
ORDER BY mg.requested_memory_kb DESC;

-- Which queries have already received very large grants?
SELECT
    r.session_id,
    mg.granted_memory_kb / 1024     AS granted_mb,
    mg.used_memory_kb    / 1024     AS used_mb,
    mg.grant_time,
    SUBSTRING(st.text, 1, 300)      AS query_snippet
FROM sys.dm_exec_query_memory_grants mg
JOIN sys.dm_exec_requests r ON mg.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE mg.grant_time IS NOT NULL
ORDER BY mg.granted_memory_kb DESC;
```

Actionable decisions from these results:

| Finding | Action |
|---|---|
| One query has a massive grant (e.g., 50GB) | Check its plan: large hash join, sort on a huge table. Consider killing it or waiting for it to finish. Investigate the query — missing index is a common cause. |
| Many queries waiting with moderate grants | Total demand exceeds `max server memory`. Check if `max server memory` is set too low. Also check if a batch job is competing with OLTP workload. |
| `available_physical_mb` very low, `system_memory_state_desc = 'Low Memory'` | OS is stealing pages from SQL Server. Check for other memory-hungry processes (ETL tools, reporting services, SSIS). |

#### Page Life Expectancy — use only as a trend indicator

```sql
SELECT
    object_name,
    counter_name,
    cntr_value AS page_life_expectancy_seconds
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
  AND object_name LIKE '%Buffer Manager%';
```

> **PLE warning:** There is no universal "healthy" threshold for PLE. A server with 4 GB of RAM and a 300-second PLE is healthy. A server with 256 GB of RAM and a 300-second PLE may be in serious trouble. What matters is the **trend**: if PLE drops suddenly by 50% or more over minutes, that is a signal. An absolute PLE value in isolation tells you nothing without a baseline for that server.

#### Memory clerks — useful for post-mortem, not crisis triage

```sql
-- Who is consuming SQL Server memory? (useful for post-mortem analysis)
SELECT TOP 15
    type                   AS clerk_type,
    SUM(pages_kb) / 1024   AS used_mb
FROM sys.dm_os_memory_clerks
GROUP BY type
ORDER BY SUM(pages_kb) DESC;
```

Notable clerks:
- `MEMORYCLERK_SQLBUFFERPOOL` — buffer pool. Should be the largest. Expected.
- `MEMORYCLERK_SQLQERESERVATIONS` — memory grants for query execution. If very large, you have heavy sort/hash join workload.
- `CACHESTORE_SQLCP` + `CACHESTORE_OBJCP` — plan caches. If enormous, look for single-use plan bloat.

#### References
- [sys.dm_exec_query_memory_grants — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-memory-grants-transact-sql)
- [Memory management architecture guide — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/memory-management-architecture-guide)

---

### 4.6 I/O Pressure Investigation

**Permissions required:** `VIEW SERVER STATE`

#### When to use it
When `PAGEIOLATCH_*` or `WRITELOG` waits appear at the top of the wait list, when disk alerts fire, or when queries are taking minutes instead of seconds without a blocking or CPU explanation.

#### What question it answers
> *Which database files have high latency, and is the problem data reads, log writes, or tempdb?*

#### Script 1: File-level latency (cumulative since last restart)

```sql
SELECT
    DB_NAME(fs.database_id)                     AS database_name,
    mf.physical_name,
    mf.type_desc                                AS file_type,
    fs.num_of_reads,
    fs.io_stall_read_ms,
    CASE WHEN fs.num_of_reads = 0 THEN 0
         ELSE fs.io_stall_read_ms / fs.num_of_reads
    END                                         AS avg_read_latency_ms,
    fs.num_of_writes,
    fs.io_stall_write_ms,
    CASE WHEN fs.num_of_writes = 0 THEN 0
         ELSE fs.io_stall_write_ms / fs.num_of_writes
    END                                         AS avg_write_latency_ms,
    fs.io_stall,
    fs.size_on_disk_bytes / 1048576             AS size_mb
FROM sys.dm_io_virtual_file_stats(NULL, NULL) fs
JOIN sys.master_files mf
    ON fs.database_id = mf.database_id
    AND fs.file_id    = mf.file_id
ORDER BY (fs.io_stall_read_ms + fs.io_stall_write_ms) DESC;
```

Cumulative values can be dominated by a past event (backup that ran 6 hours ago). Use the delta snapshot below for current-state accuracy.

#### Script 2: Delta-based latency (what is happening right now)

```sql
-- Take a 60-second snapshot to see current I/O behaviour.
SELECT
    DB_NAME(fs.database_id) AS database_name,
    mf.physical_name,
    mf.type_desc,
    fs.io_stall_read_ms     AS r1_read_ms,
    fs.num_of_reads         AS r1_reads,
    fs.io_stall_write_ms    AS r1_write_ms,
    fs.num_of_writes        AS r1_writes
INTO #io_snap1
FROM sys.dm_io_virtual_file_stats(NULL, NULL) fs
JOIN sys.master_files mf ON fs.database_id = mf.database_id AND fs.file_id = mf.file_id;

WAITFOR DELAY '00:01:00';

SELECT
    s1.database_name,
    s1.physical_name,
    s1.type_desc,
    (fs.num_of_reads        - s1.r1_reads)      AS delta_reads,
    (fs.io_stall_read_ms    - s1.r1_read_ms)    AS delta_read_stall_ms,
    CASE WHEN (fs.num_of_reads - s1.r1_reads) = 0 THEN 0
         ELSE (fs.io_stall_read_ms - s1.r1_read_ms) / (fs.num_of_reads - s1.r1_reads)
    END                                          AS current_avg_read_latency_ms,
    (fs.num_of_writes       - s1.r1_writes)     AS delta_writes,
    (fs.io_stall_write_ms   - s1.r1_write_ms)   AS delta_write_stall_ms,
    CASE WHEN (fs.num_of_writes - s1.r1_writes) = 0 THEN 0
         ELSE (fs.io_stall_write_ms - s1.r1_write_ms) / (fs.num_of_writes - s1.r1_writes)
    END                                          AS current_avg_write_latency_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) fs
JOIN sys.master_files mf ON fs.database_id = mf.database_id AND fs.file_id = mf.file_id
JOIN #io_snap1 s1 ON s1.physical_name = mf.physical_name
WHERE (fs.num_of_reads + fs.num_of_writes - s1.r1_reads - s1.r1_writes) > 0
ORDER BY (delta_read_stall_ms + delta_write_stall_ms) DESC;

DROP TABLE #io_snap1;
```

#### Latency thresholds

These are general guidelines based on common SAN and NVMe benchmarks. Your baseline is the most reliable reference.

| File type | Acceptable | Investigate | Critical |
|---|---|---|---|
| Data file reads | < 5 ms | 5–20 ms | > 20 ms |
| Log file writes | < 2 ms | 2–10 ms | > 10 ms |
| TempDB files | < 5 ms | 5–15 ms | > 15 ms |

NVMe-backed storage commonly achieves sub-millisecond latency. If you have NVMe and see 3ms, investigate. If you have a SAN from 2015, 8ms may be your normal.

#### Separating the type of I/O problem

| Pattern | Interpretation |
|---|---|
| High data file read latency only | Buffer pool cache misses, cold cache, or large scans pulling pages from disk |
| High log file write latency only | Log drive I/O bottleneck; log on a shared or slow disk |
| High tempdb read and write latency | Spills, version store, or temp table intensive workload — see [4.10](#410-tempdb-emergency-check) |
| High latency across all files simultaneously | Storage subsystem issue (SAN, RAID controller, network storage) |
| Latency normal but PAGEIOLATCH waits high | Check if a cold buffer pool (post-restart) is the cause; it is transient |

#### Sessions waiting on WRITELOG right now

```sql
SELECT
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    DB_NAME(r.database_id) AS database_name,
    SUBSTRING(st.text, 1, 300) AS query_snippet
FROM sys.dm_os_waiting_tasks wt
JOIN sys.dm_exec_requests r ON wt.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE wt.wait_type = 'WRITELOG'
ORDER BY wt.wait_duration_ms DESC;
```

Common causes of WRITELOG pressure: log file on a slow or shared disk, autogrowth events on the log file, or synchronous AG commit wait (see `HADR_SYNC_COMMIT`).

#### References
- [sys.dm_io_virtual_file_stats — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql)
- [Troubleshoot SQL Server I/O performance — Microsoft Docs](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/troubleshoot-sql-io-performance)

---

### 4.7 Query Store Emergency Usage

**Permissions required:** `VIEW DATABASE STATE` (or `db_owner`) for read-only Query Store queries. `ALTER DATABASE` to force/unforce plans.

#### When to use it
A query that was fast is now slow. A deployment happened. A plan changed. You need to identify and optionally revert a plan regression in minutes.

#### What question it answers
> *Did a query plan change recently? Which plan was better? Can we force the old plan?*

> **Prerequisite:** Query Store must be enabled on the database. Check: `SELECT name, is_query_store_on FROM sys.databases WHERE name = '<db>';`

#### Script 1: Most expensive queries in the last 2 hours

```sql
-- Run in the context of the target database.
-- Query Store uses UTC internally — always use GETUTCDATE() for time filters.
SELECT TOP 20
    qsq.query_id,
    qst.query_sql_text,
    CAST(qsrs.avg_duration   / 1000.0 AS DECIMAL(18,2))  AS avg_duration_ms,
    CAST(qsrs.avg_cpu_time   / 1000.0 AS DECIMAL(18,2))  AS avg_cpu_ms,
    qsrs.avg_logical_io_reads,
    qsrs.count_executions,
    qsp.plan_id,
    qsrsi.start_time,
    qsrsi.end_time
FROM sys.query_store_query          qsq
JOIN sys.query_store_query_text     qst   ON qsq.query_text_id = qst.query_text_id
JOIN sys.query_store_plan           qsp   ON qsq.query_id      = qsp.query_id
JOIN sys.query_store_runtime_stats  qsrs  ON qsp.plan_id       = qsrs.plan_id
JOIN sys.query_store_runtime_stats_interval qsrsi
     ON qsrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
WHERE qsrsi.start_time >= DATEADD(HOUR, -2, GETUTCDATE())
ORDER BY qsrs.avg_duration DESC;
```

#### Script 2: Queries with multiple plans (plan regression indicator)

```sql
SELECT
    qsq.query_id,
    qst.query_sql_text,
    COUNT(DISTINCT qsp.plan_id)             AS plan_count,
    MIN(qsp.last_compile_start_time)        AS first_plan_compiled,
    MAX(qsp.last_compile_start_time)        AS latest_plan_compiled
FROM sys.query_store_query      qsq
JOIN sys.query_store_query_text qst ON qsq.query_text_id = qst.query_text_id
JOIN sys.query_store_plan       qsp ON qsq.query_id      = qsp.query_id
GROUP BY qsq.query_id, qst.query_sql_text
HAVING COUNT(DISTINCT qsp.plan_id) > 1
ORDER BY plan_count DESC;
```

#### Script 3: Retrieve the plans for a specific query to compare

```sql
-- Replace <your_query_id> with the query_id from the scripts above.
SELECT
    qsp.plan_id,
    qsp.last_compile_start_time,
    qsrs.count_executions,
    CAST(qsrs.avg_duration / 1000.0 AS DECIMAL(18,2))  AS avg_duration_ms,
    CAST(qsrs.avg_cpu_time / 1000.0 AS DECIMAL(18,2))  AS avg_cpu_ms,
    qsp.is_forced_plan,
    CAST(qsp.query_plan AS XML) AS query_plan_xml
FROM sys.query_store_plan           qsp
JOIN sys.query_store_runtime_stats  qsrs ON qsp.plan_id = qsrs.plan_id
WHERE qsp.query_id = <your_query_id>
ORDER BY qsrs.avg_duration ASC;  -- Fastest plan first
```

Click the XML in SSMS to view the graphical plan. Compare the good and bad plans side by side.

#### Script 4: Check currently forced plans and their health

```sql
SELECT
    qsq.query_id,
    qst.query_sql_text,
    qsp.plan_id,
    qsp.is_forced_plan,
    qsp.force_failure_count,
    qsp.last_force_failure_reason_desc   -- Non-null means the forced plan failed
FROM sys.query_store_plan       qsp
JOIN sys.query_store_query      qsq ON qsp.query_id      = qsq.query_id
JOIN sys.query_store_query_text qst ON qsq.query_text_id = qst.query_text_id
WHERE qsp.is_forced_plan = 1;
```

Monitor `force_failure_count` and `last_force_failure_reason_desc` after forcing. If the forced plan fails (e.g., because its index was dropped), SQL Server falls back to the optimizer — but this can cause silent performance degradation.

#### Forcing a plan

> ⚠️ **PLAN FORCING — READ BEFORE RUNNING:**
>
> Only force a plan when you have confirmed through `avg_duration_ms` and `avg_cpu_ms` comparison that a specific older plan was consistently better.
>
> Plan forcing is a **temporary mitigation**. It does not fix the root cause (stale statistics, parameter sniffing, schema change, missing index). Schedule a follow-up within 24–48 hours to resolve the underlying issue and unforce the plan.
>
> A forced plan that references a dropped index will cause query failures.

```sql
-- REQUIRES: ALTER DATABASE permission or db_owner.
-- Document the query_id, plan_id, reason, and timestamp before running.
EXEC sys.sp_query_store_force_plan
    @query_id = <query_id>,
    @plan_id  = <good_plan_id>;

-- To unforce:
EXEC sys.sp_query_store_unforce_plan
    @query_id = <query_id>,
    @plan_id  = <plan_id>;
```

#### References
- [Query Store overview — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Query Store best practices — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/performance/best-practice-with-the-query-store)

---

### 4.8 SQL Agent Jobs

**Permissions required:** `SQLAgentReaderRole` in msdb, `SQLAgentOperatorRole`, or `sysadmin`

#### When to use it
When performance degradation started at a specific time and no query-level cause is obvious. Maintenance jobs, ETL, backups, and index rebuilds can silently destroy production performance.

#### What question it answers
> *Is a SQL Agent job running right now, or did one start around the time the incident began?*

#### Script 1: Currently running jobs

```sql
SELECT
    j.name                               AS job_name,
    ja.start_execution_date,
    DATEDIFF(MINUTE, ja.start_execution_date, GETDATE()) AS running_minutes,
    ja.last_executed_step_id,
    ja.last_executed_step_date,
    j.enabled
FROM msdb.dbo.sysjobactivity ja
JOIN msdb.dbo.sysjobs        j  ON ja.job_id = j.job_id
WHERE ja.session_id = (
    SELECT MAX(session_id) FROM msdb.dbo.syssessions
)
AND ja.start_execution_date IS NOT NULL
AND ja.stop_execution_date  IS NULL
ORDER BY ja.start_execution_date;
```

#### Script 2: Recently failed jobs (last 24 hours)

```sql
SELECT
    j.name                       AS job_name,
    jh.step_name,
    msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS run_time,
    jh.run_duration,
    CASE jh.run_status
        WHEN 0 THEN 'FAILED'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'In Progress'
    END                          AS run_status,
    jh.message
FROM msdb.dbo.sysjobhistory jh
JOIN msdb.dbo.sysjobs       j  ON jh.job_id = j.job_id
WHERE jh.run_status = 0
  AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time)
      >= DATEADD(HOUR, -24, GETDATE())
ORDER BY msdb.dbo.agent_datetime(jh.run_date, jh.run_time) DESC;
```

#### Script 3: Jobs that started around the incident time

```sql
DECLARE @IncidentTime DATETIME = '2024-01-15 14:30:00'; -- Replace with actual incident time

SELECT
    j.name                       AS job_name,
    msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS start_time,
    jh.run_duration,
    CASE jh.run_status
        WHEN 0 THEN 'FAILED'  WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'   WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'In Progress'
    END AS run_status,
    jh.step_name,
    jh.message
FROM msdb.dbo.sysjobhistory jh
JOIN msdb.dbo.sysjobs       j  ON jh.job_id = j.job_id
WHERE msdb.dbo.agent_datetime(jh.run_date, jh.run_time)
      BETWEEN DATEADD(MINUTE, -30, @IncidentTime)
          AND DATEADD(MINUTE,  60, @IncidentTime)
ORDER BY start_time DESC;
```

#### High-impact job types

| Job type | Production impact |
|---|---|
| Index rebuild OFFLINE | Takes table-level lock — blocks ALL reads and writes on that table |
| Index rebuild ONLINE | Long-running; holds schema stability lock; CPU and I/O intensive |
| Full backup | Heavy sequential I/O; can saturate the disk and cause PAGEIOLATCH waits |
| Statistics update (full scan) | Causes plan recompilations; brief lock on statistics object |
| ETL / SSIS package | May open long transactions causing log growth and blocking |
| DBCC CHECKDB | Very I/O intensive; can run for hours and degrade read performance |
| Transaction log backup | Usually lightweight, but frequent log backups on a busy system add up |

---

### 4.9 Always On AG Health Check

**Permissions required:** `VIEW SERVER STATE`

#### When to use it
When an AG alert fires, a failover occurs, read-only connections start failing, or you see `HADR_SYNC_COMMIT` high in wait stats.

#### What question it answers
> *Is the AG synchronized? Are replicas healthy? What is the failover risk if we act right now?*

#### Script 1: AG overall health

```sql
SELECT
    ag.name                              AS ag_name,
    ags.primary_replica,
    ags.primary_recovery_health_desc,
    ags.synchronization_health_desc,
    ags.connected_state_desc
FROM sys.availability_groups                ag
JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id;
```

#### Script 2: Replica health

```sql
SELECT
    ag.name                               AS ag_name,
    ar.replica_server_name,
    ar.availability_mode_desc,            -- SYNCHRONOUS_COMMIT or ASYNCHRONOUS_COMMIT
    ar.failover_mode_desc,
    ars.role_desc,                        -- PRIMARY or SECONDARY
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    ars.operational_state_desc,
    ars.recovery_health_desc,
    ars.last_connect_error_description    -- Populated when a replica disconnects
FROM sys.availability_groups                  ag
JOIN sys.availability_replicas                ar  ON ag.group_id  = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars  ON ar.replica_id = ars.replica_id;
```

#### Script 3: Database-level synchronization and queue sizes

```sql
SELECT
    DB_NAME(drs.database_id)            AS database_name,
    ag.name                             AS ag_name,
    ar.replica_server_name,
    drs.is_primary_replica,
    drs.synchronization_state_desc,     -- SYNCHRONIZED, SYNCHRONIZING, NOT SYNCHRONIZING
    drs.synchronization_health_desc,
    drs.database_state_desc,            -- Look for: RECOVERING, SUSPECT, SUSPENDED
    drs.is_suspended,
    drs.suspend_reason_desc,
    drs.log_send_queue_size,            -- KB waiting to be sent to secondary
    drs.log_send_rate,                  -- KB/s
    drs.redo_queue_size,                -- KB waiting to be applied on secondary
    drs.redo_rate,                      -- KB/s
    CASE WHEN drs.redo_rate > 0
         THEN CAST(drs.redo_queue_size / drs.redo_rate AS DECIMAL(10,1))
         ELSE NULL
    END                                 AS estimated_seconds_behind,
    drs.last_sent_time,
    drs.last_received_time,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.last_commit_time
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas           ar  ON drs.replica_id = ar.replica_id
JOIN sys.availability_groups             ag  ON ar.group_id    = ag.group_id
ORDER BY ag.name, ar.replica_server_name;
```

#### Interpreting the results

| Field | Red flag value | What it means |
|---|---|---|
| `synchronization_state_desc` | `NOT SYNCHRONIZING` | Replica stopped applying log. Data loss risk exists. |
| `synchronization_health_desc` | `NOT_HEALTHY` | AG is degraded. |
| `connected_state_desc` | `DISCONNECTED` | Network or service issue between replicas. |
| `is_suspended` | `1` | Data movement suspended. Manual `RESUME DATABASE` required. |
| `redo_queue_size` | Growing continuously | Secondary is falling behind. Failover now = data loss. |
| `log_send_queue_size` | Hundreds of MB or growing | Network bottleneck or secondary is down. |
| `database_state_desc` | `RECOVERING`, `SUSPECT` | Database is not usable. Immediate investigation required. |

#### HADR_SYNC_COMMIT — what this wait means

When the primary is configured for `SYNCHRONOUS_COMMIT`, every transaction must wait for the secondary to harden (write to its log) before the commit returns to the client. `HADR_SYNC_COMMIT` is that wait.

High `HADR_SYNC_COMMIT` waits mean one of:
- The network between primary and secondary is slow or saturated
- The secondary's disk (log drive) is slow
- The secondary is under CPU or I/O pressure and cannot keep up with the primary's log rate

Diagnosis:
1. Check `log_send_queue_size` and `redo_queue_size` in the script above — a growing send queue = network problem; a growing redo queue with healthy send queue = secondary I/O problem
2. Check network latency between the replicas
3. Check I/O latency on the secondary's log drive using Section 4.6 scripts, run on the secondary

#### Pre-failover checklist

> ⚠️ **DO NOT FAIL OVER without verifying all of the following:**
>
> 1. Target replica `synchronization_state_desc = SYNCHRONIZED` (for synchronous-commit replicas)
> 2. `redo_queue_size` is zero or within your RPO tolerance
> 3. All application teams have been notified
> 4. Connection strings or AG listener behaviour after failover is understood
> 5. A rollback plan exists if the failover makes things worse

#### References
- [Monitor Availability Groups — Microsoft Docs](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/monitor-availability-groups-transact-sql)
- [sys.dm_hadr_database_replica_states — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-hadr-database-replica-states-transact-sql)
- [Always On AG troubleshooting — Microsoft Docs](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/troubleshoot-always-on-availability-groups-configuration-sql-server)

---

### 4.10 TempDB Emergency Check

**Permissions required:** `VIEW SERVER STATE` for session-level DMVs; `VIEW DATABASE STATE` in tempdb for file space usage

#### When to use it
TempDB space alerts, `Could not allocate space in 'tempdb'` errors, or `PAGELATCH_UP` waits on tempdb pages.

#### What question it answers
> *What is consuming TempDB, and is it about to run out of space?*

#### Script 1: TempDB file space summary

> **Note:** `sys.dm_db_file_space_usage` is database-scoped. You must use three-part naming (`tempdb.sys.dm_db_file_space_usage`) or switch context to tempdb first. `WHERE database_id = 2` does **not** work — it returns zero rows if run from a different database context.

```sql
-- Use three-part naming to ensure we are always querying tempdb regardless of context.
SELECT
    SUM(unallocated_extent_page_count)    * 8 / 1024 AS free_mb,
    SUM(user_object_reserved_page_count)  * 8 / 1024 AS user_objects_mb,
    SUM(internal_object_reserved_page_count) * 8 / 1024 AS internal_objects_mb,
    SUM(version_store_reserved_page_count) * 8 / 1024 AS version_store_mb,
    SUM(mixed_extent_page_count)          * 8 / 1024 AS mixed_extents_mb,
    SUM(unallocated_extent_page_count + user_object_reserved_page_count
        + internal_object_reserved_page_count + version_store_reserved_page_count
        + mixed_extent_page_count) * 8 / 1024        AS total_used_mb
FROM tempdb.sys.dm_db_file_space_usage;
```

#### Script 2: Sessions consuming tempdb

```sql
-- sys.dm_db_session_space_usage always reports tempdb session usage.
-- Safe to run from any database context.
SELECT TOP 20
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    tu.user_objects_alloc_page_count     * 8 / 1024 AS user_objects_mb,
    tu.internal_objects_alloc_page_count * 8 / 1024 AS internal_objects_mb,
    (tu.user_objects_alloc_page_count
     + tu.internal_objects_alloc_page_count) * 8 / 1024 AS total_tempdb_mb,
    SUBSTRING(st.text, 1, 200) AS query_snippet
FROM sys.dm_db_session_space_usage tu
JOIN sys.dm_exec_sessions           s  ON tu.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests      r  ON s.session_id  = r.session_id
OUTER APPLY (SELECT text FROM sys.dm_exec_sql_text(r.sql_handle)) st
WHERE (tu.user_objects_alloc_page_count + tu.internal_objects_alloc_page_count) > 0
ORDER BY total_tempdb_mb DESC;
```

#### Script 3: Version store size and the transaction keeping it alive

A large version store means a long-running transaction in a database with RCSI (Read Committed Snapshot Isolation) enabled. The version store lives in tempdb, but the transaction causing it is in a **user database** — that is where to look.

```sql
-- Current version store size (from the file space query above, version_store_mb)
-- Now find the oldest active transaction keeping the version store alive:
SELECT TOP 10
    DB_NAME(dt.database_id)                          AS database_name,
    at.transaction_id,
    at.transaction_begin_time,
    DATEDIFF(MINUTE, at.transaction_begin_time, GETDATE()) AS age_minutes,
    dt.database_transaction_log_bytes_used / 1024    AS log_kb_used,
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    SUBSTRING(st.text, 1, 300)                       AS current_or_last_sql
FROM sys.dm_tran_active_transactions   at
JOIN sys.dm_tran_database_transactions dt ON at.transaction_id  = dt.transaction_id
JOIN sys.dm_tran_session_transactions  ts ON at.transaction_id  = ts.transaction_id
JOIN sys.dm_exec_sessions              s  ON ts.session_id      = s.session_id
LEFT JOIN sys.dm_exec_requests         r  ON s.session_id       = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
-- User databases only — these are the transactions that populate the version store
WHERE dt.database_id > 4
ORDER BY at.transaction_begin_time ASC;
```

#### Script 4: TempDB file configuration

```sql
-- Check file count, size, and autogrowth settings
SELECT
    name,
    physical_name,
    size * 8 / 1024         AS current_size_mb,
    max_size,
    growth,
    is_percent_growth
FROM tempdb.sys.database_files;
```

#### Common causes and crisis actions

| Cause | Indicator | Immediate action |
|---|---|---|
| Sort/hash join spills | High `internal_objects_mb` per session; look for Warnings in query plan | Improve the query; check for missing indexes; this often resolves after the query finishes |
| RCSI version store bloat | High `version_store_mb` and it is growing | Find and close the old transaction in a user database (Script 3 above) |
| Temp table heavy ETL | High `user_objects_mb` per session | Let it finish or kill the session if it is consuming space dangerously |
| PAGELATCH_UP contention | PAGELATCH_UP waits on page 2:1:1, 2:1:2, 2:1:3 (GAM/SGAM/PFS pages) | Add more equal-sized tempdb data files — up to the number of logical CPU cores, max 8 per best practice |
| TempDB is full and space cannot be recovered | `free_mb = 0`, no long sessions to kill | In extremis: controlled restart of SQL Server is the only recovery (all tempdb space is released). Confirm with business before doing this. |

#### References
- [TempDB configuration — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database)
- [sys.dm_db_file_space_usage — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-file-space-usage-transact-sql)

---

### 4.11 Long Transactions and Log Growth

**Permissions required:** `VIEW SERVER STATE`, `VIEW DATABASE STATE`

#### When to use it
The transaction log file is growing rapidly, disk space alerts are firing, or `log_reuse_wait_desc` shows `ACTIVE_TRANSACTION`.

#### What question it answers
> *Who has an open transaction, how old is it, and is it preventing log truncation?*

#### Script 1: Log file usage and reuse wait reason per database

The correct approach is `DBCC SQLPERF('logspace')`, which works across all databases without the permission and scoping complexities of database-scoped DMVs.

```sql
-- Cross-database log space: works from master, no per-database context switch needed.
CREATE TABLE #logspace (
    DatabaseName  SYSNAME,
    LogSizeMB     FLOAT,
    LogUsedPct    FLOAT,
    Status        INT
);
INSERT INTO #logspace EXEC ('DBCC SQLPERF(''logspace'')');

SELECT
    ls.DatabaseName,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,      -- Why the log cannot be truncated
    CAST(ls.LogSizeMB AS DECIMAL(10,1))   AS log_size_mb,
    CAST(ls.LogUsedPct AS DECIMAL(5,1))   AS log_used_pct,
    CAST(ls.LogSizeMB * ls.LogUsedPct / 100.0 AS DECIMAL(10,1)) AS log_used_mb
FROM #logspace ls
JOIN sys.databases d ON ls.DatabaseName = d.name
WHERE d.database_id > 4         -- Skip system databases; adjust if needed
ORDER BY log_used_pct DESC;

DROP TABLE #logspace;
```

#### log_reuse_wait_desc values explained

| Value | Meaning | Action |
|---|---|---|
| `NOTHING` | Log can be reused at next checkpoint. Healthy. | No action needed. |
| `ACTIVE_TRANSACTION` | An open transaction is preventing truncation. | Find and close the transaction (Script 2 below). |
| `LOG_BACKUP` | Waiting for a log backup to run. | Run a log backup now, or check why the log backup job failed. |
| `CHECKPOINT` | Waiting for a checkpoint. Normal and transient. | Wait; if persistent, investigate checkpoint frequency. |
| `REPLICATION` | Log reader agent is behind. | Check replication status and latency. |
| `AVAILABILITY_REPLICA` | AG secondary is not consuming log fast enough. | Check redo queue — see Section 4.9. |
| `DATABASE_MIRRORING` | Mirroring partner is behind (legacy). | Check mirroring status. |

#### Script 2: Open transactions and their age

```sql
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    at.transaction_id,
    at.name                                           AS transaction_name,
    at.transaction_begin_time,
    DATEDIFF(MINUTE, at.transaction_begin_time, GETDATE()) AS age_minutes,
    at.transaction_type,
    at.transaction_state,
    dt.database_transaction_log_bytes_used / 1024     AS log_kb_used,
    DB_NAME(dt.database_id)                           AS database_name,
    SUBSTRING(st.text, 1, 300)                        AS current_or_last_sql
FROM sys.dm_tran_active_transactions   at
JOIN sys.dm_tran_session_transactions  ts ON at.transaction_id = ts.transaction_id
JOIN sys.dm_exec_sessions              s  ON ts.session_id     = s.session_id
LEFT JOIN sys.dm_tran_database_transactions dt
    ON at.transaction_id = dt.transaction_id
    AND dt.database_id   > 4
LEFT JOIN sys.dm_exec_requests         r  ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
ORDER BY at.transaction_begin_time ASC;
```

#### How a long transaction causes cascading problems

```
Long open transaction (e.g., started 3 hours ago)
        │
        ├─► Log cannot be truncated (ACTIVE_TRANSACTION)
        │         └─► Log file grows → disk space exhaustion
        │
        ├─► Version store in TempDB grows (if RCSI is enabled on the database)
        │         └─► TempDB fills up
        │
        ├─► Rows modified by the transaction remain locked
        │         └─► Other sessions block, then time out
        │
        └─► AG secondary redo queue grows
                  └─► Secondary falls behind → failover risk → HADR_SYNC_COMMIT waits
```

#### References
- [sys.dm_tran_active_transactions — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-tran-active-transactions-transact-sql)
- [Transaction log architecture — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-log-architecture-and-management-guide)

---

### 4.12 Deadlocks

**Permissions required:** `VIEW SERVER STATE`

#### When to use it
Applications report errors like `Transaction (Process ID X) was deadlocked on resources with another process`.

#### What question it answers
> *Which queries are involved in deadlocks, what resource are they competing for, and what is the pattern?*

#### Deadlock vs. blocking — critical difference

| Aspect | Blocking | Deadlock |
|---|---|---|
| Resolution | One session waits indefinitely until the blocker releases its lock | SQL Server detects the cycle and automatically kills the victim (error 1205) |
| Error thrown | No — the client just waits | Error 1205 raised to the victim session |
| Duration | Minutes to hours | Typically detected within 5 seconds |
| Detection tool | sp_WhoIsActive, dm_exec_requests | system_health Extended Events, error log |

#### Script 1: Retrieve recent deadlock graphs from system_health (always running)

```sql
-- The system_health session is enabled by default on SQL Server 2008+.
-- This retrieves deadlock XML from the in-memory ring buffer.
SELECT
    xdr.value('@timestamp', 'datetime2')     AS deadlock_time,
    xdr.query('.')                           AS deadlock_graph_xml
FROM (
    SELECT CAST(target_data AS XML) AS target_data
    FROM sys.dm_xe_session_targets   t
    JOIN sys.dm_xe_sessions          s ON t.event_session_address = s.address
    WHERE s.name       = 'system_health'
      AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS xdt(xdr)
ORDER BY deadlock_time DESC;
```

Click the XML in the `deadlock_graph_xml` column in SSMS — it renders as a visual deadlock graph showing which sessions held and requested which resources.

#### Script 2: Read from system_health XEL files (older events, further back in time)

The ring buffer holds a limited number of events. For deadlocks that occurred hours ago, read the XEL files.

```sql
-- Find the system_health XEL file path first:
SELECT name, value_in_use
FROM sys.configurations
WHERE name = 'ErrorLog';
-- XEL files are in the same folder as the error log.

-- Then read them (replace the path):
SELECT
    xdr.value('@timestamp', 'datetime2')  AS deadlock_time,
    xdr.query('.')                        AS deadlock_xml
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file(
        N'<path_to_system_health_*.xel>',   -- e.g. N'C:\...\MSSQL\Log\system_health*.xel'
        NULL, NULL, NULL
    )
    WHERE object_name = 'xml_deadlock_report'
) AS src
CROSS APPLY src.event_data.nodes('event') AS xdt(xdr)
ORDER BY deadlock_time DESC;
```

#### How to read a deadlock graph

1. Each **ellipse** is a process (session). Hover or click for the query and session details.
2. Each **rectangle** is a resource (key, page, object, row).
3. Arrows show: → requesting a lock, → holding a lock.
4. The **marked victim** received error 1205. The winner kept its locks and completed.
5. Look at the lock types: `KEY` (row), `PAG` (page), `TAB` (table), `RID` (heap row).
6. Look at the access type: are both sessions trying to acquire exclusive locks on the same resource in opposite orders?

#### Common deadlock patterns and root fixes

| Pattern | Root cause | Fix |
|---|---|---|
| Session A updates table 1 then 2; Session B updates table 2 then 1 | Inconsistent access order | Enforce consistent object access order in application code |
| A scan acquires many shared locks, blocking an exclusive lock elsewhere | Missing index causes full table scan, acquiring many locks along the way | Add the missing index to reduce lock footprint |
| Both sessions reading and then updating the same row | Upgrade from shared to exclusive lock — use `UPDLOCK` hint on the initial read | Use `SELECT ... WITH (UPDLOCK)` when the intent is to update |
| READ COMMITTED readers blocking writers (pre-RCSI) | Default isolation level | Consider enabling RCSI (`ALTER DATABASE ... SET READ_COMMITTED_SNAPSHOT ON`) — but test first; this has implications for tempdb version store size |

#### References
- [SQL Server deadlocks guide — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-deadlocks-guide)
- [Use the system_health session — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/extended-events/use-the-system-health-session)

---

### 4.13 Error Log and Recent Critical Events

**Permissions required:** `CONTROL SERVER` or `sysadmin` for `xp_readerrorlog`. `VIEW SERVER STATE` for some configurations.

#### When to use it
At the start of every incident. The error log contains events that never appear in DMVs — hardware errors, AG state changes, stack dumps, memory warnings.

#### What question it answers
> *Has SQL Server logged any errors or warnings that match the incident timeframe?*

#### Script 1: Error log entries in the last 2 hours

```sql
-- LogNumber 0 = current log, 1 = previous cycle, etc.
-- LogType 1 = SQL Server error log, 2 = SQL Server Agent log
EXEC xp_readerrorlog 0, 1, NULL, NULL,
    DATEADD(HOUR, -2, GETDATE()),
    GETDATE(),
    N'asc';
```

#### Script 2: Search for specific keywords

```sql
-- I/O errors (investigate storage immediately if these appear)
EXEC xp_readerrorlog 0, 1, N'I/O error', NULL, NULL, NULL, N'desc';

-- Memory pressure messages
EXEC xp_readerrorlog 0, 1, N'memory', NULL, NULL, NULL, N'desc';

-- AG state changes (failover, suspend, reconnect)
EXEC xp_readerrorlog 0, 1, N'availability', NULL, NULL, NULL, N'desc';

-- Internal exceptions / stack dumps
EXEC xp_readerrorlog 0, 1, N'dump', NULL, NULL, NULL, N'desc';

-- Database corruption indicators
EXEC xp_readerrorlog 0, 1, N'corruption', NULL, NULL, NULL, N'desc';

-- Login failures (volume can indicate connection storm or credential issue)
EXEC xp_readerrorlog 0, 1, N'Login failed', NULL, NULL, NULL, N'desc';

-- Log file full
EXEC xp_readerrorlog 0, 1, N'log file is full', NULL, NULL, NULL, N'desc';
```

#### Critical messages and what to do

| Message pattern | Severity | Action |
|---|---|---|
| `SQL Server has encountered X occurrence(s) of I/O requests taking longer than 15 seconds` | High | Storage I/O problem. Check disk health, check Section 4.6. |
| `Error: 823, Severity: 24` | Critical | Hardware I/O error. Possible data corruption. Run DBCC CHECKDB on the affected database. Engage storage team immediately. |
| `Error: 824, Severity: 24` | Critical | Logical consistency error. Possible corruption. Same action as 823. |
| `Error: 825` (read retry succeeded) | Warning | Intermittent I/O error. Storage team investigation required even if reads succeeded. |
| `There is insufficient system memory in resource pool 'internal'` | High | Memory pressure at OS or SQL Server level. Check Section 4.5. |
| `Availability group ... is in the RESOLVING state` | High | AG failover in progress or a replica is disconnected. Check Section 4.9. |
| `A significant part of sql server process memory has been paged out` | High | OS is paging SQL Server memory. Check Locked Pages in Memory configuration. |
| `Stack Dump` | Critical | SQL Server internal assertion or access violation. Engage Microsoft Support if recurring. |
| `The transaction log for database ... is full` | Critical | Log space exhausted. Check Section 4.11 immediately. |
| `Login failed for user` at high volume | Medium-High | Credential error in application, connection storm, or security incident. |

#### References
- [xp_readerrorlog — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/xp-readerrorlog-transact-sql)

---

### 4.14 Security / Suspicious Activity Quick Checks

**Permissions required:** `VIEW SERVER STATE` for session DMVs; `sysadmin` for full error log access; specific audit tables depend on your audit implementation

#### When to use it
When you suspect unauthorized access, see unusual connections in `sp_WhoIsActive`, or when the incident may have a security component.

#### Critical limitation — read this first

> **Without SQL Server Audit or a custom Extended Events session configured beforehand, there is NO historical data available for login events, permission changes, or DDL activity in DMVs.** DMVs only show the current state — sessions connected right now, server principals as they exist right now. If a user logged in and ran a query 30 minutes ago and disconnected, there is no record of it in DMVs. The scripts below show only what is currently connected.

For any serious security investigation, you need SQL Server Audit logs or Extended Events history that was capturing before the incident.

#### Script 1: Active sessions from unusual sources

```sql
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.client_interface_name,
    s.login_time,
    s.last_request_start_time,
    s.status,
    s.open_transaction_count,
    c.client_net_address,
    c.local_net_address
FROM sys.dm_exec_sessions     s
JOIN sys.dm_exec_connections  c ON s.session_id = c.session_id
WHERE s.session_id > 50
ORDER BY s.login_time DESC;
```

Look for:
- `program_name = 'Microsoft SQL Server Management Studio'` connected to a production server (who is in SSMS right now?)
- `client_net_address` from unexpected IP ranges or countries
- `login_name` of accounts that should not connect directly to SQL Server

#### Script 2: Recent failed logins from error log

```sql
-- Requires login auditing to be enabled (Server Properties > Security > Login Auditing).
-- Without this setting, failed logins are not logged.
EXEC xp_readerrorlog 0, 1, N'Login failed', NULL,
    DATEADD(HOUR, -4, GETDATE()), GETDATE(), N'desc';
```

High volume of `Login failed` entries = credential stuffing, misconfigured application, or network scanning.

#### Script 3: Recent new logins and users

```sql
-- New server-level logins in the last 7 days
SELECT name, create_date, modify_date, type_desc, is_disabled
FROM sys.server_principals
WHERE create_date >= DATEADD(DAY, -7, GETDATE())
  AND type IN ('S', 'U', 'G')
ORDER BY create_date DESC;

-- New database users in the last 7 days (run per database)
SELECT name, create_date, modify_date, type_desc, authentication_type_desc
FROM sys.database_principals
WHERE create_date >= DATEADD(DAY, -7, GETDATE())
  AND type IN ('S', 'U', 'G')
ORDER BY create_date DESC;
```

#### Script 4: Current sysadmin members

```sql
-- Use JOIN instead of IS_SRVROLEMEMBER (the function is slow on large principal lists).
SELECT
    sp.name,
    sp.type_desc,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date
FROM sys.server_role_members  rm
JOIN sys.server_principals    r  ON rm.role_principal_id  = r.principal_id
                                AND r.name = 'sysadmin'
JOIN sys.server_principals    sp ON rm.member_principal_id = sp.principal_id
ORDER BY sp.name;
```

Unexpected new members of sysadmin is a critical finding — escalate to security team immediately.

#### Long-term solutions
- [SQL Server Audit — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine)
- [Extended Events — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/extended-events/extended-events)

---

### 4.15 Backup / Restore Risk Check

**Permissions required:** `VIEW ANY DATABASE`, access to `msdb.dbo.backupset` (requires `db_datareader` on msdb or sysadmin)

#### When to use it
**Before any risky action during an incident** — killing an important session, forcing a failover, restoring data, or making configuration changes.

#### What question it answers
> *How recent is our last backup? If something goes wrong right now, what can we restore to?*

#### Script 1: Last backup per database

```sql
SELECT
    d.name                                  AS database_name,
    d.recovery_model_desc,
    MAX(CASE b.type WHEN 'D' THEN b.backup_finish_date END) AS last_full_backup,
    MAX(CASE b.type WHEN 'I' THEN b.backup_finish_date END) AS last_differential,
    MAX(CASE b.type WHEN 'L' THEN b.backup_finish_date END) AS last_log_backup,
    DATEDIFF(HOUR,
        MAX(CASE b.type WHEN 'D' THEN b.backup_finish_date END),
        GETDATE())                          AS hours_since_full,
    DATEDIFF(MINUTE,
        MAX(CASE b.type WHEN 'L' THEN b.backup_finish_date END),
        GETDATE())                          AS minutes_since_log
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON b.database_name = d.name
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;
```

#### Script 2: Check backup job history

```sql
SELECT TOP 10
    j.name                       AS job_name,
    msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS last_run,
    CASE jh.run_status
        WHEN 0 THEN 'FAILED'
        WHEN 1 THEN 'Succeeded'
        WHEN 3 THEN 'Cancelled'
    END AS result,
    jh.message
FROM msdb.dbo.sysjobs       j
JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE j.name LIKE '%backup%'    -- Adjust pattern to match your naming convention
  AND jh.step_id = 0
ORDER BY msdb.dbo.agent_datetime(jh.run_date, jh.run_time) DESC;
```

#### Risk interpretation

| Situation | Risk before acting |
|---|---|
| Full backup < 1 hour old; log backup < 5 minutes old | Low. You have a recent restore point. |
| Full backup > 24 hours old; FULL recovery model | Moderate. You could lose up to 24 hours plus uncommitted work. |
| No log backups; FULL recovery model | High. Log space is wasting and there is no point-in-time restore capability. This is also a separate problem to fix. |
| SIMPLE recovery model | No point-in-time restore is possible. Only restore to the last full or differential backup. |
| No backups found at all | STOP. Do not take any action that could cause data loss until you understand this situation. |

#### References
- [Backup and restore SQL Server databases — Microsoft Docs](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/back-up-and-restore-of-sql-server-databases)

---

## 5. Crisis Decision Matrix

| Symptom | First Check | Likely Area | Useful Tool / DMV | Dangerous Mistake |
|---|---|---|---|---|
| Cannot connect at all | DAC (`admin:<server>`) | Service / connection pool | `sys.dm_os_schedulers` (via DAC) | Waiting without trying DAC |
| Users report slowness | `sp_WhoIsActive` | Multiple — check waits | `dm_exec_requests`, `dm_os_wait_stats` | Restarting SQL Server without evidence |
| CPU at 100% | Top CPU requests, cached plans | Query / workload | `dm_exec_query_stats`, Query Store | `DBCC FREEPROCCACHE` without targeting a plan |
| Memory pressure | Memory grants, waiter_count > 0 | Memory / query | `dm_exec_query_memory_grants`, `dm_exec_query_resource_semaphores` | Restarting the service to "free memory" |
| Blocking / app hangs | Blocking chain, head blocker | Locking | `dm_exec_requests`, `dm_os_waiting_tasks` | Killing sessions without identifying the head blocker |
| AG not synchronizing | Replica state, redo queue | HA/DR | `dm_hadr_database_replica_states` | Failing over without checking sync state and RPO |
| HADR_SYNC_COMMIT high | Send queue, redo queue, secondary I/O | AG / network / secondary I/O | `dm_hadr_database_replica_states` | Ignoring it — this directly degrades primary commit latency |
| TempDB full | TempDB file usage, session usage | TempDB / queries | `tempdb.sys.dm_db_file_space_usage` | Restarting SQL Server without telling the business |
| Log file growing | `log_reuse_wait_desc`, open transactions | Transaction / log | `sys.databases` (DBCC SQLPERF), `dm_tran_active_transactions` | Shrinking the log file during the incident |
| Disk latency high | File I/O delta snapshot | Storage | `dm_io_virtual_file_stats` | Running index rebuild or CHECKDB during active I/O pressure |
| Deadlocks in app logs | system_health ring buffer | Locking / query design | `dm_xe_session_targets` | Assuming retries will handle it permanently |
| Query suddenly slow | Query Store plan history | Query / plan regression | `query_store_plan`, `query_store_runtime_stats` | Forcing a plan without confirming it was historically better |
| THREADPOOL waits | Worker thread usage, long sessions | Connection flood | `dm_os_schedulers`, DAC | Trying to connect normally (all threads are taken) |
| Login failures at volume | Error log (with auditing on) | Security / app | `xp_readerrorlog` | Blocking at SQL level before notifying security team |
| SQL Agent job failing | Job history, currently running | Jobs / maintenance | `msdb.dbo.sysjobhistory`, `sysjobactivity` | Disabling the job without understanding why it failed |

---

## 6. What Not To Do During a SQL Server Incident

### ❌ Do not restart SQL Server without evidence

Restarting:
- Destroys all in-memory forensic data (DMVs, plan cache, ring buffers, wait stats)
- Rolls back all open transactions — potentially for longer than the restart itself
- Does not fix the underlying problem; the issue will recur
- Surprises every connected application

Acceptable only when: the SQL Server service has crashed and is not recovering, or when instructed by Microsoft Support with specific evidence.

### ❌ Do not kill sessions blindly

- Killing a session with a large open transaction starts a rollback. Check estimated rollback time first.
- Check whether the application will immediately reconnect and repeat the same transaction.
- The correct order: identify → understand → decide → kill a specific session with justification.

### ❌ Do not use DBCC FREEPROCCACHE without a target plan handle

`DBCC FREEPROCCACHE` (no arguments) flushes the entire plan cache for the entire instance. All queries recompile simultaneously — causing a CPU spike and compilation overhead across all applications.

If you need to evict one bad plan, target it precisely:
```sql
-- Safe: evict only one specific plan
DBCC FREEPROCCACHE (<plan_handle>);
-- Get the plan_handle from sp_WhoIsActive or sys.dm_exec_query_stats
```

### ❌ Do not run index rebuilds during a production incident

Index rebuilds consume CPU, I/O, and log space. ONLINE rebuilds hold schema stability locks; OFFLINE rebuilds hold table-level locks. Running them during peak hours or an active incident makes the situation worse.

### ❌ Do not shrink database files

`DBCC SHRINKFILE` and `DBCC SHRINKDATABASE` cause severe index fragmentation, consume CPU and I/O, do not improve performance, and are not a space solution (files will grow again). Never recommended during an incident.

### ❌ Do not change server-wide settings (MAXDOP, cost threshold, max server memory) during an incident

Server-wide configuration changes affect all workloads. Any of these changes should be planned, tested, and applied in a maintenance window — never in the middle of a crisis.

### ❌ Do not fail over an AG without checking synchronization state and business impact

Failing over to an unsynchronized secondary means potential data loss. Failing over during peak hours means a brief connection interruption for all applications. Always check the redo queue, confirm stakeholder approval, and have a rollback plan.

---

## 7. Final Printable Checklist

### SQL Server Incident Response Checklist

---

#### ⏱ 0–5 Minutes: Establish Situation

- [ ] Can you connect? If not — try the DAC: `sqlcmd -S admin:<server> -E`
- [ ] Confirm SQL Server service is running
- [ ] Check `sys.databases` — any `OFFLINE`, `SUSPECT`, or `RECOVERING` databases?
- [ ] Run `sp_WhoIsActive` — capture first snapshot
- [ ] Note the exact incident start time from users or alerting system
- [ ] Is one application affected or all applications?
- [ ] Scan error log for obvious messages (`xp_readerrorlog`)
- [ ] Check AG replica health if AG is in use

---

#### ⏱ 5–15 Minutes: Identify the Category

- [ ] **Blocking?** — `sp_WhoIsActive` shows `blocking_session_id` > 0 → run blocking chain script → identify head blocker
- [ ] **CPU high?** — Sort `dm_exec_requests` by `cpu_time` → check `dm_exec_query_stats` for cached plans
- [ ] **Memory pressure?** — Check `dm_exec_query_resource_semaphores` `waiter_count` → check `dm_exec_query_memory_grants`
- [ ] **I/O latency?** — Run delta snapshot with `dm_io_virtual_file_stats` → check PAGEIOLATCH and WRITELOG waits
- [ ] **TempDB full?** — `tempdb.sys.dm_db_file_space_usage` → session tempdb usage
- [ ] **Log growing?** — `DBCC SQLPERF('logspace')` → check `log_reuse_wait_desc` → find open transactions
- [ ] **AG unhealthy?** — Check `synchronization_state_desc` and `redo_queue_size`
- [ ] **Job running?** — `msdb.dbo.sysjobactivity` — did a job start near the incident time?
- [ ] **THREADPOOL?** — Connect via DAC → check `dm_os_schedulers` worker thread usage

---

#### ⏱ 15–30 Minutes: Deep Diagnosis and Mitigation

- [ ] Query Store: plan regressions? New plans after a recent deployment?
- [ ] Deadlocks: `system_health` ring buffer → retrieve XML deadlock graphs
- [ ] Security: unusual sessions, unexpected IPs, spike in login failures?
- [ ] Backup check: is there a recent backup before any risky action?
- [ ] Start capturing `sp_WhoIsActive` to a table in a loop (10-second intervals)
- [ ] Communicate status to stakeholders — what is known and what is being investigated
- [ ] Apply mitigations only with evidence (specific query, specific job, specific session)
- [ ] After any KILL, monitor `sys.dm_exec_requests WHERE command = 'KILLED/ROLLBACK'` for rollback progress
- [ ] Document every action taken with a timestamp

---

#### 🚨 Escalation Points — Senior DBA / Vendor Support / Microsoft CSS

- [ ] SQL Server crashing or producing stack dumps repeatedly
- [ ] Storage errors 823, 824, 825 in the error log — possible data corruption
- [ ] Data loss occurred or is suspected after an AG failover
- [ ] Incident has lasted > 30 minutes with no identified root cause
- [ ] A security breach is suspected
- [ ] The service cannot be started and downtime is ongoing

---

## 8. References

### Official Microsoft Documentation
- [SQL Server DMV Reference](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/system-dynamic-management-views)
- [Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- [Always On Availability Groups](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server)
- [Extended Events](https://learn.microsoft.com/en-us/sql/relational-databases/extended-events/extended-events)
- [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine)
- [TempDB database](https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database)
- [Transaction log architecture](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-log-architecture-and-management-guide)
- [SQL Server deadlocks guide](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-deadlocks-guide)
- [Diagnose high CPU](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/high-cpu-usage-in-sql-server)
- [Understand and resolve blocking](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/understand-resolve-blocking)
- [Troubleshoot I/O performance](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/troubleshoot-sql-io-performance)
- [Backup and restore guide](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/back-up-and-restore-of-sql-server-databases)
- [Dedicated Administrator Connection](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/diagnostic-connection-for-database-administrators)
- [sys.dm_os_schedulers](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-schedulers-transact-sql)

### Community Tools
- [sp_WhoIsActive by Adam Machanic](https://github.com/amachanic/sp_whoisactive) — http://whoisactive.com
- [First Responder Kit by Brent Ozar Unlimited](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) — `sp_Blitz`, `sp_BlitzFirst`, `sp_BlitzCache`, `sp_BlitzIndex`
- [Ola Hallengren Maintenance Solution](https://ola.hallengren.com/) — for planned maintenance (index, statistics, backup)

---

*Guide version: 2025-rev2 | Applies to: SQL Server 2019, 2022, Azure SQL Managed Instance*  
*All T-SQL scripts are read-only unless explicitly marked with ⚠️ DANGEROUS.*  
*Changelog from rev1: Fixed BUG-01 (tempdb DMV scoping), BUG-02 (FILEPROPERTY log space), BUG-03 (version store transaction filter). Added DAC section, permissions reference, KILL rollback monitoring, HADR_SYNC_COMMIT wait type, THREADPOOL action plan. Removed 300s PLE absolute threshold and DBCC SQLPERF clear suggestion. Corrected dm_exec_query_stats "since last restart" label. Corrected CXPACKET/CXCONSUMER SQL 2019 description. Fixed IS_SRVROLEMEMBER with JOIN-based query.*
