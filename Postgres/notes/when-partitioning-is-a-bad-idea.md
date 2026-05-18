# When PostgreSQL Partitioning Is a Bad Idea

Partitioning is one of the most overreached-for tools in PostgreSQL. It solves real problems when applied correctly, but it introduces a layer of structural complexity that can quietly make a database harder to maintain, slower to query, and more fragile under load — especially when the data model or query patterns are a poor match for the chosen partition key.

This document is not an argument against partitioning. It is a practical guide to the situations where you should not reach for it, and what you should do instead.

---

## The Main Rule

Partitioning is useful only when **most of your important queries include the partition key in the WHERE clause**. PostgreSQL uses the partition key to prune the search space at the planner level. If your application cannot consistently supply that key, the planner has to scan every partition — which is often slower than scanning one well-indexed table.

If your application mostly queries by `id`, `user_id`, `status`, or other columns that are not the partition key, partitioning provides no pruning benefit and adds overhead without return.

---

## When Partitioning Is a Bad Idea

### 1. The Table Is Small or Medium-Sized

Partitioning is a physical data management strategy, not a query optimization shortcut. For tables with millions of rows or fewer, a normal heap table with proper indexes is almost always faster and simpler. The planner can use index scans efficiently without any partition overhead.

Partition management — creating new partitions, monitoring their sizes, running VACUUM per partition, and handling missing partitions — adds operational cost that is only justified at scale. If the table is not large enough to make full sequential scans prohibitively slow, that overhead is wasted effort.

**Start with indexes. Partition only after you can demonstrate that they are insufficient.**

---

### 2. Queries Do Not Filter by the Partition Key

This is the most common mistake. A table is partitioned by `processed_at`, `created_at`, or some other timestamp, and then the application consistently queries by `id`.

```sql
-- Intended to be fast, but will scan every partition
SELECT * FROM event_queue WHERE id = 12345;
```

PostgreSQL cannot prune partitions based on `id` alone if `id` is not the partition key. The planner must visit each partition and check whether the row might exist there. On a table with many partitions, this degrades into something close to a full scan, even though the result is a single row.

The fix is not to add the partition key to every query. If your access patterns do not naturally include the partition key, the partition strategy is wrong for your workload.

---

### 3. You Need a Simple Primary Key on `id`

PostgreSQL requires that **every unique constraint on a partitioned table must include the partition key**. This means `PRIMARY KEY (id)` is not directly achievable on a table partitioned by `processed_at` or `status`.

The workarounds all carry trade-offs:

- **Composite primary key** (`id`, `processed_at`): Allows NULL in `processed_at`, which means uniqueness on pending rows is not enforced by the database. Two rows with the same `id` and NULL `processed_at` can coexist.
- **COALESCE in the key expression**: Solves the NULL problem but makes the schema harder to understand and requires careful partition boundary design.
- **Application-level enforcement**: Drops the database guarantee entirely and moves correctness into the application layer.
- **Separate lookup table**: Adds a secondary structure just to resolve IDs, increasing read complexity and write overhead.

If the application expects `PRIMARY KEY (id)` semantics — as most applications do — partitioning by a nullable or mutable column adds friction with no offsetting benefit unless the workload is genuinely suited for it.

---

### 4. Other Tables Have Foreign Keys to This Table

Foreign keys referencing a partitioned table must reference a unique constraint that includes the partition key. A simple reference like this will not work:

```sql
-- This will fail or behave unexpectedly on a table partitioned by processed_at
CREATE TABLE event_results (
    id SERIAL PRIMARY KEY,
    event_id BIGINT REFERENCES event_queue(id)
);
```

The referencing table must carry the partition key as well:

```sql
ALTER TABLE event_queue ADD UNIQUE (id, processed_at);

CREATE TABLE event_results (
    id SERIAL PRIMARY KEY,
    event_id BIGINT,
    event_processed_at TIMESTAMP,
    FOREIGN KEY (event_id, event_processed_at)
        REFERENCES event_queue(id, processed_at)
);
```

Now `event_results` must track the `processed_at` value of every row it references. If that value changes — because the event is processed and moves to a different partition — the foreign key in the dependent table must be updated atomically. This kind of cascading complexity is rarely worth it.

When a table sits at the center of a relational schema with multiple dependents, partitioning it usually creates more problems than it solves.

---

### 5. The Partition Key Changes After Insert

In PostgreSQL, updating the partition key of a row causes the row to **physically move between partitions**. This is not a simple in-place update. Internally, PostgreSQL deletes the row from the source partition and inserts it into the destination partition. Both operations are written to WAL and both trigger index maintenance on both partitions.

```sql
-- This is inexpensive on a normal table.
-- On a partitioned table, it is a DELETE + INSERT across two partitions.
UPDATE event_queue
SET processed_at = NOW(), processed_by = 'worker-1'
WHERE id IN (SELECT id FROM event_queue WHERE processed_at IS NULL LIMIT 1000);
```

At low volumes this is manageable. At high throughput — thousands of updates per second — the extra write amplification accumulates. Dead tuples build up in the source partition. Index pages fragment. VACUUM has to work harder, and it has to do so on each partition independently.

If the core operation of your system is updating a column that serves as the partition key, partitioning by that column will add cost to your most frequent operation.

---

### 6. Lookups Are Primarily by `id`

Queue-like tables are often partitioned to separate pending from processed data. This is a reasonable goal. The risk appears when workers and dependent systems primarily look up rows by `id` to check status, fetch results, or correlate with other records.

If `id`-based lookups are frequent and the partition key is `processed_at` or `status`, every such lookup must scan all partitions. The partitioning serves the archival goal well but works against the operational query pattern. These two concerns are in tension, and partitioning cannot satisfy both simultaneously.

---

### 7. Processed Data Is Deleted Quickly

One of the concrete benefits of partitioning is that you can drop an old partition with a single DDL statement, which is far faster and cheaper than a large DELETE. This benefit is real — but only if old data actually accumulates.

If your retention policy deletes processed or historical records within a few days or weeks, the partitions never grow large enough to make that DROP meaningful. You are carrying the full complexity of the partitioning scheme — composite keys, per-partition indexes, monitoring, creation automation — without ever using the one feature that justifies it.

For short retention windows, a periodic DELETE job on a normal table is simpler and almost certainly fast enough.

---

### 8. The Team Cannot Maintain Partitions Reliably

Partitioning is not just a DDL decision. It is an ongoing operational commitment. Among the things that must be managed:

- Creating new partitions ahead of time (a missing partition causes inserts to fail or route to a DEFAULT partition)
- Monitoring partition sizes and growth rates independently
- Ensuring indexes exist on each partition, since index creation on the parent does not automatically apply retroactively
- Running VACUUM and ANALYZE across each partition, or verifying that autovacuum is doing so appropriately
- Managing bloat across partitions that receive frequent updates

If the team does not have tooling and processes for this, partitioning will create operational surprises: missed partitions causing insert failures, bloated partitions from high-update workloads, or query regressions when a partition's statistics go stale.

---

### 9. Indexes Would Already Solve the Problem

Before partitioning a table, verify that indexing strategies have been fully explored. Several index types cover use cases that are often mistakenly addressed with partitioning:

- **Partial indexes** are effective when a small subset of rows is queried heavily. A partial index on pending rows is often more efficient than separating them into a different partition.
- **Composite indexes** cover multi-column query patterns without any schema restructuring.
- **BRIN indexes** are well-suited to large append-only tables with naturally ordered data, such as time-series logs, at a fraction of the storage cost of a B-tree index.
- **Query-level tuning** — proper use of `LIMIT`, smarter join ordering, or caching — sometimes resolves performance concerns entirely without touching the schema.

Partitioning is not a substitute for index design. It is an addition to it, and it adds complexity even when used correctly.

---

## Realistic Example: The Event Queue

The event queue pattern — partitioning by `processed_at` to separate pending and processed events — is a frequently cited example of partitioning done well. In the right context, it works. In the wrong context, it accumulates problems quietly.

The pattern becomes risky when:

**Strict `id` uniqueness is required.** Because the partition key must be part of any unique constraint, `PRIMARY KEY (id)` on a table partitioned by `processed_at` is not enforceable without COALESCE expressions or sentinel values. The database cannot guarantee uniqueness on pending rows when `processed_at` is NULL and the composite key allows it.

**Other tables reference `event_queue(id)`.** As described above, dependent tables must carry the partition key, and any state change on the partition key must be propagated atomically. In a schema with multiple referencing tables, this becomes unwieldy quickly.

**Workers update many rows at high frequency.** Marking events as processed is a partition key change. At high throughput, this generates significant write amplification and bloat in the pending partition. The benefit of separating pending from processed data may be outweighed by the cost of moving rows between partitions under load.

**Queries often look up rows by `id` alone.** If workers, monitoring systems, or dependent services need to fetch a specific event by `id` — without knowing its `processed_at` value — every such query scans all partitions. The lookup pattern is incompatible with the partition strategy.

**Processed events are deleted quickly.** If processed events are deleted after a few days, there is nothing to archive. A DROP on a small partition saves nothing worth saving, and the complexity of managing those partitions was incurred for no durable benefit.

---

## Better Alternatives

For each scenario above, simpler approaches are usually available.

### Partial Index for Active Rows

When a small, well-defined subset of rows is queried frequently — pending events, open orders, active sessions — a partial index targets exactly those rows without restructuring the table.

```sql
-- Normal table with a partial index for pending events
CREATE TABLE event_queue (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW() NOT NULL,
    processed_at TIMESTAMP,
    processed_by VARCHAR(50),
    result JSONB
);

-- Only indexes rows where processed_at is NULL
-- Small, fast, and automatically maintained
CREATE INDEX idx_pending_events ON event_queue(created_at)
    WHERE processed_at IS NULL;
```

This gives efficient access to pending rows without any of the primary key, foreign key, or update-movement complications of partitioning.

### Composite Index for Common Lookups

When queries consistently filter on a combination of columns, a composite index covers them directly.

```sql
-- Queries like: WHERE event_type = 'order_placed' AND created_at > NOW() - INTERVAL '1 hour'
CREATE INDEX idx_event_type_created ON event_queue(event_type, created_at)
    WHERE processed_at IS NULL;
```

### Active Table + Archive Table

When the operational table needs to stay small and the historical data needs to be retained but is queried rarely, two tables with different schemas serve the purpose better than a single partitioned table.

```sql
-- Hot path: simple, unpartitioned, full PK semantics
CREATE TABLE event_queue_active (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW() NOT NULL
);

-- Archive: partitioned for lifecycle management, queried by date range
CREATE TABLE event_queue_archive (
    id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL,
    processed_at TIMESTAMP NOT NULL,
    processed_by VARCHAR(50),
    result JSONB,
    PRIMARY KEY (id, processed_at)
) PARTITION BY RANGE (processed_at);

-- Move completed rows to the archive after processing
WITH processed AS (
    DELETE FROM event_queue_active
    WHERE id = 12345
    RETURNING *
)
INSERT INTO event_queue_archive (id, event_type, event_data, created_at, processed_at, processed_by, result)
SELECT id, event_type, event_data, created_at, NOW(), 'worker-1', '{"status": "success"}'::jsonb
FROM processed;
```

The active table retains simple `PRIMARY KEY (id)` semantics and full foreign key support. The archive table uses partitioning where it actually helps: deterministic, immutable data keyed on `processed_at`, dropped by month when the retention window expires.

### BRIN Index for Large Append-Only Tables

For time-series or audit tables where data is written sequentially and queried by time range, a BRIN index is a fraction of the size of a B-tree index and covers range queries efficiently without partitioning.

```sql
CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY,
    recorded_at TIMESTAMP NOT NULL DEFAULT NOW(),
    entity_type VARCHAR(50),
    entity_id BIGINT,
    payload JSONB
);

-- BRIN covers range queries on recorded_at with minimal storage overhead
CREATE INDEX idx_audit_brin ON audit_log USING BRIN (recorded_at);
```

### Periodic Archival Job

When the goal is to remove old data rather than to query it by partition, a scheduled job against a normal table is straightforward and requires no schema changes.

```sql
-- Run nightly via pg_cron or an external scheduler
DELETE FROM event_queue
WHERE processed_at < NOW() - INTERVAL '30 days';
```

---

## Decision Checklist

Before choosing to partition a table, answer these questions:

- **Do most queries include the partition key in the WHERE clause?** If not, pruning will not apply and query performance may be worse.
- **Is the table large enough to justify the overhead?** Hundreds of millions of rows with genuine performance problems is a reasonable threshold. A few million rows with indexes is usually not.
- **Will the partition key change after insert?** If so, updates will move rows between partitions, generating write amplification and bloat under load.
- **Does the application need `PRIMARY KEY (id)`?** If yes, partitioning by a nullable or mutable column adds significant key management complexity.
- **Do other tables reference this table by `id`?** If yes, foreign key constraints will require those tables to carry the partition key as well.
- **Is there a durable retention or archival strategy?** If processed data is deleted quickly, the main benefit of partitioning — fast DROP of old partitions — is never realized.
- **Can the team create, monitor, and maintain partitions reliably?** Missing partitions cause insert failures. Unmonitored partitions accumulate bloat. Absent indexes cause query regressions.
- **Have indexes been tried first?** Partial indexes, composite indexes, and BRIN indexes cover many cases that are mistakenly attributed to partitioning.

---

## Final Recommendation

Partitioning is a structural decision, not a performance patch. It works well for predictable data lifecycle management — dropping old partitions, isolating hot data from cold data, or managing very large datasets where full scans would be impractical even with indexes.

It does not work well as a response to a slow query, a large row count that has not yet caused problems, or a vague sense that a table should be partitioned because it is important.

Start with a normal table and proper indexes. Analyze query patterns with `EXPLAIN (ANALYZE, BUFFERS)`. Apply partial or composite indexes where the access patterns are clear. If the table grows to a scale where indexes alone are insufficient, and if most queries naturally include a stable, high-cardinality column, then partitioning by that column becomes a well-founded decision.

Partitioning chosen for the wrong reasons will add complexity without adding capability. Partitioning chosen for the right reasons, on the right data model, with a team equipped to maintain it, is a legitimate and powerful tool.
