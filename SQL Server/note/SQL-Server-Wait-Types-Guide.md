# SQL Server Wait Types: A Practical DBA Guide

> 

## Table of Contents

1. [What Are Wait Types?](#1-what-are-wait-types)
2. [Why Wait Statistics Matter](#2-why-wait-statistics-matter)
3. [Key DMVs for Wait Analysis](#3-key-dmvs-for-wait-analysis)
4. [Common Wait Categories](#4-common-wait-categories)
5. [Wait Types That Are Often Benign or Background](#5-wait-types-that-are-often-benign-or-background)
6. [Practical Diagnostic Scripts](#6-practical-diagnostic-scripts)
7. [Troubleshooting Playbook](#7-troubleshooting-playbook)
8. [Deep-Dive: LCK_M_IX](#8-deep-dive-lck_m_ix)
9. [Best Practices](#9-best-practices)
10. [References and Further Reading](#10-references-and-further-reading)

---

## 1. What Are Wait Types?

### Every Query Waits for Something

SQL Server is a resource-management engine. To execute any query, SQL Server needs CPU time, memory, disk I/O, locks, latches, and more. When a thread cannot immediately proceed because a resource is not yet available, SQL Server records a **wait**. That wait has a type — a label that describes exactly what the thread is waiting for.

Wait types are SQL Server's own internal instrumentation. They are not guesses or inferences. When you observe a wait type, SQL Server is telling you: *"This thread needed something, and it had to pause to get it."*

### Normal Waits vs. Problematic Waits

Not every wait is a problem. A server with zero wait times would be unusual and likely idle. Some waits are expected, healthy, and unavoidable:

- A query reading data from disk will generate `PAGEIOLATCH_SH` waits — that is simply I/O happening.
- A session sleeping between retries will generate `WAITFOR` waits — that is application logic doing its job.
- Background system tasks generate waits like `LAZYWRITER_SLEEP` constantly, on every server, at all times.

A wait becomes worth investigating when:

- It is unexpectedly high relative to your baseline.
- It correlates with degraded query performance, blocking, or user complaints.
- It is growing over time without a clear reason.
- It represents a resource under genuine pressure.

### Waits Are Signals, Not Verdicts

The most important mindset shift when working with wait statistics is this: **a wait type tells you where to look, not what to fix.** High `PAGEIOLATCH_SH` does not automatically mean "buy faster storage." It might mean queries are doing excessive logical reads due to missing indexes, or the buffer pool is under memory pressure, or storage truly is slow. The wait type opens the investigation; it does not close it.

Always correlate wait statistics with:

- Query execution plans
- Index usage and missing index DMVs
- CPU and memory counters
- Blocking and locking information
- Application behavior and workload patterns
- Query Store (SQL Server 2016+)

---

## 2. Why Wait Statistics Matter

### Identifying Bottlenecks

Wait statistics provide a server-wide view of where time is being lost. When queries are slow, memory is under pressure, or the server becomes unresponsive, wait stats often point directly at the category of problem — I/O, CPU, locking, memory grants — before you even look at individual queries.

This makes them one of the most efficient starting points in performance troubleshooting.

### Server-Level vs. Session/Request-Level Waits

SQL Server exposes wait statistics at two levels:

| Level                                 | DMV                       | Scope                                                 |
| ------------------------------------- | ------------------------- | ----------------------------------------------------- |
| Server-level (cumulative)             | `sys.dm_os_wait_stats`    | Aggregated since last service restart or manual reset |
| Session/request-level (point-in-time) | `sys.dm_os_waiting_tasks` | Active waiting tasks right now                        |
| Request-level with details            | `sys.dm_exec_requests`    | Active requests and their current wait type           |

Cumulative wait stats from `sys.dm_os_wait_stats` show you the total picture over time. Point-in-time DMVs show you what is happening right now.

### The Danger of Cumulative Interpretation

`sys.dm_os_wait_stats` accumulates wait data from the last time SQL Server was restarted — or from the last time someone ran `DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR)` (use caution with this command in production).

This means:

- A server running for six months will have enormous cumulative wait numbers for almost everything.
- A high cumulative wait from months ago tells you very little about what is happening today.
- A wait type that dominates the cumulative list may have peaked once during a backup job three weeks ago and has been normal ever since.

**The correct approach is to compare wait stats over a defined interval — a delta sample.** Capture wait stats at time T1, wait a meaningful interval (5–15 minutes during a representative workload period), capture again at T2, and calculate the difference. This delta represents what SQL Server waited for *during that interval*, which is actionable.

See Script 5 in Section 6 for a practical delta sampling script.

---

## 3. Key DMVs for Wait Analysis

### sys.dm_os_wait_stats

Returns accumulated wait statistics for all wait types since last restart or reset.

Key columns:

| Column                | Description                                                    |
| --------------------- | -------------------------------------------------------------- |
| `wait_type`           | Name of the wait type                                          |
| `waiting_tasks_count` | Number of times this wait occurred                             |
| `wait_time_ms`        | Total wait time in milliseconds (including signal waits)       |
| `max_wait_time_ms`    | Maximum single wait duration                                   |
| `signal_wait_time_ms` | Time spent waiting for CPU after the resource became available |

`resource_wait_time_ms` is derived: `wait_time_ms - signal_wait_time_ms`. A high `signal_wait_time_ms` relative to `wait_time_ms` suggests CPU pressure — the resource was ready, but the thread had to wait for a CPU scheduler slot.

**Example — basic query:**

```sql
SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    -- Common benign/background waits (non-exhaustive)
    'SLEEP_TASK','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'XE_TIMER_EVENT','XE_DISPATCHER_WAIT','BROKER_RECEIVE_WAITFOR',
    'WAITFOR','DISPATCHER_QUEUE_SEMAPHORE','CLR_AUTO_EVENT',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG'
)
ORDER BY wait_time_ms DESC;
```

### sys.dm_os_waiting_tasks

Returns tasks currently waiting. This is a real-time, point-in-time view.

Key columns:

| Column                 | Description                                         |
| ---------------------- | --------------------------------------------------- |
| `session_id`           | Session waiting                                     |
| `wait_type`            | Current wait type                                   |
| `wait_duration_ms`     | How long this task has been waiting                 |
| `blocking_session_id`  | Session holding the resource (if applicable)        |
| `resource_description` | Details about the specific resource being waited on |

This DMV is most useful when you have an active performance incident and want to see what is blocked right now, and who is blocking it.

### sys.dm_exec_requests

Returns information about each currently executing request.

Key columns relevant to wait analysis:

| Column                | Description                        |
| --------------------- | ---------------------------------- |
| `session_id`          | Session identifier                 |
| `status`              | running, sleeping, suspended, etc. |
| `wait_type`           | Current or most recent wait type   |
| `wait_time`           | Duration of current wait (ms)      |
| `blocking_session_id` | Session blocking this request      |
| `cpu_time`            | CPU consumed                       |
| `logical_reads`       | Buffer pool reads                  |
| `reads`               | Physical reads                     |
| `writes`              | Writes                             |

Join to `sys.dm_exec_sql_text(sql_handle)` to see the actual query text.

### sys.dm_exec_sessions

Returns information about active sessions. Useful for joining with wait and request data to get login, host, application, and database context.

### sys.dm_exec_sql_text

Table-valued function. Pass a `sql_handle` or `plan_handle` to retrieve the SQL text of the batch.

```sql
SELECT text FROM sys.dm_exec_sql_text(@sql_handle);
```

### sys.dm_exec_query_plan

Table-valued function. Pass a `plan_handle` to retrieve the XML execution plan. Useful when investigating why a query is generating a particular wait type (e.g., large scans causing I/O waits, or sort operators causing memory grant pressure).

```sql
SELECT query_plan FROM sys.dm_exec_query_plan(@plan_handle);
```

### Query Store Wait Statistics (SQL Server 2017+)

SQL Server 2017 introduced wait statistics in Query Store via `sys.query_store_wait_stats`. This allows you to correlate wait types with specific query plans and query IDs over historical time windows — a major advantage over server-level cumulative stats.

```sql
SELECT
    qt.query_sql_text,
    qws.wait_category_desc,
    qws.total_query_wait_time_ms,
    qws.avg_query_wait_time_ms
FROM sys.query_store_wait_stats qws
JOIN sys.query_store_plan qp ON qws.plan_id = qp.plan_id
JOIN sys.query_store_query qq ON qp.query_id = qq.query_id
JOIN sys.query_store_query_text qt ON qq.query_text_id = qt.query_text_id
ORDER BY qws.total_query_wait_time_ms DESC;
```

> Note: Query Store must be enabled on the database (`ALTER DATABASE ... SET QUERY_STORE = ON`). Query Store wait stats are available from SQL Server 2017 onward.

---

## 4. Common Wait Categories

### Quick Reference Table

| Category            | Common Wait Types                                        | What It Usually Means           | First Things to Check                                      |
| ------------------- | -------------------------------------------------------- | ------------------------------- | ---------------------------------------------------------- |
| CPU / Scheduler     | `SOS_SCHEDULER_YIELD`, `THREADPOOL`                      | CPU pressure, thread exhaustion | CPU utilization, query plans, missing indexes, parallelism |
| Parallelism         | `CXPACKET`, `CXCONSUMER`                                 | Parallel query execution        | Skewed parallelism, MAXDOP, Cost Threshold for Parallelism |
| Locks               | `LCK_M_S`, `LCK_M_X`, `LCK_M_IX`, `LCK_M_SCH_M`          | Blocking, long transactions     | Blocking chains, transaction duration, index gaps          |
| Latches             | `PAGELATCH_EX`, `PAGELATCH_SH`, `PAGELATCH_UP`           | In-memory page contention       | TempDB files, hot pages, allocation bitmaps                |
| I/O                 | `PAGEIOLATCH_SH`, `PAGEIOLATCH_EX`, `IO_COMPLETION`      | Physical read latency           | Storage latency, buffer pool size, query reads             |
| Transaction Log     | `WRITELOG`, `LOGBUFFER`                                  | Log flush latency               | Log disk speed, transaction size, synchronous commit       |
| Memory              | `RESOURCE_SEMAPHORE`, `RESOURCE_SEMAPHORE_QUERY_COMPILE` | Memory grant pressure           | Memory grants, large sorts/hashes, statistics              |
| Network             | `ASYNC_NETWORK_IO`                                       | Client consuming results slowly | Application fetch behavior, result set sizes               |
| Backup/Maintenance  | `BACKUPIO`, `BACKUPBUFFER`                               | Backup throughput               | Backup target speed, maintenance windows                   |
| Availability Groups | `HADR_SYNC_COMMIT`, `HADR_DATABASE_FLOW_CONTROL`         | Replication latency             | Secondary performance, network latency                     |
| TempDB              | `PAGELATCH_*` on tempdb pages                            | TempDB allocation contention    | TempDB file count, spills, temp table usage                |

---

### CPU / Scheduler Waits

#### SOS_SCHEDULER_YIELD

A thread voluntarily yields the CPU scheduler to give other threads a chance to run. A moderate number of these is normal. When elevated, it indicates that many threads are competing for CPU time — threads are yielding because the scheduler is crowded.

**Common causes:**

- High CPU utilization (sustained >80–90%)
- Inefficient query plans doing excessive logical reads or computation
- Too many concurrent queries
- Excessive parallelism splitting work across too many threads

**What to check:**

- Top CPU-consuming queries via `sys.dm_exec_query_stats` or Query Store
- Missing indexes causing table scans
- Compilation overhead (too many ad-hoc queries, not using parameterization)
- Degree of parallelism settings

#### THREADPOOL

A worker thread could not be assigned because all threads in the thread pool were busy. This is a serious condition that can lead to complete server unresponsiveness.

**Common causes:**

- Massive number of concurrent blocking sessions consuming threads
- Very high connection counts with many active requests
- Long-running queries tying up worker threads
- Misconfigured `max worker threads` (rare, as the default is usually appropriate)

**What to check:**

- Active session and request counts
- Blocking chains consuming threads
- Connection pooling behavior in the application
- Query duration and throughput

> **Warning:** THREADPOOL exhaustion can cause new requests to queue indefinitely. Investigate and resolve blocking chains before considering configuration changes.

---

### Parallelism Waits

#### CXPACKET

Occurs when threads participating in a parallel query are waiting for a "packet exchange" — essentially, when some parallel threads finish their work portions faster than others and wait for the slower threads to finish.

`CXPACKET` by itself does not mean parallelism is bad. It is a natural side effect of parallel execution. However, very high `CXPACKET` with skewed parallel thread work can indicate inefficient parallelism.

#### CXCONSUMER

Introduced in SQL Server 2016 SP2 / 2017 CU3, `CXCONSUMER` was split from `CXPACKET` to distinguish the "consumer" side of exchange operators. A consumer thread waits for the producer to provide rows. `CXCONSUMER` is generally less concerning than `CXPACKET` on the producer side, but both should be evaluated together.

**MAXDOP and Cost Threshold for Parallelism:**

- `MAXDOP` controls the maximum number of threads for a parallel query. Setting it too high can cause skewed work distribution; too low can underutilize hardware.
- `Cost Threshold for Parallelism` determines when the optimizer considers a parallel plan. The default of 5 is widely considered too low for modern workloads — many DBAs raise it to 25–50, but this must be validated against the specific workload.

> **Important:** Do not change `MAXDOP` or `Cost Threshold for Parallelism` based on `CXPACKET` alone. First, identify whether the queries generating parallel waits are genuinely performing better with parallelism or are being skewed. Query tuning (indexes, statistics updates) often resolves the underlying issue without touching server-level settings.

---

### Lock Waits

Lock waits occur when a session needs a lock on a resource but another session already holds an incompatible lock. This is **blocking**.

#### Common Lock Wait Types

| Wait Type     | Lock Mode           | Meaning                                                |
| ------------- | ------------------- | ------------------------------------------------------ |
| `LCK_M_S`     | Shared              | Waiting for a shared (read) lock                       |
| `LCK_M_U`     | Update              | Waiting for an update lock                             |
| `LCK_M_X`     | Exclusive           | Waiting for an exclusive (write) lock                  |
| `LCK_M_IS`    | Intent Shared       | Waiting for intent shared lock on a higher resource    |
| `LCK_M_IX`    | Intent Exclusive    | Waiting for intent exclusive lock on a higher resource |
| `LCK_M_SCH_M` | Schema Modification | Waiting for schema modification lock (DDL operations)  |
| `LCK_M_SCH_S` | Schema Stability    | Waiting to read an object's schema                     |

#### Common Causes

- **Long-running transactions** holding locks for extended periods
- **Missing indexes** causing full scans and lock escalation
- **Isolation level conflicts** — READ COMMITTED vs. SERIALIZABLE, etc.
- **Lock escalation** — SQL Server escalating row locks to table locks
- **Hot rows** — many sessions updating the same rows simultaneously
- **Schema modification locks** (`LCK_M_SCH_M`) during index rebuilds or `ALTER TABLE` operations

#### Identifying Blocker and Blocked Sessions

Use `sys.dm_exec_requests` with `blocking_session_id`, or `sys.dm_os_waiting_tasks` with `blocking_session_id`. The blocking session itself may not appear in waiting tasks if it is idle (holding a lock from an open transaction without actively running a query) — check `sys.dm_exec_sessions` for open transactions.

See Script 4 in Section 6 for a practical blocking detection query.

#### Considerations

- **Do not simply kill blocking sessions** as a routine fix. Understand why the session is blocking and address the root cause.
- Evaluate whether Read Committed Snapshot Isolation (RCSI) would reduce read-write contention in your workload (test thoroughly before enabling).
- Check for missing indexes on columns used in join conditions and `WHERE` clauses of queries involved in blocking.

---

### Latch Waits

Latches are lightweight internal synchronization mechanisms that protect in-memory data structures (primarily buffer pool pages). Unlike locks, latches are held for very short durations and are not transaction-aware.

#### PAGELATCH_EX / PAGELATCH_SH / PAGELATCH_UP

These waits indicate contention on a specific in-memory page that multiple threads are trying to access simultaneously.

| Wait Type      | Mode      | Meaning                                                      |
| -------------- | --------- | ------------------------------------------------------------ |
| `PAGELATCH_SH` | Shared    | Multiple readers contending on the same page                 |
| `PAGELATCH_EX` | Exclusive | Writers contending — one thread modifying a page others want |
| `PAGELATCH_UP` | Update    | Update-mode latch contention                                 |

**Common causes:**

- **TempDB allocation page contention** — the PFS (Page Free Space), GAM (Global Allocation Map), and SGAM (Shared Global Allocation Map) pages in TempDB become hot under heavy temp table and worktable usage. The standard fix is to create multiple TempDB data files (typically one per logical CPU core, up to 8, then as needed).
- **Identity column hot pages** — sequential inserts into an identity column concentrate activity on the last data page of the index.
- **Right-edge index contention** — sequential key inserts (auto-increment IDs, date/time stamps) cause contention on the rightmost leaf page of an index.

#### PAGELATCH vs. PAGEIOLATCH

This distinction is important:

- `PAGELATCH_*` — The page is already in the buffer pool (memory). The thread is waiting for access to the in-memory copy.
- `PAGEIOLATCH_*` — The page is being read from disk into the buffer pool. The thread is waiting for the physical I/O to complete.

Different root causes, different solutions.

---

### I/O Waits

#### PAGEIOLATCH_SH / PAGEIOLATCH_EX

The most common I/O waits. A thread is waiting for a page to be read from storage into the buffer pool.

**Common causes:**

- The buffer pool is undersized — data that should be cached keeps being evicted, forcing physical reads.
- Missing indexes cause large table scans that read far more pages than necessary.
- Storage is genuinely slow (high latency, throughput saturation).
- Cold cache after a restart.

**What to check:**

- Storage latency via `sys.dm_io_virtual_file_stats`
- Buffer pool size and memory pressure via `sys.dm_os_performance_counters` (Page Life Expectancy)
- Query logical and physical read counts via `sys.dm_exec_query_stats`

#### IO_COMPLETION / ASYNC_IO_COMPLETION

Waits for non-data-page I/O operations to complete — such as transaction log writes, bulk operations, or system file I/O.

---

### Transaction Log Waits

#### WRITELOG

A session is waiting for the transaction log to be flushed (hardened) to disk. SQL Server must guarantee durability (the D in ACID) by flushing log records to disk before acknowledging a committed transaction.

**Common causes:**

- Log disk with high latency (seek time, mechanical HDDs, overloaded storage)
- Extremely high transaction rate — many small, frequent commits
- Batch processing that commits every row individually instead of in batches

**What to check:**

- Log file I/O latency via `sys.dm_io_virtual_file_stats`
- Whether the log file is on a shared storage device with data files
- Transaction commit frequency — batching writes where appropriate can significantly reduce `WRITELOG` waits

#### LOGBUFFER

A session is waiting for space in the log buffer to write log records. Indicates that the in-memory log buffer is filling up faster than it can be flushed.

**Common causes:**

- Very high write rate
- Slow log I/O
- Large number of concurrent write transactions

#### LOGMGR_QUEUE

A background wait associated with the log manager's internal processing queue. Usually benign at low levels; elevated values may indicate log management pressure.

#### Synchronous Commit in Availability Groups

In synchronous-commit AG configurations, `WRITELOG` waits may be elevated because SQL Server must wait for the secondary replica to harden the log before committing on the primary. See HADR waits below.

---

### Memory Waits

#### RESOURCE_SEMAPHORE

A query is waiting for a memory grant. SQL Server pre-allocates query workspace memory for sort and hash operations. When total granted memory across all queries exceeds available memory for grants, additional queries queue on this wait.

**Common causes:**

- Large `ORDER BY`, `GROUP BY`, hash join, or hash aggregate operations that request large memory grants
- Poor cardinality estimates causing over- or under-estimation of memory requirements
- Many concurrent memory-intensive queries
- Stale or missing statistics leading to bad estimates

**What to check:**

- `sys.dm_exec_query_memory_grants` for queued and granted memory requests
- Query plans for sort and hash operators with large estimated rows
- Statistics freshness
- Degree of parallelism (parallel queries multiply their memory grants)

#### RESOURCE_SEMAPHORE_QUERY_COMPILE

A query is waiting for memory to compile its execution plan. High values indicate compilation pressure, often from many unique ad-hoc queries (parameter sniffing avoidance patterns, ORMs generating dynamic SQL, etc.).

**What to check:**

- Plan cache hit ratio
- Ad-hoc workload and parameterization
- `OPTIMIZE FOR UNKNOWN`, `RECOMPILE` hints (use carefully)

---

### Network Waits

#### ASYNC_NETWORK_IO

SQL Server has query results ready to send to the client, but the client is not consuming them fast enough. SQL Server buffers fill up and the server thread must wait.

**Common causes:**

- Application fetching results row-by-row (cursor-like behavior) rather than in bulk
- Application processing each row before fetching the next
- Large result sets being sent to clients with limited bandwidth
- Network congestion (less common, but possible)

**Important note:** `ASYNC_NETWORK_IO` is not necessarily a network hardware problem. It very often reflects application-side behavior. Investigate the application's data consumption pattern before investigating the network.

**What to check:**

- Whether the application is using client-side cursors
- Whether large result sets can be reduced (pagination, filtering at the database level)
- Application response time and threading behavior

---

### Backup / Restore / Maintenance Waits

#### BACKUPIO / BACKUPBUFFER

Waits occurring during backup operations — the backup process is waiting for I/O to the backup target (disk, network share, tape, URL).

**Common causes:**

- Slow backup target storage
- Network throughput saturation when backing up to a network share or Azure Blob
- Backup compression competing for CPU

**Notes:**

- Backup waits during a scheduled maintenance window are expected and generally not a concern.
- If backups are running during business hours and impacting query performance, consider scheduling, compression, and backup target placement.

#### DISKIO_SUSPEND

Typically associated with database snapshot creation as part of backup or VSS (Volume Shadow Copy Service) operations. The database is briefly frozen (frozen I/O) while a snapshot is taken. Short durations are expected; prolonged `DISKIO_SUSPEND` may indicate VSS provider issues.

---

### Availability Group / HA Waits

#### HADR_SYNC_COMMIT

In a synchronous-commit Availability Group, the primary replica must wait for the secondary replica to harden (write to its local disk) each log block before the primary can acknowledge the commit to the client.

**Factors affecting this wait:**

- Network latency between primary and secondary
- Disk write performance on the secondary replica
- Secondary replica workload (heavy redo activity, readable secondary load)
- Log generation rate on the primary

**What to check:**

- `sys.dm_hadr_database_replica_states` for redo queue and log send queue sizes
- Network round-trip time between replicas
- Secondary disk I/O performance

#### HADR_DATABASE_FLOW_CONTROL

The primary is being throttled because the secondary cannot keep up with the log stream. SQL Server applies back-pressure to avoid overwhelming the secondary.

#### HADR_WORK_QUEUE

Background AG worker threads waiting for work. Usually benign at low levels; elevated under heavy AG activity.

---

### TempDB-Related Waits

TempDB is a shared resource used by all databases on the instance. It serves temporary tables, table variables, work files for sorts and hashes, row versioning (under RCSI/snapshot isolation), and the Service Broker. Under heavy concurrent load, TempDB can become a significant bottleneck.

#### PAGELATCH_* on TempDB Allocation Pages

The most common TempDB contention pattern. PFS, GAM, and SGAM pages within TempDB track free space and allocation status. Under high concurrency (many sessions creating and dropping temp objects simultaneously), these pages become hot.

**The standard remedy:** Create multiple equally-sized TempDB data files. Microsoft recommends one file per logical CPU core, up to 8 files, then adding more only if contention persists. All files must be the same size and configured with the same autogrowth settings. Trace flags 1117 and 1118 are built into SQL Server 2016+ by default.

#### WRITELOG in TempDB-Heavy Workloads

Heavy temp table usage, version store activity (RCSI), and sort spills all write to the TempDB transaction log, contributing to `WRITELOG` waits.

#### Spills to TempDB

When query operators (sorts, hash joins, hash aggregates) cannot fit their working data in the memory grant, they spill to TempDB. This generates I/O waits and log waits on TempDB.

**What to check:**

- Query plans with the `Warnings` property showing sort or hash spills
- `sys.dm_exec_query_stats` columns `total_spills`, `min_spills`, `max_spills` (SQL Server 2017+)
- Statistics accuracy — spills often result from underestimated row counts leading to undersized memory grants

---

## 5. Wait Types That Are Often Benign or Background

The following wait types are frequently seen on healthy, active SQL Server instances. They represent background system activity, sleeping processes, or expected idle behavior. Seeing them at the top of a cumulative `sys.dm_os_wait_stats` query does not indicate a problem.

| Wait Type                       | Description                                                                  |
| ------------------------------- | ---------------------------------------------------------------------------- |
| `LAZYWRITER_SLEEP`              | The lazy writer background process sleeping between scans of the buffer pool |
| `SQLTRACE_BUFFER_FLUSH`         | SQL Trace buffer flush process sleeping between flushes                      |
| `XE_TIMER_EVENT`                | Extended Events timer thread sleeping                                        |
| `XE_DISPATCHER_WAIT`            | Extended Events dispatcher waiting for work                                  |
| `BROKER_RECEIVE_WAITFOR`        | Service Broker background process waiting for messages                       |
| `WAITFOR`                       | Application-level `WAITFOR DELAY` or `WAITFOR TIME` statement executing      |
| `SLEEP_TASK`                    | A system task sleeping between operations                                    |
| `DISPATCHER_QUEUE_SEMAPHORE`    | Background thread dispatcher waiting for work                                |
| `CLR_AUTO_EVENT`                | CLR runtime automatic event processing                                       |
| `SLEEP_DBSTARTUP`               | Database startup background task sleeping                                    |
| `SP_SERVER_DIAGNOSTICS_SLEEP`   | Server health diagnostics task sleeping                                      |
| `WAIT_XTP_OFFLINE_CKPT_NEW_LOG` | In-Memory OLTP checkpoint waiting for new log records                        |

### Important Caveat

Filtering out these waits helps focus on actionable signals. However, **do not blindly maintain a permanent exclusion list without reviewing it periodically.** In unusual circumstances, even normally benign waits can indicate a problem. For example, `BROKER_RECEIVE_WAITFOR` could be elevated due to a Service Broker application issue rather than normal idle waiting. Context and comparison to baseline always matter.

The exclusion filters in the scripts in this guide are a reasonable starting point, not an absolute rule.

---

## 6. Practical Diagnostic Scripts

> **Safety note:** All scripts in this section are read-only queries against DMVs. They do not modify any server state. Always review scripts before running them in any environment, and ensure you have appropriate permissions.

---

### Script 1: Top Server-Level Waits (Snapshot)

**Purpose:** Shows the most significant wait types from the server-level cumulative statistics, filtered for common benign waits. Use this as a starting point to understand the overall wait profile of the instance.

**Limitation:** This reflects cumulative data since the last restart or stat reset. Use Script 5 (delta sampling) for time-bounded analysis.

```sql
-- Script: 01_top_waits_snapshot.sql
-- Purpose: Top wait types from sys.dm_os_wait_stats (cumulative, filtered)
-- Usage: Run on the target instance. Review wait_time_ms percentage for context.
-- Note: Cumulative since last SQL Server restart or manual stat reset.

DECLARE @total_wait_ms BIGINT;

SELECT @total_wait_ms = SUM(wait_time_ms)
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'XE_TIMER_EVENT','XE_DISPATCHER_WAIT','BROKER_RECEIVE_WAITFOR',
    'WAITFOR','DISPATCHER_QUEUE_SEMAPHORE','CLR_AUTO_EVENT',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'SLEEP_MASTERSTARTED','SLEEP_TEMPDBSTARTUP','TRACE_EVTNOTIF',
    'DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    'HADR_WORK_QUEUE','SLEEP_DCOMSTARTUP','FT_IFTS_SCHEDULER_IDLE_WAIT'
);

SELECT TOP 25
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms                          AS resource_wait_time_ms,
    CASE WHEN waiting_tasks_count = 0 THEN 0
         ELSE wait_time_ms / waiting_tasks_count
    END                                                         AS avg_wait_ms_per_task,
    CAST(100.0 * wait_time_ms / NULLIF(@total_wait_ms, 0) AS DECIMAL(5,2))
                                                                AS pct_of_total_wait
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'XE_TIMER_EVENT','XE_DISPATCHER_WAIT','BROKER_RECEIVE_WAITFOR',
    'WAITFOR','DISPATCHER_QUEUE_SEMAPHORE','CLR_AUTO_EVENT',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'SLEEP_MASTERSTARTED','SLEEP_TEMPDBSTARTUP','TRACE_EVTNOTIF',
    'DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    'HADR_WORK_QUEUE','SLEEP_DCOMSTARTUP','FT_IFTS_SCHEDULER_IDLE_WAIT'
)
ORDER BY wait_time_ms DESC;
```

**How to interpret:**

- High `pct_of_total_wait` for a single wait type deserves investigation if it correlates with symptoms.
- High `signal_wait_time_ms` relative to `wait_time_ms` suggests CPU pressure.
- `avg_wait_ms_per_task` is more meaningful than raw totals for understanding per-event impact.

---

### Script 2: Current Waiting Tasks

**Purpose:** Shows tasks that are currently waiting — real-time, point-in-time. Best run during an active performance incident.

```sql
-- Script: 02_current_waiting_tasks.sql
-- Purpose: Active waiting tasks right now (point-in-time)
-- Usage: Run during an active performance incident or slow period.

SELECT
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    wt.blocking_session_id,
    wt.resource_description,
    s.login_name,
    s.host_name,
    s.program_name,
    s.database_id,
    DB_NAME(s.database_id)  AS database_name,
    s.open_transaction_count
FROM sys.dm_os_waiting_tasks wt
JOIN sys.dm_exec_sessions s
    ON wt.session_id = s.session_id
WHERE wt.session_id > 50  -- Exclude system sessions
  AND s.is_user_process = 1
ORDER BY wt.wait_duration_ms DESC;
```

**How to interpret:**

- Sessions with large `wait_duration_ms` values are stuck — investigate `wait_type` and `blocking_session_id`.
- `resource_description` for lock waits shows the specific object and resource (page, key, RID, table, etc.).
- A non-NULL `blocking_session_id` means another session is directly causing this wait.

---

### Script 3: Current Requests with SQL Text and Wait Details

**Purpose:** Shows all currently active requests with their current wait type, wait time, and the actual SQL text being executed.

```sql
-- Script: 03_requests_with_waits.sql
-- Purpose: Active requests with SQL text and wait context
-- Usage: Run during investigation. Shows what is running and what each request is waiting for.

SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time                             AS wait_time_ms,
    r.blocking_session_id,
    r.cpu_time,
    r.logical_reads,
    r.reads,
    r.writes,
    r.total_elapsed_time,
    r.percent_complete,
    DB_NAME(r.database_id)                  AS database_name,
    s.login_name,
    s.host_name,
    s.program_name,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
        END / 2 - r.statement_start_offset / 2 + 1
    )                                       AS current_statement,
    t.text                                  AS full_batch_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s
    ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
  AND s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;
```

**How to interpret:**

- `current_statement` extracts only the specific statement within the batch currently executing.
- Sort by `total_elapsed_time` to find long-running requests.
- `blocking_session_id > 0` identifies blocked requests.

---

### Script 4: Blocking and Lock Waits

**Purpose:** Identifies blocking chains — which sessions are blocked and which sessions are the root blockers. Includes SQL text for both the blocked and blocking sessions where available.

```sql
-- Script: 04_blocking_and_lock_waits.sql
-- Purpose: Identify blocking chains and lock wait details
-- Note: A blocking session holding locks from an OPEN TRANSACTION may appear
--       idle (not in dm_exec_requests). Check open_transaction_count.

-- Part 1: Blocked sessions and their blockers
SELECT
    blocked.session_id                          AS blocked_session_id,
    blocked.wait_type                           AS blocked_wait_type,
    blocked.wait_time                           AS blocked_wait_ms,
    blocked.blocking_session_id                 AS blocking_session_id,
    blocked_s.login_name                        AS blocked_login,
    blocked_s.host_name                         AS blocked_host,
    blocked_s.program_name                      AS blocked_program,
    DB_NAME(blocked.database_id)                AS blocked_database,
    SUBSTRING(
        blocked_t.text,
        (blocked.statement_start_offset / 2) + 1,
        CASE blocked.statement_end_offset
            WHEN -1 THEN DATALENGTH(blocked_t.text)
            ELSE blocked.statement_end_offset
        END / 2 - blocked.statement_start_offset / 2 + 1
    )                                           AS blocked_statement,
    -- Blocker info from sessions (blocker may not be in dm_exec_requests if idle with open tx)
    blocking_s.login_name                       AS blocker_login,
    blocking_s.host_name                        AS blocker_host,
    blocking_s.program_name                     AS blocker_program,
    blocking_s.open_transaction_count           AS blocker_open_txn_count,
    blocking_s.last_request_start_time          AS blocker_last_request_start,
    COALESCE(
        (SELECT TOP 1 SUBSTRING(
            bt.text,
            (blocker_r.statement_start_offset / 2) + 1,
            CASE blocker_r.statement_end_offset
                WHEN -1 THEN DATALENGTH(bt.text)
                ELSE blocker_r.statement_end_offset
            END / 2 - blocker_r.statement_start_offset / 2 + 1
        )
        FROM sys.dm_exec_requests blocker_r
        CROSS APPLY sys.dm_exec_sql_text(blocker_r.sql_handle) bt
        WHERE blocker_r.session_id = blocked.blocking_session_id),
        -- If blocker not in requests, get last executed SQL via connections
        (SELECT TOP 1 ct.text
         FROM sys.dm_exec_connections bc
         CROSS APPLY sys.dm_exec_sql_text(bc.most_recent_sql_handle) ct
         WHERE bc.session_id = blocked.blocking_session_id)
    )                                           AS blocker_sql_text
FROM sys.dm_exec_requests blocked
JOIN sys.dm_exec_sessions blocked_s
    ON blocked.session_id = blocked_s.session_id
JOIN sys.dm_exec_sessions blocking_s
    ON blocked.blocking_session_id = blocking_s.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) blocked_t
WHERE blocked.blocking_session_id > 0
ORDER BY blocked.wait_time DESC;


-- Part 2: Lock waits from sys.dm_os_waiting_tasks (lock resource details)
SELECT
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    wt.blocking_session_id,
    wt.resource_description,
    wt.resource_address
FROM sys.dm_os_waiting_tasks wt
WHERE wt.wait_type LIKE 'LCK%'
  AND wt.session_id > 50
ORDER BY wt.wait_duration_ms DESC;
```

**How to interpret:**

- `blocker_open_txn_count > 0` on a session NOT in `dm_exec_requests` means a transaction was opened and the session is now idle — a common "sleeping blocker" pattern.
- `resource_description` in Part 2 shows the specific lock resource: `KEY`, `PAGE`, `OBJECT`, `RID`, `DATABASE`, etc.
- Trace the chain: a blocked session may itself be blocking others. Use the output to build the full chain.

---

### Script 5: Wait Stats Delta Sample

**Purpose:** Captures wait statistics at two points in time and returns the delta — what SQL Server waited for *during that specific interval*. This is more meaningful for troubleshooting than raw cumulative values.

**Usage note:** The sample interval below is 60 seconds. Adjust based on your situation. Run this during a representative period of your workload.

```sql
-- Script: 05_waits_delta_sample.sql
-- Purpose: Capture wait stats delta over a defined interval
-- Adjust @sample_seconds to your desired capture window.
-- WARNING: Uses a temporary table and WAITFOR DELAY. Do not run in tight loops.
-- This is a safe, read-only analysis script. It does not modify server state.

SET NOCOUNT ON;

DECLARE @sample_seconds INT = 60;  -- Adjust as needed (60-300 seconds recommended)

-- Snapshot 1: Before
IF OBJECT_ID('tempdb..#waits_before') IS NOT NULL
    DROP TABLE #waits_before;

SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
INTO #waits_before
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'XE_TIMER_EVENT','XE_DISPATCHER_WAIT','BROKER_RECEIVE_WAITFOR',
    'WAITFOR','DISPATCHER_QUEUE_SEMAPHORE','CLR_AUTO_EVENT',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_WORK_QUEUE',
    'FT_IFTS_SCHEDULER_IDLE_WAIT'
);

-- Wait for the sample interval
DECLARE @delay VARCHAR(8);
SET @delay = '00:' + RIGHT('00' + CAST(@sample_seconds / 60 AS VARCHAR), 2)
           + ':' + RIGHT('00' + CAST(@sample_seconds % 60 AS VARCHAR), 2);
WAITFOR DELAY @delay;

-- Snapshot 2: After
IF OBJECT_ID('tempdb..#waits_after') IS NOT NULL
    DROP TABLE #waits_after;

SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
INTO #waits_after
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'XE_TIMER_EVENT','XE_DISPATCHER_WAIT','BROKER_RECEIVE_WAITFOR',
    'WAITFOR','DISPATCHER_QUEUE_SEMAPHORE','CLR_AUTO_EVENT',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_WORK_QUEUE',
    'FT_IFTS_SCHEDULER_IDLE_WAIT'
);

-- Calculate delta
DECLARE @total_delta_ms BIGINT;
SELECT @total_delta_ms = SUM(a.wait_time_ms - ISNULL(b.wait_time_ms, 0))
FROM #waits_after a
LEFT JOIN #waits_before b ON a.wait_type = b.wait_type;

SELECT TOP 25
    a.wait_type,
    a.waiting_tasks_count     - ISNULL(b.waiting_tasks_count, 0)     AS delta_tasks_count,
    a.wait_time_ms            - ISNULL(b.wait_time_ms, 0)            AS delta_wait_time_ms,
    a.signal_wait_time_ms     - ISNULL(b.signal_wait_time_ms, 0)     AS delta_signal_wait_ms,
    a.resource_wait_time_ms   - ISNULL(b.resource_wait_time_ms, 0)   AS delta_resource_wait_ms,
    CASE
        WHEN (a.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0)) = 0 THEN 0
        ELSE (a.wait_time_ms - ISNULL(b.wait_time_ms, 0))
           / (a.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0))
    END                                                               AS avg_wait_ms_per_task,
    CAST(
        100.0 * (a.wait_time_ms - ISNULL(b.wait_time_ms, 0))
        / NULLIF(@total_delta_ms, 0)
    AS DECIMAL(5,2))                                                  AS pct_of_delta_total
FROM #waits_after a
LEFT JOIN #waits_before b ON a.wait_type = b.wait_type
WHERE (a.wait_time_ms - ISNULL(b.wait_time_ms, 0)) > 0
ORDER BY delta_wait_time_ms DESC;

DROP TABLE #waits_before;
DROP TABLE #waits_after;
```

**How to interpret:**

- `delta_wait_time_ms` shows how much total wait time accumulated for each wait type during the sample window.
- `pct_of_delta_total` shows the relative share within this sample — the dominant wait type during this period.
- Run during peak workload for the most relevant results.
- Run multiple times and compare: is the same wait type consistently dominant?

---

## 7. Troubleshooting Playbook

| Symptom                                      | Likely Wait Types                                                        | What to Check First                                                           | Possible Fixes                                                                          | Risk / Warning                                                                            |
| -------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Slow queries during business hours (general) | `SOS_SCHEDULER_YIELD`, `PAGEIOLATCH_SH`, `LCK_M_*`, `RESOURCE_SEMAPHORE` | CPU utilization, blocking chains, missing indexes, memory grants              | Index tuning, query plan review, blocking resolution                                    | Avoid global changes without identifying root cause                                       |
| Sustained high CPU                           | `SOS_SCHEDULER_YIELD`, `CXPACKET`                                        | Top CPU queries, missing indexes, parameterization, excessive recompiles      | Tune high-CPU queries, add indexes, consider MAXDOP after query tuning                  | Changing MAXDOP affects all queries; test carefully                                       |
| Blocking chains                              | `LCK_M_S`, `LCK_M_X`, `LCK_M_IX`, `LCK_M_U`                              | Root blocker session, open transaction duration, query plans                  | Shorten transactions, add indexes, review isolation levels, consider RCSI               | Enabling RCSI changes locking behavior across the database; test thoroughly               |
| Slow single-row inserts/updates              | `WRITELOG`, `LCK_M_X`, `PAGELATCH_EX`                                    | Log disk latency, transaction frequency, contention on hot pages              | Batch writes, check log disk placement, review identity/sequential key patterns         | Batching changes application logic                                                        |
| Slow reporting queries                       | `PAGEIOLATCH_SH`, `RESOURCE_SEMAPHORE`, `CXPACKET`                       | Buffer pool size, missing indexes, memory grants, parallel plan quality       | Add covering indexes, update statistics, review memory configuration                    | Memory changes affect all workloads                                                       |
| TempDB contention                            | `PAGELATCH_EX`/`UP` on tempdb, `WRITELOG`                                | Number of TempDB data files, temp table usage patterns, spills                | Add equally-sized TempDB data files, tune queries to reduce spills and temp objects     | Adding files is generally safe; always make all files the same size                       |
| Application reads results slowly             | `ASYNC_NETWORK_IO`                                                       | Application fetch behavior, result set sizes, client processing time          | Reduce result set size, paginate, fix application fetch patterns                        | Application-side changes required                                                         |
| AG synchronous commit delay                  | `HADR_SYNC_COMMIT`, `WRITELOG`                                           | Network latency between replicas, secondary disk performance, redo queue      | Investigate secondary performance, consider async commit if business requirements allow | Switching to async commit risks data loss on failover; significant architectural decision |
| Memory grant pressure                        | `RESOURCE_SEMAPHORE`                                                     | Memory grant queue depth, query plans with sorts/hashes, statistics freshness | Update statistics, tune high-memory-grant queries, review `max server memory`           | Memory configuration changes have broad impact                                            |

---

## 8. Deep-Dive: LCK_M_IX

### What Is LCK_M_IX?

`LCK_M_IX` is a wait for an **Intent Exclusive (IX) lock**. To understand it, you need to understand why intent locks exist.

### Why Intent Locks Exist

SQL Server uses a lock hierarchy: row locks, page locks, and table locks. Before placing a row-level or page-level exclusive lock, SQL Server places an **intent lock** at the table level. This tells other sessions: *"I intend to place exclusive locks lower in the hierarchy within this table."*

An IX lock at the table level signals: *"I have (or am about to have) exclusive locks on one or more rows or pages in this table."*

This allows SQL Server to quickly detect conflicts at the table level without scanning every row-level lock. Without intent locks, a full table lock would need to check every existing row lock in the table before granting a new table-level lock.

### When LCK_M_IX Is Seen as a Wait

A session waiting on `LCK_M_IX` is trying to acquire an Intent Exclusive lock on a table but cannot, because another session holds an incompatible lock at the table level. Common incompatible holders include:

- A `TABLOCK` or table-level shared lock from a query running with `TABLOCKX` or `HOLDLOCK` hints
- A schema modification lock (`LCK_M_SCH_M`) during an `ALTER TABLE` or index rebuild
- A serializable isolation level causing table-level shared locks
- Lock escalation — SQL Server escalated a large number of row locks to a table-level lock

### Common Causes

- A long-running transaction that has escalated its locks to table level
- `ALTER TABLE`, `CREATE INDEX` (online or offline), or `DROP INDEX` holding a schema lock
- Queries using `TABLOCK`, `HOLDLOCK`, or `SERIALIZABLE` hints that are taking a long time
- Reporting queries under `SERIALIZABLE` isolation competing with OLTP writes

### Detecting the Blocking Session

Use Script 4 from Section 6. The `resource_description` column in the lock wait output will show the specific resource. The `blocking_session_id` identifies the holder.

Pay attention to the blocker's `open_transaction_count`. If the blocker is not active in `sys.dm_exec_requests` but has `open_transaction_count > 0`, it has an open transaction that is not currently executing — it opened a transaction, the batch finished, but the transaction was never committed or rolled back (often an application bug).

### Why Killing the Blocking Session Is Not a Real Fix

Terminating the blocking session with `KILL` releases its locks and unblocks waiting sessions immediately. In an active incident, this may be necessary. However:

- The root cause remains: the next long transaction or the same application behavior will cause the same blocking.
- The killed transaction will roll back, which may take time proportional to the work done.
- If the session was doing legitimate work, killing it disrupts the application.

Treat `KILL` as an emergency measure for restoring service, not as a solution.

### Possible Fixes

- **Shorten transactions:** Keep the unit of work in each transaction as small as possible. Open the transaction, do the work, commit immediately. Do not hold transactions open while waiting for user input, calling external services, or performing unrelated operations.

- **Improve indexes:** Missing indexes on columns used in `WHERE` and join conditions cause full scans, which request more locks and are more likely to escalate. Proper indexing reduces the number of rows locked.

- **Tune queries:** Queries that read or modify large numbers of rows are more likely to escalate locks. Review execution plans for table scans that could be replaced with index seeks.

- **Check isolation levels:** If queries are running under `SERIALIZABLE`, consider whether a lower isolation level is appropriate. If read-write contention is the core issue, consider Read Committed Snapshot Isolation (RCSI) — but test its impact on your workload thoroughly before enabling it in production.

- **Investigate lock escalation:** Use `sys.dm_db_index_operational_stats` to check `index_lock_promotion_count` for tables involved in blocking. If escalation is frequent and causing problems, evaluate the `DISABLE_LOCK_ESCALATION` table option (available in SQL Server 2008+). Use this option with care — it can increase row-lock memory usage.

- **Avoid unnecessary long-running transactions:** Audit application code for patterns such as explicit transaction blocks that span multiple network round-trips, or batch jobs that process millions of rows in a single transaction when they could commit in smaller batches.

---

## 9. Best Practices

- **Establish a baseline.** Before you have a problem, capture and store wait stats snapshots regularly. Knowing what is "normal" for your server is essential for recognizing what is abnormal.

- **Use delta analysis, not raw cumulative stats.** Run Script 5 or an equivalent process during representative load windows. Compare delta snapshots across time rather than relying on a single raw snapshot.

- **Do not tune based on a single wait type in isolation.** A single dominant wait type is a starting point, not a conclusion. Always correlate with query plans, CPU, I/O, memory, blocking, and application behavior before making changes.

- **Tune queries before changing server-level settings.** Changing `MAXDOP`, `Cost Threshold for Parallelism`, `max server memory`, or isolation levels affects every workload on the instance. Targeted query and index tuning is almost always the safer and more effective first step.

- **Document before and after.** When you make a change, record the wait stats before and after. This validates whether the change actually helped and provides evidence for your team.

- **Use Query Store.** On SQL Server 2016+, Query Store tracks query performance, plan history, and wait statistics over time. It is one of the most powerful tools for identifying and tracking regression and identifying which queries are driving wait categories.

- **Be careful with isolation level changes.** Enabling RCSI changes read behavior for the entire database. This can significantly reduce read-write blocking but introduces version store overhead in TempDB. Test in a non-production environment that mirrors your workload.

- **Be cautious with memory configuration.** Setting `max server memory` too low starves SQL Server; too high starves the OS. Changes to memory-related configurations require careful testing and monitoring.

- **Involve the application team.** Many wait type investigations lead back to application behavior — transaction patterns, result set consumption, connection management, and query design. The DBA cannot always fix the root cause alone.

---

## 10. References and Further Reading

| Title                                                             | URL                                                                                                                                         | Supports                                                                    |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| sys.dm_os_wait_stats (Transact-SQL)                               | https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-wait-stats-transact-sql                | Primary reference for all wait type definitions and DMV columns             |
| sys.dm_os_waiting_tasks (Transact-SQL)                            | https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-waiting-tasks-transact-sql             | Real-time waiting task DMV                                                  |
| sys.dm_exec_requests (Transact-SQL)                               | https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql                | Active request details including wait type and blocking                     |
| sys.dm_exec_sessions (Transact-SQL)                               | https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-sessions-transact-sql                | Session-level information for correlating waits with users and applications |
| sys.dm_exec_sql_text (Transact-SQL)                               | https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-sql-text-transact-sql                | Retrieving SQL text associated with a handle                                |
| Query Store wait statistics (sys.query_store_wait_stats)          | https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-query-store-wait-stats-transact-sql                     | Per-query wait statistics in Query Store (SQL Server 2017+)                 |
| Monitor and tune for performance                                  | https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitor-and-tune-for-performance                                     | General performance monitoring guidance                                     |
| Transaction locking and row versioning guide                      | https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide                          | In-depth coverage of locking, blocking, and row versioning (RCSI)           |
| sys.dm_io_virtual_file_stats (Transact-SQL)                       | https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql        | File-level I/O latency — use with PAGEIOLATCH and WRITELOG waits            |
| Configure the max degree of parallelism (MAXDOP)                  | https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-max-degree-of-parallelism-server-configuration-option | MAXDOP configuration guidance                                               |
| Optimizing TempDB performance                                     | https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database                                                        | TempDB configuration, file counts, and performance                          |
| Monitor Availability Groups (sys.dm_hadr_database_replica_states) | https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-hadr-database-replica-states-transact-sql | AG replica lag, redo queue, and commit latency                              |
| Monitoring performance by using the Query Store                   | https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store                      | Using Query Store for performance analysis                                  |

---

*Last reviewed against SQL Server 2019 / SQL Server 2022 documentation. Features noted as version-specific (Query Store wait stats: 2017+) should be verified against your SQL Server version.*
