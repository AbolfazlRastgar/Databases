# 30 PostgreSQL Data Types Every Data Engineer Should Know

> A practical reference for data engineers, analytics engineers, and backend developers building production systems on PostgreSQL.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Quick Selection Table](#quick-selection-table)
3. [Main Guide](#main-guide)
   - Numeric Types
   - String Types
   - Boolean
   - Date and Time Types
   - Identifiers
   - Semi-Structured Data
   - Binary
   - Network Types
   - Arrays
   - Range and Multirange Types
   - Other Useful Types
4. [Important Comparisons](#important-comparisons)
5. [Practical Rules for Data Engineers](#practical-rules-for-data-engineers)
6. [Final Cheat Sheet](#final-cheat-sheet)
7. [Further Reading](#further-reading)

---

## Introduction

Choosing the right PostgreSQL data type is one of the most consequential decisions in schema design. It affects everything downstream: query performance, storage footprint, data quality enforcement, indexing strategy, and the long-term maintainability of your pipelines and models.

Data engineers often reach for the most permissive type available — usually `text` or `jsonb` — because it accommodates anything. That flexibility comes at a cost. Loose typing means the database cannot enforce constraints on your behalf, query planners lose precision, and downstream consumers inherit ambiguity that compounds over time.

Choosing types deliberately pays dividends in these areas:

**Storage efficiency.** A `smallint` occupies 2 bytes. A `text` representation of the same integer can occupy 10 or more. At billions of rows, that gap becomes significant, especially in columnar storage layers and over-the-wire serialization.

**Query performance.** The query planner uses column type statistics to generate execution plans. Correct types allow the planner to use range scans, index-only scans, and operator-specific indexes. Incorrect types force casts, disable index use, and produce suboptimal plans.

**Data quality.** PostgreSQL constraints are only as precise as the type allows. A `date` column cannot store `"next monday"`. A `numeric(12,2)` column cannot store a value with three decimal places silently. Types are the first line of defense in data quality enforcement, before application logic or pipeline validation.

**Indexing.** Many PostgreSQL index types are type-specific. GIN indexes work on `jsonb`, arrays, and full-text vectors. GiST indexes work on range types, geometric types, and `inet`. Choosing the right type unlocks the right index.

**ETL/ELT pipelines.** When loading data from external sources — APIs, CSVs, CDC streams, Kafka topics — type mismatches cause silent truncation, implicit coercions, and load failures. Explicit types make pipelines more predictable and easier to test.

**Analytics and reporting.** BI tools, query engines, and dbt models all behave differently depending on column types. Timestamps without time zones produce incorrect aggregations across regions. Numbers stored as text cannot be summed. Enums stored as integers cannot be labeled without joins.

**Schema maintainability.** Schemas that use precise types are self-documenting. A column typed `inet` communicates intent. A column typed `text` communicates nothing.

This guide covers approximately 30 PostgreSQL data types with practical guidance on when to use them, when to avoid them, what mistakes to watch for, and how they behave under real workloads.

---

## Quick Selection Table

| Data Type | Category | Best Used For | Avoid When | Data Engineering Example |
|---|---|---|---|---|
| `smallint` | Numeric | Small integer codes, low-cardinality counts | Values may exceed 32,767 | Status codes, day-of-week integers |
| `integer` | Numeric | General-purpose integer IDs, counts | Tables with billions of rows | Order counts, product IDs |
| `bigint` | Numeric | Large fact table IDs, event counts, sequence keys | Memory is very constrained and values are small | User event IDs, CDC offset tracking |
| `numeric` | Numeric | Exact financial values, amounts, rates | Approximate scientific data | Invoice amounts, tax rates |
| `real` | Numeric | Scientific approximations, ML feature values | Exact financial math | Sensor readings, low-precision scores |
| `double precision` | Numeric | Higher-precision floating point approximations | Exact decimal arithmetic | Latitude/longitude, probability scores |
| `text` | String | Free-form content, names, labels, raw imports | Structured values like dates, IPs, UUIDs | Campaign names, log messages |
| `varchar(n)` | String | Fields with meaningful length constraints | Length limit is arbitrary or unknown | Username (max 50), country code |
| `char(n)` | String | Fixed-width codes with known exact length | Variable-length content | ISO currency codes, fixed-format codes |
| `boolean` | Boolean | Binary flags, feature toggles | Tri-state or null-heavy logic | `is_active`, `has_consent` |
| `date` | Date/Time | Calendar dates without time | Events that require time-of-day precision | Birthdate, subscription start date |
| `time` | Date/Time | Time of day without a date | Full event timestamps | Business hours, scheduled time slots |
| `timestamp` | Date/Time | Wall-clock time in a known single time zone | Multi-region systems or UTC is not guaranteed | Internal audit logs in single-TZ systems |
| `timestamptz` | Date/Time | UTC event timestamps across time zones | Single-TZ systems where overhead matters | All external event timestamps |
| `interval` | Date/Time | Durations, time deltas, SLA calculations | Storing absolute points in time | Session duration, TTL calculations |
| `uuid` | Identifier | Globally unique IDs, cross-system keys | Sequential inserts into B-tree indexes at scale | API resource IDs, cross-service entity keys |
| `bigserial` / identity | Identifier | Surrogate keys in single-system tables | Cross-system ID sharing | Auto-incrementing fact table surrogate keys |
| `json` | Semi-structured | Raw JSON preservation (rarely preferred) | Querying or indexing is needed | Archiving original API responses verbatim |
| `jsonb` | Semi-structured | Semi-structured data requiring query or indexing | Schema is fully known and stable | API payloads, flexible attribute storage |
| `hstore` | Semi-structured | Simple key-value pairs (requires extension) | Complex nested structures | Tag storage, configuration metadata |
| `bytea` | Binary | Raw binary objects, encrypted payloads | Storing files that belong in object storage | Encryption key material, image thumbnails |
| `inet` | Network | IPv4 and IPv6 addresses with subnet logic | Simple string storage of IPs is sufficient | Web server logs, access control tables |
| `cidr` | Network | Network address blocks | Individual host addresses | Firewall rules, VPC CIDR allocations |
| `macaddr` / `macaddr8` | Network | MAC addresses | General text storage | Device inventory, network audit tables |
| `text[]` / `integer[]` | Array | Multi-value tags, flag sets | Analytics aggregation is the primary use | Tag lists, multi-value attribute sets |
| `int4range` / `int8range` | Range | Integer ranges, version bands | Point-in-time or date logic | Partition key ranges, numeric bands |
| `tstzrange` | Range | Time windows with time zone awareness | Simple point-in-time storage | Session windows, billing periods, SLAs |
| `daterange` | Range | Calendar date intervals | Time-of-day precision is needed | Contract validity periods, date-based partitions |
| `enum` | Custom | Stable, low-cardinality categorical values | Values change frequently | Order status, payment method |
| `numeric` domain | Domain | Reusable constrained numeric types | One-off constraints | `positive_amount`, `percentage` |
| `money` | Monetary | Legacy compatibility only | New schema design | (Avoid in new schemas — use `numeric`) |

---

## Main Guide

---

### Numeric Types

---

### smallint

**What it is:**
A 2-byte signed integer with a range of -32,768 to 32,767.

**Use it for:**
Low-cardinality integer codes where you are confident values will never exceed the range. Examples include day-of-week codes (0–6), month numbers (1–12), HTTP status codes, or small reference table IDs.

**Avoid it when:**
You are not certain the range is bounded. Using `smallint` for an auto-incrementing ID that might exceed 32,767 will cause an overflow error in production.

**Data engineering example:**
A dimension table storing day-of-week, hour-of-day, or ISO week number benefits from `smallint` because the values are fixed and bounded.

**Common mistake:**
Using `smallint` for surrogate keys on tables that will grow. A single viral event can push an ID counter past the limit faster than expected.

**Indexing note:**
B-tree indexes on `smallint` are compact and fast. The smaller storage footprint also improves index page density.

```sql
CREATE TABLE dim_time (
    hour_of_day   smallint NOT NULL CHECK (hour_of_day BETWEEN 0 AND 23),
    day_of_week   smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    iso_week      smallint NOT NULL CHECK (iso_week BETWEEN 1 AND 53)
);
```

---

### integer

**What it is:**
A 4-byte signed integer with a range of approximately -2.1 billion to 2.1 billion.

**Use it for:**
General-purpose integer IDs, counts, and reference keys in tables that will not exceed roughly 2 billion rows. It is the default integer type in PostgreSQL and is appropriate for the majority of OLTP and moderate-scale analytics use cases.

**Avoid it when:**
Your fact tables or event tables may approach or exceed 2 billion rows. Event-driven systems, high-frequency clickstreams, and large IoT ingestion pipelines can exhaust an integer sequence within months.

**Data engineering example:**
Product IDs, category IDs, or foreign keys in star schema dimension tables.

**Common mistake:**
Using `integer` as a primary key in a fact table that will receive billions of inserts, then hitting sequence exhaustion in production.

**Indexing note:**
The 4-byte width gives B-tree indexes good page density. Prefer `integer` over `bigint` where the range is confirmed to be safe, as it saves both storage and cache pressure.

```sql
CREATE TABLE dim_product (
    product_id    integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    product_name  text    NOT NULL,
    category_id   integer NOT NULL
);
```

---

### bigint

**What it is:**
An 8-byte signed integer with a range of approximately -9.2 quintillion to 9.2 quintillion.

**Use it for:**
Large fact table surrogate keys, event IDs, Kafka offsets, CDC sequence numbers, row counts on large tables, and any identifier where the upper bound is not known or is very large. This should be the default choice for primary keys on high-volume tables.

**Avoid it when:**
You are working with very constrained storage, the values are provably small, or you are defining a dimension with bounded cardinality. Using `bigint` everywhere without reason wastes 4 bytes per value compared to `integer`.

**Data engineering example:**
An event fact table ingesting billions of clickstream events per month. The primary key and foreign keys to large dimension tables should be `bigint`.

**Common mistake:**
Using `integer` as a surrogate key and then performing a costly `ALTER TABLE` to `bigint` after sequence exhaustion becomes a risk.

**Indexing note:**
B-tree index entries on `bigint` are 8 bytes instead of 4. On very large indexes this can affect page density, but the difference is rarely the primary bottleneck.

```sql
CREATE TABLE fact_events (
    event_id      bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       bigint      NOT NULL,
    occurred_at   timestamptz NOT NULL,
    event_type    text        NOT NULL
);
```

---

### numeric / decimal

**What it is:**
An arbitrary-precision exact numeric type. `numeric(precision, scale)` stores up to `precision` significant digits with exactly `scale` digits after the decimal point. `numeric` without arguments stores values with user-specified precision up to the implementation limit.

**Use it for:**
Financial amounts, monetary calculations, tax rates, percentage values, and any value where exact decimal representation is required. `numeric` does not suffer from binary floating-point rounding errors.

**Avoid it when:**
You need fast approximate arithmetic. `numeric` is significantly slower than `real` or `double precision` for large-scale mathematical operations because it performs decimal arithmetic in software rather than using CPU floating-point hardware.

**Data engineering example:**
An invoice line table storing unit price, quantity, tax rate, and line total. All financial values should be `numeric(18,4)` or similar.

**Common mistake:**
Using `double precision` or `real` for financial values, which introduces rounding errors. `0.1 + 0.2` in floating point is not exactly `0.3`. This causes reconciliation failures in accounting pipelines.

**Indexing note:**
B-tree indexes work on `numeric`. No special considerations, but `numeric` comparisons are slower than integer comparisons due to variable-length representation.

```sql
CREATE TABLE invoice_lines (
    line_id       bigint          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id    bigint          NOT NULL,
    unit_price    numeric(18, 4)  NOT NULL,
    quantity      numeric(10, 4)  NOT NULL,
    tax_rate      numeric(5, 4)   NOT NULL,
    line_total    numeric(18, 4)  NOT NULL
);
```

---

### real

**What it is:**
A 4-byte single-precision IEEE 754 floating-point number. Provides approximately 6 decimal digits of precision.

**Use it for:**
Scientific measurements, sensor readings, and ML feature values where approximate precision is acceptable and storage compactness matters more than exactness.

**Avoid it when:**
Any financial calculation, accounting value, or situation where exact decimal representation is required. Also avoid when values span a very wide range, as precision degrades at extremes.

**Data engineering example:**
Storing temperature sensor readings, signal strength values, or recommendation scores where 6 digits of precision is sufficient.

**Common mistake:**
Using `real` for values that will be aggregated, compared, or reported as exact amounts. Accumulated rounding errors across `SUM()` over millions of rows can produce visibly incorrect totals.

```sql
CREATE TABLE sensor_readings (
    reading_id    bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sensor_id     integer NOT NULL,
    temperature_c real    NOT NULL,
    recorded_at   timestamptz NOT NULL
);
```

---

### double precision

**What it is:**
An 8-byte double-precision IEEE 754 floating-point number. Provides approximately 15 decimal digits of precision.

**Use it for:**
Geographic coordinates (latitude, longitude), probability scores, scientific calculations, and cases where the wider precision of `double precision` over `real` is needed but exact decimal arithmetic is not required.

**Avoid it when:**
Exact decimal values are needed. The same fundamental floating-point issue as `real` applies — the precision is higher but it is still approximate.

**Data engineering example:**
Storing latitude and longitude on a location dimension. `double precision` gives enough precision (about 1.1 meters at 8 decimal places) for most geospatial use cases.

**Common mistake:**
Assuming `double precision` is safe for financial values because it has 15 digits of precision. It is not. `1.005` cannot be represented exactly in binary floating point, regardless of width.

```sql
CREATE TABLE locations (
    location_id   integer          PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    location_name text             NOT NULL,
    latitude      double precision NOT NULL,
    longitude     double precision NOT NULL
);
```

---

### String Types

---

### text

**What it is:**
A variable-length character string with no explicit length limit (up to 1 GB in theory, though practical limits are much lower). The most general-purpose string type in PostgreSQL.

**Use it for:**
Descriptions, names, log messages, labels, raw imported fields, free-form user content, and any string field where enforcing a length constraint is not meaningful.

**Avoid it when:**
The value has a structured format that PostgreSQL can enforce with a better type: dates, IP addresses, UUIDs, booleans, enums, and numeric values should all use their proper types, not `text`.

**Data engineering example:**
Storing raw event names from a CSV import, campaign descriptions, error message payloads, or source system labels in a staging table.

**Common mistake:**
Using `text` for every string field by default, including fields that represent dates, statuses, IDs, and categories. This defers data quality enforcement to the application layer, where it is often not enforced.

**Indexing note:**
Standard B-tree indexes on `text` work well for equality and prefix lookups. For full-text search, use `tsvector` and GIN indexes. For pattern matching with `LIKE '%term%'`, use `pg_trgm` with a GIN or GiST index.

```sql
CREATE TABLE pipeline_runs (
    run_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pipeline_name text   NOT NULL,
    status        text   NOT NULL,  -- Consider enum instead
    error_message text
);
```

---

### varchar(n)

**What it is:**
A variable-length string with an explicit maximum length constraint. Functionally, `varchar(n)` is `text` with a CHECK constraint enforcing a length limit.

**Use it for:**
Fields where a maximum length is semantically meaningful and part of the business rule. Examples: usernames (max 50 characters), short codes (max 10 characters), or fields that map to external systems with documented length limits.

**Avoid it when:**
The length limit is arbitrary, chosen defensively, or likely to change. Altering a `varchar(n)` constraint upward requires an `ALTER TABLE` and a table rewrite in older PostgreSQL versions (though modern versions handle some cases without a rewrite). If the limit carries no semantic meaning, prefer `text`.

**Data engineering example:**
An interface table loading data from an external system that documents a `VARCHAR(255)` constraint. Matching the type preserves the upstream contract at the boundary.

**Common mistake:**
Using `varchar(255)` everywhere as a default because it is familiar from MySQL or SQL Server. In PostgreSQL, `varchar(255)` and `text` have identical storage and performance. The `(255)` adds no benefit unless the limit is a real constraint.

```sql
CREATE TABLE users (
    user_id       bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username      varchar(50)  NOT NULL UNIQUE,
    display_name  text,
    email         text         NOT NULL UNIQUE
);
```

---

### char(n)

**What it is:**
A fixed-length, blank-padded string type. All stored values are padded with spaces to exactly `n` characters.

**Use it for:**
Fixed-width codes where every value is guaranteed to have the same length and where blank padding is acceptable or irrelevant: ISO 3166-1 alpha-2 country codes (`char(2)`), ISO 4217 currency codes (`char(3)`), or fixed-format legacy codes from mainframe or EDI systems.

**Avoid it when:**
The length is variable or likely to vary. The blank-padding behavior of `char(n)` is a frequent source of subtle bugs: `'US' = 'US '` is true in `char` comparisons, which can cause unexpected join behavior.

**Data engineering example:**
A currency dimension table using ISO 4217 three-character codes, where `char(3)` documents the fixed-length contract precisely.

**Common mistake:**
Using `char(n)` for codes that are usually but not always the same length, then experiencing join failures or missed lookups caused by trailing space padding.

```sql
CREATE TABLE dim_currency (
    currency_code char(3)  NOT NULL PRIMARY KEY,
    currency_name text     NOT NULL,
    numeric_code  smallint NOT NULL
);
```

---

### Boolean

---

### boolean

**What it is:**
A standard SQL boolean type that stores `TRUE`, `FALSE`, or `NULL`. Occupies 1 byte.

**Use it for:**
Binary flags, feature toggles, consent flags, soft-delete markers, and any attribute with a clear true/false semantics. PostgreSQL accepts `true`, `false`, `'t'`, `'f'`, `'yes'`, `'no'`, `'on'`, `'off'`, `1`, and `0` as input.

**Avoid it when:**
The flag has three meaningful states: true, false, and unknown. In that case, `NULL` may be semantically valid and you must document what `NULL` means. If a `NULL` boolean creates ambiguity in your application or pipeline, add a NOT NULL constraint and make the tri-state explicit with an enum.

**Data engineering example:**
A user dimension table with flags like `is_active`, `has_verified_email`, `has_consent_marketing`, all typed as `boolean NOT NULL DEFAULT false`.

**Common mistake:**
Storing booleans as `integer` (0 or 1) or `text` (`'Y'`/`'N'`, `'true'`/`'false'`). This is a common pattern in systems migrated from databases that lack a native boolean type. In PostgreSQL, use the native type — it is more expressive, takes less storage, and filters cleanly in queries.

**Indexing note:**
A standard B-tree index on a low-cardinality boolean column (almost all rows are `false`) is usually not selective enough to be useful. A partial index is often more efficient.

```sql
-- Partial index: only index the rare TRUE case
CREATE INDEX idx_users_pending_verification
    ON users (user_id)
    WHERE has_verified_email = FALSE;
```

---

### Date and Time Types

---

### date

**What it is:**
Stores a calendar date (year, month, day) without a time component. Occupies 4 bytes. Range: 4713 BC to 5874897 AD.

**Use it for:**
Birthdates, subscription dates, report dates, partition keys based on calendar dates, and any value where time-of-day precision is neither needed nor meaningful.

**Avoid it when:**
The value represents an event that occurred at a specific time. Truncating a timestamp to a date loses information and can cause incorrect ordering, deduplication, or filtering.

**Data engineering example:**
A subscription dimension with `start_date date` and `end_date date`. A daily reporting aggregate table partitioned by `report_date date`.

**Common mistake:**
Storing dates as `text` in formats like `'2024-01-15'` or `'01/15/2024'`. This prevents date arithmetic, range filtering, and index range scans. It also introduces format inconsistency across rows.

**Indexing note:**
B-tree indexes on `date` support range scans efficiently. Partition pruning on range-partitioned tables works correctly when the partition key is `date`.

```sql
CREATE TABLE dim_date (
    date_key      date     NOT NULL PRIMARY KEY,
    year          smallint NOT NULL,
    month         smallint NOT NULL,
    day           smallint NOT NULL,
    iso_week      smallint NOT NULL,
    is_weekend    boolean  NOT NULL,
    is_holiday    boolean  NOT NULL DEFAULT false
);
```

---

### time

**What it is:**
Stores a time of day without a date component. Also available as `timetz` (time with time zone), though PostgreSQL documentation notes that `timetz` is of limited practical use.

**Use it for:**
Scheduled times, business hours, recurring daily windows, or cron-like schedules where the date is not relevant.

**Avoid it when:**
You need a full timestamp. A `time` without a date is difficult to reason about across days, especially around midnight boundaries or DST transitions.

**Data engineering example:**
A business hours table storing open and close times for each day of the week.

**Common mistake:**
Using `timetz` instead of just `time`. The PostgreSQL documentation itself acknowledges that `timetz` has questionable usefulness, because storing a time zone without a date makes the offset ambiguous with respect to DST.

```sql
CREATE TABLE business_hours (
    location_id   integer NOT NULL,
    day_of_week   smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    opens_at      time    NOT NULL,
    closes_at     time    NOT NULL,
    is_closed     boolean NOT NULL DEFAULT false,
    PRIMARY KEY (location_id, day_of_week)
);
```

---

### timestamp

**What it is:**
Stores a date and time without time zone information. Occupies 8 bytes. When you insert a value, PostgreSQL stores it as-is with no time zone conversion.

**Use it for:**
Timestamps where all data originates from a single, known time zone and no conversion is needed. Internal audit logs in single-region systems, local time representations in legacy schemas, or timestamps that are already normalized to UTC by the application before insertion.

**Avoid it when:**
Data originates from multiple time zones, the system operates across regions, or you cannot guarantee that all producers normalize to UTC before writing. Using `timestamp` in a multi-region system silently discards time zone context, leading to incorrect ordering and aggregations.

**Data engineering example:**
An internal batch processing log table where all timestamps are written by a UTC-normalized scheduler and the team has enforced UTC everywhere at the application level.

**Common mistake:**
Using `timestamp` instead of `timestamptz` and assuming the stored values are UTC. They may not be, depending on the client's `TimeZone` session setting. PostgreSQL does not validate or convert on insert for plain `timestamp`.

```sql
CREATE TABLE batch_job_runs (
    job_run_id    bigint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_name      text      NOT NULL,
    started_at    timestamp NOT NULL,
    finished_at   timestamp,
    status        text      NOT NULL
);
```

---

### timestamptz

**What it is:**
Stores a timestamp with time zone. PostgreSQL normalizes the stored value to UTC internally regardless of the input time zone, and converts it back to the session's time zone on output. Occupies 8 bytes — identical to `timestamp`.

**Use it for:**
All external event timestamps, user activity timestamps, pipeline execution times, API event logs, and any value where the absolute moment in time matters. This should be the default choice for timestamp columns in most systems.

**Avoid it when:**
You are working in a single-time-zone system and the overhead of time zone conversion is a documented bottleneck (which is rare). For most systems, the negligible overhead of UTC normalization is worth the correctness guarantee.

**Data engineering example:**
A clickstream event table receiving events from users across multiple countries. `occurred_at timestamptz` stores the absolute moment correctly regardless of where the event originated.

**Common mistake:**
Confusing `timestamptz` with "storing a time zone." PostgreSQL stores a UTC value, not the original time zone. If you need to preserve the original time zone offset (for example, to display the local time to a user), store it as a separate column.

**Indexing note:**
B-tree indexes on `timestamptz` support efficient range scans. Combined with table partitioning by time range, this is the foundation of most high-volume event table designs.

```sql
CREATE TABLE fact_events (
    event_id       bigint      GENERATED ALWAYS AS IDENTITY,
    user_id        bigint      NOT NULL,
    session_id     uuid        NOT NULL,
    event_type     text        NOT NULL,
    occurred_at    timestamptz NOT NULL,
    properties     jsonb
) PARTITION BY RANGE (occurred_at);
```

---

### interval

**What it is:**
Stores a time duration or span: years, months, days, hours, minutes, seconds, and fractional seconds. Not a point in time, but a difference between two points in time.

**Use it for:**
Session duration, SLA thresholds, time-to-event calculations, TTL values, recurring schedule offsets, and time delta arithmetic.

**Avoid it when:**
You are trying to store a point in time. An `interval` is a relative duration, not an absolute timestamp.

**Data engineering example:**
Calculating session duration as `ended_at - started_at` returns an `interval`. Storing SLA windows like `INTERVAL '24 hours'` or subscription renewal periods like `INTERVAL '1 month'`.

**Common mistake:**
Storing durations as integers (seconds or milliseconds) because `interval` feels unfamiliar. Integer durations are valid, but `interval` allows richer arithmetic and clearer semantics, particularly for mixed-unit durations (e.g., 2 months and 3 days).

```sql
-- Calculate average session duration
SELECT
    AVG(ended_at - started_at) AS avg_session_duration
FROM user_sessions
WHERE ended_at IS NOT NULL;

-- Store SLA thresholds
CREATE TABLE sla_definitions (
    sla_name          text     NOT NULL PRIMARY KEY,
    response_deadline interval NOT NULL,
    resolution_deadline interval NOT NULL
);
```

---

### Identifiers

---

### uuid

**What it is:**
A 128-bit universally unique identifier stored in 16 bytes. PostgreSQL has a native `uuid` type and supports UUID generation via `gen_random_uuid()` (built-in since PostgreSQL 13) or the `uuid-ossp` extension.

**Use it for:**
Primary keys that must be unique across systems, services, or databases without coordination. API resource identifiers, cross-service entity references, distributed system identifiers, and keys where revealing sequential ordering is undesirable.

**Avoid it when:**
You need sequential, ordered inserts and the primary key is purely internal. Random UUIDs (v4) cause B-tree index fragmentation because new values are inserted randomly across the index, not at the end. This leads to index bloat and reduced write performance on large tables.

**Data engineering example:**
A distributed microservices architecture where multiple services create events independently and merge them into a central warehouse. UUID keys prevent collisions without a central sequence coordinator.

**Common mistake:**
Using UUIDv4 as a primary key on a high-write OLTP table without understanding the write amplification caused by random index insertion. UUIDv7 (sequential, timestamp-prefixed) or `bigint` identity columns are better choices for write-heavy tables where global uniqueness is not required.

**Indexing note:**
Standard B-tree indexes on UUIDv4 fragment over time due to random insertion order. Consider UUIDv7 for ordered UUID generation, or store UUIDs as `text` only at the boundary layer and use `bigint` internally — though storing as proper `uuid` type is still more efficient than `text`.

```sql
CREATE TABLE api_requests (
    request_id   uuid        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id      bigint      NOT NULL,
    endpoint     text        NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now()
);
```

---

### serial / bigserial vs Identity Columns

**What they are:**
`serial` and `bigserial` are convenience shorthands that create an integer or bigint column attached to an auto-generated sequence. They are not true types — they are shorthand for `CREATE SEQUENCE` plus `DEFAULT nextval(...)`.

`GENERATED ALWAYS AS IDENTITY` and `GENERATED BY DEFAULT AS IDENTITY` are the SQL-standard equivalent, introduced in PostgreSQL 10, and are the recommended approach for new schemas.

**Use identity columns for:**
Auto-incrementing surrogate primary keys in new schemas. Identity columns are cleaner, more explicit, and better supported by tools and replication than serial pseudo-types.

**Use serial / bigserial when:**
Maintaining compatibility with older schemas or tools that predate identity column support.

**Avoid serial / bigserial in new schemas:**
The `serial` shorthand has several subtle issues: the sequence is not intrinsically tied to the column (it can be dropped independently), `GENERATED ALWAYS AS IDENTITY` prevents accidental manual overrides more safely, and identity columns are the SQL standard.

**Common mistake:**
Using `serial` (4-byte, max ~2.1 billion) instead of `bigserial` or `bigint GENERATED ALWAYS AS IDENTITY` for fact tables. Exhausting a sequence in production is a severe incident.

```sql
-- Preferred: SQL-standard identity column
CREATE TABLE dim_customer (
    customer_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_name text   NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- Legacy: serial shorthand (still valid, not preferred for new schemas)
CREATE TABLE dim_product_legacy (
    product_id   bigserial PRIMARY KEY,
    product_name text NOT NULL
);
```

---

### Semi-Structured Data

---

### json

**What it is:**
Stores JSON as an exact copy of the input text, preserving whitespace, key order, and duplicate keys. No indexing support beyond casting to `jsonb`.

**Use it for:**
Archival scenarios where exact text representation must be preserved, or as an intermediate staging type before transformation to `jsonb`. In practice, `jsonb` is preferred in almost all cases.

**Avoid it when:**
You need to query individual keys, use operators, or create indexes on JSON content. `json` processes the text on every access, making repeated key lookups significantly slower than `jsonb`.

**Data engineering example:**
A raw ingestion table that archives original API responses verbatim for compliance or replay purposes, where the exact text byte-for-byte matters.

**Common mistake:**
Defaulting to `json` instead of `jsonb` because it looks simpler. The distinction matters: `jsonb` is a parsed binary format optimized for querying; `json` is just text with validation.

```sql
-- Archival table preserving exact original payload
CREATE TABLE raw_api_responses (
    response_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    endpoint     text   NOT NULL,
    raw_payload  json   NOT NULL,
    received_at  timestamptz NOT NULL DEFAULT now()
);
```

---

### jsonb

**What it is:**
Stores JSON in a decomposed binary format. Unlike `json`, `jsonb` normalizes key order (last value wins for duplicate keys), does not preserve whitespace, and stores the data in a form optimized for querying. Supports GIN indexing and a rich set of operators.

**Use it for:**
Flexible schema storage, semi-structured attributes, API payloads that need to be queried, entity-attribute-value patterns where the schema varies per row, configuration metadata, and event properties with variable structure.

**Avoid it when:**
The data has a fully known and stable schema. At that point, normalize the structure into typed columns — the type safety, compression, and query performance of proper columns exceeds `jsonb` for structured data. Also avoid `jsonb` for very large JSON documents if only a small subset of keys are queried; the full binary representation must be loaded and parsed.

**Data engineering example:**
An event tracking table where `properties jsonb` stores flexible event-specific attributes. Some events have 3 properties, others have 30. A GIN index on `properties` allows fast lookups by key presence or value.

**Common mistake:**
Storing all data in a single `jsonb` column to avoid defining a schema. This is a schema design failure that defers all data quality problems to query time and makes it impossible for the query planner to use statistics effectively on individual fields.

**Indexing note:**
A GIN index with `jsonb_ops` (the default) supports `@>`, `?`, `?|`, `?&` operators. A GIN index with `jsonb_path_ops` is smaller and faster for `@>` (containment) queries but does not support key-existence operators. Index only the `jsonb` columns where key-level filtering is a genuine query pattern.

```sql
CREATE TABLE event_properties (
    event_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_type  text        NOT NULL,
    occurred_at timestamptz NOT NULL,
    properties  jsonb
);

-- GIN index for key-level and containment queries
CREATE INDEX idx_event_properties_gin
    ON event_properties USING GIN (properties);

-- Query example: find events where properties contain a specific key-value
SELECT event_id, event_type
FROM event_properties
WHERE properties @> '{"campaign_id": "abc123"}';
```

---

### hstore

**What it is:**
A PostgreSQL extension type (`CREATE EXTENSION hstore`) that stores a flat set of key-value pairs where both keys and values are strings. It predates `jsonb` and is simpler, but is limited to one level of depth and string-only values.

**Use it for:**
Flat key-value metadata where keys are strings and values are strings or nulls. Tag storage, configuration metadata, attribute sets where nesting is not needed. In new schemas, `jsonb` is usually the better default unless the flat KV semantics are a deliberate constraint.

**Avoid it when:**
Values may be numeric, boolean, or nested. `hstore` cannot represent those types natively. For most new development, `jsonb` covers the use case with more flexibility.

**Data engineering example:**
Storing arbitrary user-defined tags on an object: `tags hstore` containing `'env => production, team => data-engineering, tier => gold'`.

**Common mistake:**
Using `hstore` in a new schema when `jsonb` was the intended choice. `hstore` requires an explicit extension install and adds a dependency. Confirm it is the right tool before choosing it over `jsonb`.

```sql
CREATE EXTENSION IF NOT EXISTS hstore;

CREATE TABLE resource_tags (
    resource_id   bigint NOT NULL,
    resource_type text   NOT NULL,
    tags          hstore,
    PRIMARY KEY (resource_id, resource_type)
);

-- Query: find resources tagged as production
SELECT resource_id FROM resource_tags
WHERE tags @> 'env => production';
```

---

### Binary

---

### bytea

**What it is:**
Stores binary data as a variable-length byte sequence. PostgreSQL stores it as escaped or hex-encoded text internally, but exposes it as raw bytes to clients. No character set interpretation is applied.

**Use it for:**
Encrypted payloads (storing ciphertext), binary file fragments or thumbnails that genuinely belong in the database, cryptographic hashes, raw binary protocol messages, and HMAC values.

**Avoid it when:**
The binary objects are large files (images, videos, large documents). Storing large objects in `bytea` columns causes table bloat, complicates vacuuming, and performs poorly compared to object storage (S3, GCS) combined with a URL reference stored in the database. PostgreSQL's `lo` (large object) type and TOAST handle large values, but the operational complexity is rarely worth it.

**Data engineering example:**
An encryption key management table storing encrypted DEKs (data encryption keys) as `bytea`. The keys are small (32–64 bytes), referenced frequently, and should live with the database.

**Common mistake:**
Storing large binary files (PDFs, images, video) in `bytea` when they should be in object storage. The rule of thumb: if the binary object is larger than a few hundred kilobytes and you have more than a few thousand rows, use object storage.

```sql
CREATE TABLE encrypted_secrets (
    secret_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    secret_name   text   NOT NULL UNIQUE,
    ciphertext    bytea  NOT NULL,
    key_version   integer NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);
```

---

### Network Types

---

### inet

**What it is:**
Stores an IPv4 or IPv6 host address, optionally with a subnet mask in CIDR notation. PostgreSQL validates the address on insert and provides network-aware operators and functions.

**Use it for:**
Storing IP addresses from web server logs, authentication events, access control tables, and network audit logs. The `inet` type supports operators like `<<` (is contained within subnet), `>>` (contains), and allows subnet arithmetic that is impossible with plain `text`.

**Avoid it when:**
You only need to store an IP string for display purposes and never query it by subnet, range, or network membership. In that case, `text` avoids the dependency on network type understanding, though `inet` is still preferable for correctness.

**Data engineering example:**
A web access log table where `client_ip inet` allows queries like "find all requests from the corporate IP range" using subnet containment operators.

**Common mistake:**
Storing IP addresses as `text`. This is valid but prevents subnet-level filtering, makes IP validation the application's responsibility, and misses PostgreSQL's network operator support.

**Indexing note:**
GiST indexes on `inet` support subnet containment queries efficiently. B-tree indexes support equality and ordering.

```sql
CREATE TABLE access_logs (
    log_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_ip   inet        NOT NULL,
    user_agent  text,
    requested_at timestamptz NOT NULL,
    status_code smallint    NOT NULL
);

-- Find all requests from a specific subnet
SELECT COUNT(*) FROM access_logs
WHERE client_ip << '10.0.0.0/8';
```

---

### cidr

**What it is:**
Similar to `inet` but stores a network address where the host bits must be zero. It represents a network block, not a host-within-a-network.

**Use it for:**
Firewall rules, VPC CIDR allocations, allowed/blocked network ranges, and routing tables where the stored value is a network address, not a specific host.

**Avoid it when:**
You are storing an individual host address. Use `inet` for hosts. `cidr` will reject an input like `192.168.1.5/24` because the host bits are non-zero.

**Data engineering example:**
A network security table storing allowed IP ranges for API access: `allowed_cidr cidr NOT NULL` with values like `10.20.30.0/24`.

```sql
CREATE TABLE ip_allowlist (
    allowlist_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    allowed_cidr  cidr    NOT NULL,
    description   text,
    created_at    timestamptz NOT NULL DEFAULT now()
);
```

---

### macaddr / macaddr8

**What it is:**
`macaddr` stores a 6-byte MAC address (EUI-48, e.g., `08:00:2b:01:02:03`). `macaddr8` stores an 8-byte MAC address (EUI-64). Both validate the format on input and provide a dedicated operator set.

**Use it for:**
Device inventory tables, network audit logs, DHCP lease tables, hardware asset management, and any system that tracks physical network devices.

**Avoid it when:**
You are storing values that look like MAC addresses but are not (synthetic device IDs in some systems use MAC-like formats for legacy reasons). Verify the semantic meaning before using the native type.

**Data engineering example:**
A device inventory table in a network operations context: `mac_address macaddr NOT NULL UNIQUE`.

```sql
CREATE TABLE network_devices (
    device_id   integer  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mac_address macaddr  NOT NULL UNIQUE,
    ip_address  inet,
    hostname    text,
    first_seen  timestamptz NOT NULL DEFAULT now()
);
```

---

### Arrays

---

### text[] / integer[] / general array types

**What they are:**
PostgreSQL supports one-dimensional and multi-dimensional arrays of any base type. A `text[]` column stores a variable-length array of text values. `integer[]` stores an array of integers. Arrays are a first-class PostgreSQL type with dedicated operators and functions.

**Use them for:**
Storing multiple values of the same type that belong to a single row: tags, labels, permission lists, search keyword sets, multi-value attributes where the set is used together and not queried independently. PostgreSQL's `@>` (contains), `<@` (contained by), `&&` (overlap), and `ANY()` operators make array queries practical.

**Avoid them when:**
You need to query, join, or aggregate on individual array elements frequently. Arrays are not normalized — each element is not independently indexable without unnesting. Analytics that require counting occurrences, grouping, or joining on array elements should use normalized tables or `jsonb` depending on the structure.

**Data engineering example:**
A content table with `tags text[] NOT NULL DEFAULT '{}'` storing a list of editorial tags. A GIN index on the array allows efficient `@>` (contains-tag) queries.

**Common mistake:**
Using arrays for data that should be in a child table. If you find yourself frequently unnesting an array to join it, filter it, or aggregate it, that is a signal the data belongs in a separate relation.

**Indexing note:**
GIN indexes on array columns support containment and overlap operators. B-tree indexes on arrays only support equality on the entire array, which is rarely useful.

```sql
CREATE TABLE articles (
    article_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title        text   NOT NULL,
    tags         text[] NOT NULL DEFAULT '{}',
    published_at timestamptz
);

CREATE INDEX idx_articles_tags_gin ON articles USING GIN (tags);

-- Find all articles tagged 'postgresql'
SELECT article_id, title
FROM articles
WHERE tags @> ARRAY['postgresql'];
```

---

### Range and Multirange Types

---

### int4range / int8range

**What they are:**
`int4range` represents a range of `integer` values. `int8range` represents a range of `bigint` values. Both support inclusive `[` and exclusive `)` bounds.

**Use them for:**
Version ranges, partition band definitions, integer ID windows, score ranges, and any domain where a contiguous range of integers must be stored and queried for containment or overlap.

**Avoid them when:**
You are storing a single point value, not a range. Also avoid when the range semantics are not genuinely contiguous (a list of specific IDs is not a range).

**Data engineering example:**
A feature flag table where flags apply to users within a specific ID range: `eligible_user_ids int8range NOT NULL`.

```sql
CREATE TABLE feature_flags (
    flag_id             integer   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    flag_name           text      NOT NULL UNIQUE,
    eligible_user_range int8range,
    is_active           boolean   NOT NULL DEFAULT true
);

-- Check if a user is in the eligible range
SELECT flag_name FROM feature_flags
WHERE eligible_user_range @> 12345678::bigint
  AND is_active = true;
```

---

### numrange

**What it is:**
A range of `numeric` values. Useful for exact decimal ranges.

**Use it for:**
Price bands, salary ranges, score thresholds, numeric bracket definitions, and any range over exact decimal values.

**Data engineering example:**
A pricing tier table where each tier covers a revenue range: `revenue_range numrange NOT NULL`.

```sql
CREATE TABLE pricing_tiers (
    tier_name     text     NOT NULL PRIMARY KEY,
    revenue_range numrange NOT NULL,
    discount_rate numeric(5,4) NOT NULL,
    EXCLUDE USING GIST (revenue_range WITH &&)
);
```

---

### tsrange / tstzrange

**What they are:**
`tsrange` stores a range of `timestamp` values (without time zone). `tstzrange` stores a range of `timestamptz` values. For most real-world use cases, `tstzrange` is preferred for the same reasons `timestamptz` is preferred over `timestamp`.

**Use them for:**
Session windows, billing periods, subscription validity windows, SLA measurement windows, scheduled maintenance windows, and any domain involving time intervals with defined start and end.

**Avoid them when:**
You only need a single timestamp. Do not model a point-in-time as a degenerate range.

**Data engineering example:**
A subscription table where `valid_during tstzrange NOT NULL` stores the active period. An exclusion constraint prevents overlapping subscriptions for the same user.

**Indexing note:**
GiST indexes on range types support containment, overlap, and adjacency queries efficiently. For high-volume event windowing, GiST-indexed range columns perform well in temporal queries.

```sql
CREATE TABLE subscriptions (
    subscription_id bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id         bigint      NOT NULL,
    plan_name       text        NOT NULL,
    valid_during    tstzrange   NOT NULL,
    EXCLUDE USING GIST (user_id WITH =, valid_during WITH &&)
);

-- Find the active subscription for a user at a given time
SELECT plan_name FROM subscriptions
WHERE user_id = 42
  AND valid_during @> now();
```

---

### daterange

**What it is:**
A range of `date` values. Useful when time-of-day precision is not needed and calendar date boundaries define the range.

**Use it for:**
Contract validity periods, promotion windows, fiscal periods, holiday date ranges, and any date-bounded interval that does not need sub-day precision.

```sql
CREATE TABLE promotions (
    promotion_id   integer   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promotion_name text      NOT NULL,
    active_period  daterange NOT NULL,
    discount_pct   numeric(5,2) NOT NULL
);

-- Find promotions active today
SELECT promotion_name, discount_pct
FROM promotions
WHERE active_period @> CURRENT_DATE;
```

---

### Other Useful PostgreSQL Types

---

### enum

**What it is:**
A user-defined type consisting of a static, ordered list of labeled values. Enums are stored efficiently (4 bytes per value) and enforced at the type level.

**Use it for:**
Stable, low-cardinality categorical values with a controlled vocabulary: order status (`pending`, `confirmed`, `shipped`, `delivered`, `cancelled`), payment method, priority level, or pipeline status. Enum values are type-safe, storage-efficient, and self-documenting.

**Avoid it when:**
The list of values changes frequently, is managed by business users, or must be joined with other data. Adding a value to an enum requires `ALTER TYPE ... ADD VALUE`, which is a schema change requiring deployment coordination. Removing or reordering values requires even more care. For frequently changing categories, a lookup table is more maintainable.

**Data engineering example:**
A pipeline execution log with `status pipeline_status NOT NULL` where `pipeline_status` is an enum with values `queued`, `running`, `succeeded`, `failed`, `skipped`.

**Common mistake:**
Using enum for values that evolve with business requirements. Enum changes require DDL, which must be coordinated with deployments and may affect clients reading the type definition.

```sql
CREATE TYPE order_status AS ENUM (
    'pending', 'confirmed', 'processing',
    'shipped', 'delivered', 'cancelled', 'refunded'
);

CREATE TABLE orders (
    order_id    bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     bigint       NOT NULL,
    status      order_status NOT NULL DEFAULT 'pending',
    created_at  timestamptz  NOT NULL DEFAULT now()
);
```

---

### money

**What it is:**
A PostgreSQL-native type for monetary values. It stores a currency amount as a fixed-point number with 2 decimal places, tied to the database's `lc_monetary` locale setting.

**Use it for:**
Practically nothing in new schema design. The `money` type is included here as a warning type.

**Avoid it when:**
Building any serious financial data system. The `money` type has several known problems: it is locale-dependent (behavior changes with `lc_monetary`), it does not support multiple currencies, it has poor interoperability with arithmetic operations and type casts, and it cannot represent values requiring more than 2 decimal places. Replication and migration scenarios with different locale settings can silently produce incorrect values.

**Data engineering example:**
There is no recommended data engineering use case for `money`. Use `numeric(18, 4)` instead.

**Common mistake:**
Choosing `money` for financial columns because the name seems appropriate. Prefer `numeric` with explicit precision and scale.

```sql
-- Avoid this:
-- price money NOT NULL

-- Prefer this:
CREATE TABLE product_prices (
    product_id  integer        NOT NULL,
    currency    char(3)        NOT NULL,
    amount      numeric(18, 4) NOT NULL,
    valid_from  timestamptz    NOT NULL,
    PRIMARY KEY (product_id, currency, valid_from)
);
```

---

### Domain Types

**What they are:**
User-defined types based on an existing base type with optional constraints, default values, or collations. A domain is a named type that reuses a base type's storage and behavior but layers additional validation.

**Use them for:**
Reusable constraint definitions that must be enforced consistently across multiple tables. A `positive_amount` domain based on `numeric(18,4) CHECK (VALUE > 0)` can be applied to dozens of columns without repeating the constraint definition. Domains also communicate intent clearly in schema definitions.

**Avoid them when:**
The constraint is table-specific and unlikely to be reused. In that case, a column-level CHECK constraint is sufficient and simpler.

**Data engineering example:**
A `percentage` domain defined as `numeric(5,4) CHECK (VALUE BETWEEN 0 AND 1)` used across tax rates, discount rates, and commission rates.

**Common mistake:**
Defining domains but not using them consistently, leaving some columns as bare `numeric` and others as the domain type. The value of domains comes from consistency.

```sql
CREATE DOMAIN positive_amount AS numeric(18, 4)
    CHECK (VALUE > 0);

CREATE DOMAIN percentage AS numeric(5, 4)
    CHECK (VALUE BETWEEN 0 AND 1);

CREATE DOMAIN email_address AS text
    CHECK (VALUE ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');

CREATE TABLE commissions (
    commission_id   bigint          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_id         bigint          NOT NULL,
    agent_id        bigint          NOT NULL,
    sale_amount     positive_amount NOT NULL,
    commission_rate percentage      NOT NULL,
    commission_due  positive_amount NOT NULL
);
```

---

## Important Comparisons

---

### text vs varchar vs char

| Characteristic | text | varchar(n) | char(n) |
|---|---|---|---|
| Length limit | None | n characters max | Exactly n characters |
| Storage | Variable | Variable | Fixed (blank-padded) |
| Performance | Identical to varchar | Identical to text | Slight overhead from padding |
| Best use | Default string type | Meaningful length constraint | Fixed-length codes |
| Gotcha | None | Changing n requires ALTER TABLE | Trailing space padding causes subtle bugs |

**Recommendation:** Default to `text`. Use `varchar(n)` when a maximum length is a real business constraint. Use `char(n)` only for codes with a guaranteed fixed width.

---

### timestamp vs timestamptz

| Characteristic | timestamp | timestamptz |
|---|---|---|
| Time zone awareness | None — stores as-is | Converts to UTC on insert, converts to session TZ on output |
| Storage size | 8 bytes | 8 bytes |
| Best use | Single-TZ systems with UTC enforced at application | All external events, multi-region systems |
| Risk | Silent data corruption when clients are in different TZs | None — time zone semantics are explicit |

**Recommendation:** Default to `timestamptz` for all new schemas. The cost is zero and the correctness guarantee is significant.

---

### json vs jsonb

| Characteristic | json | jsonb |
|---|---|---|
| Storage format | Exact text copy | Decomposed binary |
| Key order preserved | Yes | No (sorted) |
| Duplicate key behavior | Preserved (last wins on query) | Last value wins, others discarded |
| Query performance | Slow (re-parses on every access) | Fast (binary access) |
| GIN index support | No | Yes |
| Operator richness | Limited | Full |

**Recommendation:** Always use `jsonb` unless exact text preservation is a documented requirement.

---

### numeric vs double precision

| Characteristic | numeric | double precision |
|---|---|---|
| Precision | Exact | Approximate (~15 significant digits) |
| Storage | Variable (2–34 bytes) | 8 bytes fixed |
| Performance | Slow (software arithmetic) | Fast (CPU FPU) |
| Financial use | Required | Forbidden |
| Scientific use | Usually unnecessary | Appropriate |

**Recommendation:** Use `numeric` for financial values. Use `double precision` for scientific approximations, coordinates, and ML features.

---

### serial / bigserial vs Identity Columns

| Characteristic | serial / bigserial | GENERATED ALWAYS / BY DEFAULT AS IDENTITY |
|---|---|---|
| SQL standard | No | Yes (SQL:2003) |
| Sequence dependency | Implicit (can be dropped) | Intrinsic to column |
| Manual override | Allowed by default | Controlled by `ALWAYS` vs `BY DEFAULT` |
| Recommendation | Legacy schemas only | All new schemas |

**Recommendation:** Use `GENERATED ALWAYS AS IDENTITY` for new schemas. Use `bigint` as the base type for high-volume tables.

---

### uuid vs bigint as Primary Key

| Characteristic | uuid (v4) | bigint identity |
|---|---|---|
| Global uniqueness | Yes (without coordination) | No (local sequence) |
| Storage | 16 bytes | 8 bytes |
| Insert performance | Degrades over time (random B-tree insertion) | Consistent (sequential insertion) |
| Cross-system use | Ideal | Requires coordination |
| Readability | Poor | Good |
| Index fragmentation | High (UUIDv4) | None |

**Recommendation:** Use `bigint` identity for internal surrogate keys. Use `uuid` (preferably UUIDv7 for ordering) for cross-system identifiers or external-facing keys.

---

### Arrays vs Normalized Relational Design

| Consideration | Arrays | Normalized Child Table |
|---|---|---|
| Write simplicity | High | Moderate |
| Query simplicity on whole set | High | Moderate (requires join) |
| Analytics on elements | Poor (requires unnesting) | Excellent (direct aggregation) |
| Foreign key constraints | Not possible on elements | Full referential integrity |
| Element-level indexing | Limited (GIN on whole column) | Full index support |

**Recommendation:** Use arrays for read-together, write-together sets of scalar values (tags, labels). Use normalized tables when individual elements require counting, joining, filtering, or updating independently.

---

### enum vs Lookup Table

| Consideration | enum | Lookup table |
|---|---|---|
| Adding values | Requires `ALTER TYPE` (DDL) | `INSERT` (DML) |
| Removing values | Complex (requires type recreation) | `DELETE` (with FK considerations) |
| Business user management | Not possible without schema access | Possible via application |
| Storage efficiency | Excellent (4 bytes) | Moderate (FK integer or text) |
| Type safety | Enforced at DB level | Enforced via FK constraint |

**Recommendation:** Use `enum` for values that are part of the application's code contract and change only with deployments. Use a lookup table for values managed by operations or business users.

---

### money vs numeric

**Do not use `money` in new schemas.**

The `money` type is locale-dependent, has poor interoperability with arithmetic and type conversions, cannot represent multiple currencies, and is limited to 2 decimal places. Use `numeric(18, 4)` with a separate `currency char(3)` column.

---

### date vs timestamp

Use `date` when time-of-day is irrelevant: birthdays, report periods, calendar dimensions, contract start/end dates.

Use `timestamptz` when the absolute moment matters: event timestamps, audit trails, pipeline execution times.

Never store a date as a `timestamp` with midnight time just because `timestamp` "feels more precise." The extra resolution adds ambiguity (is midnight UTC? Local time?) and wastes 4 bytes.

---

## Practical Rules for Data Engineers

**1. Never store dates as text.**
Dates in text columns cannot be compared with `<` and `>`, cannot be range-scanned by indexes, and accumulate format inconsistencies over time. Use `date` or `timestamptz`.

**2. Prefer `timestamptz` for all event timestamps where time zone matters.**
The storage cost is identical to `timestamp`. The correctness guarantee is significant. Default to `timestamptz` unless you have a documented reason not to.

**3. Prefer `jsonb` over `json` for all semi-structured data that will be queried.**
`json` is text storage with syntax validation. `jsonb` is a queryable binary format. There is rarely a reason to use `json` in a production schema.

**4. Use `numeric` for all financial values.**
Floating-point arithmetic produces incorrect results for decimal values. This is not a precision issue — it is a representation issue. `0.1` cannot be represented exactly in binary floating point. Use `numeric` for any value involving money, rates, or exact decimal arithmetic.

**5. Use `bigint` for primary keys on large fact tables.**
`integer` exhausts at approximately 2.1 billion. High-volume event tables can reach this within months. Use `bigint` identity columns for all fact table surrogate keys.

**6. Be deliberate about `jsonb`.**
`jsonb` is a tool for genuinely variable schema, not an escape from schema design. Columns with known, stable structure should be typed columns. Overusing `jsonb` moves data quality enforcement out of the database.

**7. Be careful with arrays in analytics workloads.**
Arrays are convenient for ingestion but difficult for analytics. Aggregating, counting, or joining on array elements requires `unnest()`, which adds complexity and can produce large intermediate result sets. Evaluate whether a child table serves the query patterns better.

**8. Use range types for contiguous intervals.**
When a domain involves a start and end value of the same type, a range type is cleaner, more expressive, and enables GiST-indexed overlap and containment queries that `BETWEEN` cannot match efficiently.

**9. Consider domain types for frequently reused constraints.**
Constraints defined once as a domain type are applied consistently, documented in the type name, and maintained in one place. A `positive_amount` domain is more expressive than a repeated `CHECK (amount > 0)` across twenty tables.

**10. Index thoughtfully before adding `jsonb`, arrays, or range types.**
These types have specific index requirements: GIN for `jsonb` and arrays, GiST for range types and `inet`. An unindexed `jsonb` column queried by key value will produce a sequential scan. Plan your indexes before choosing a type.

**11. Avoid `varchar(255)` as a default.**
In PostgreSQL, `varchar(255)` and `text` have identical performance and storage. The `(255)` adds no benefit unless 255 is a real semantic limit. Use `text` as the default and add a constraint when a limit is meaningful.

**12. Avoid `money` in new schemas.**
Use `numeric(18, 4)` instead. The `money` type is locale-dependent and poorly interoperable.

**13. Use `boolean NOT NULL` with explicit defaults.**
Nullable booleans create three-valued logic that complicates application code and query logic. Add `NOT NULL DEFAULT false` unless `NULL` carries a distinct, documented meaning.

**14. Align type choices to downstream consumers.**
BI tools, dbt models, and query engines interpret types differently. A `timestamptz` column in Redshift Spectrum, BigQuery external tables, or Metabase renders differently than a `text` column containing the same value. Type choices affect the entire data platform, not just the PostgreSQL layer.

---

## Final Cheat Sheet

**If your data is X, consider Y**

| Your Data | Recommended Type | Notes |
|---|---|---|
| User-generated text | `text` | Default string type; no length constraint needed |
| Name or label with max length | `varchar(n)` | Only if the limit is a real constraint |
| Fixed-width code (ISO, legacy) | `char(n)` | Confirm fixed length; watch for padding |
| Binary flag | `boolean NOT NULL DEFAULT false` | Avoid nullable booleans |
| Whole number (small range) | `smallint` | Only when range is confirmed bounded |
| General integer ID or count | `integer` | Default for bounded tables |
| Large fact table ID, event count | `bigint` or `bigint GENERATED ALWAYS AS IDENTITY` | Default for high-volume tables |
| Exact financial amount or rate | `numeric(18, 4)` | Never use floating point for money |
| Scientific approximation, score | `double precision` | When FP approximation is acceptable |
| Geographic coordinate | `double precision` | Latitude/longitude |
| Calendar date (no time) | `date` | Birthdate, report date, contract date |
| Time of day (no date) | `time` | Business hours, scheduled slots |
| Event timestamp (multi-region) | `timestamptz` | Default for all external events |
| Event timestamp (UTC, single-TZ) | `timestamp` | Only when UTC enforced at application |
| Duration or time delta | `interval` | Session length, SLA window |
| Auto-increment surrogate key | `bigint GENERATED ALWAYS AS IDENTITY` | Prefer over `bigserial` |
| Cross-system unique identifier | `uuid` | Use UUIDv7 if insert ordering matters |
| Raw API payload | `jsonb` | With GIN index if queried by key |
| Exact JSON text preservation | `json` | Archival only; prefer `jsonb` otherwise |
| Flat key-value tags | `hstore` (extension) or `jsonb` | `jsonb` for new schemas unless flat KV is a constraint |
| Raw binary / encrypted payload | `bytea` | Files > a few hundred KB → object storage |
| IPv4/IPv6 host address | `inet` | Enables subnet operators |
| Network address block | `cidr` | VPC ranges, firewall rules |
| MAC address | `macaddr` / `macaddr8` | Device inventory |
| Multi-value tag set | `text[]` with GIN index | If analytics on elements: normalize instead |
| Integer range or band | `int4range` / `int8range` | Version ranges, ID windows |
| Date interval | `daterange` | Contract periods, fiscal periods |
| Timestamp window | `tstzrange` | Sessions, billing periods, SLAs |
| Stable categorical value | `enum` or lookup table | Enum for code-contract values; lookup table for business-managed values |
| Monetary value | `numeric(18, 4)` | Never `money` |
| Reusable validated constraint | Domain type | `positive_amount`, `percentage`, `email_address` |

---

## Further Reading

All references are to the official PostgreSQL documentation.

- **PostgreSQL Data Types (Chapter 8)**
  https://www.postgresql.org/docs/current/datatype.html

- **Numeric Types**
  https://www.postgresql.org/docs/current/datatype-numeric.html

- **Character Types**
  https://www.postgresql.org/docs/current/datatype-character.html

- **Date/Time Types**
  https://www.postgresql.org/docs/current/datatype-datetime.html

- **Boolean Type**
  https://www.postgresql.org/docs/current/datatype-boolean.html

- **Binary Data Types (bytea)**
  https://www.postgresql.org/docs/current/datatype-binary.html

- **Network Address Types**
  https://www.postgresql.org/docs/current/datatype-net-types.html

- **JSON Types**
  https://www.postgresql.org/docs/current/datatype-json.html

- **Arrays**
  https://www.postgresql.org/docs/current/arrays.html

- **Range Types**
  https://www.postgresql.org/docs/current/rangetypes.html

- **Multirange Types**
  https://www.postgresql.org/docs/current/rangetypes.html#RANGETYPES-BUILTIN

- **Enumerated Types**
  https://www.postgresql.org/docs/current/datatype-enum.html

- **Domain Types**
  https://www.postgresql.org/docs/current/domains.html

- **UUID Type**
  https://www.postgresql.org/docs/current/datatype-uuid.html

- **Composite Types**
  https://www.postgresql.org/docs/current/rowtypes.html

- **Index Types (B-tree, GIN, GiST, BRIN)**
  https://www.postgresql.org/docs/current/indexes-types.html

- **hstore Extension**
  https://www.postgresql.org/docs/current/hstore.html

- **pg_trgm Extension (trigram indexes for text search)**
  https://www.postgresql.org/docs/current/pgtrgm.html

- **Date/Time Functions and Operators**
  https://www.postgresql.org/docs/current/functions-datetime.html

- **JSON Functions and Operators**
  https://www.postgresql.org/docs/current/functions-json.html

- **Network Address Functions and Operators**
  https://www.postgresql.org/docs/current/functions-net.html

- **Range Functions and Operators**
  https://www.postgresql.org/docs/current/functions-range.html

- **PostgreSQL 10 Identity Columns (release notes)**
  https://www.postgresql.org/docs/10/sql-createtable.html

---

*This guide covers PostgreSQL behavior as documented for PostgreSQL 15 and 16. Verify version-specific behavior — particularly for identity columns (10+), `gen_random_uuid()` built-in (13+), and multirange types (14+) — against your target PostgreSQL version.*
