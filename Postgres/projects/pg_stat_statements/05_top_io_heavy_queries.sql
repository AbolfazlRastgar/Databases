-- ============================================================
-- Script   : 05_top_io_heavy_queries.sql
-- Purpose  : Find queries with high shared block I/O activity
-- Read-only : Yes
-- ============================================================
-- What it answers:
--   Which queries are reading or writing the most data blocks?
--
-- Why this matters:
--   Block-level I/O is often the underlying cause of slow queries.
--   High shared_blks_read means data had to be fetched from disk
--   (or the OS cache) rather than from PostgreSQL's shared buffers.
--   High shared_blks_written means the query is generating a lot
--   of dirty pages.
--
--   Temp block usage (temp_blks_read / temp_blks_written) indicates
--   sort or hash operations that exceeded work_mem and spilled to
--   disk — a common cause of unexpectedly slow queries.
--
-- Note:
--   blk_read_time and blk_write_time are only populated when
--   track_io_timing = on in postgresql.conf. Otherwise they show 0.
-- ============================================================

SELECT
    pss.userid::regrole                                         AS db_user,
    pss.dbid::regdatabase                                       AS database_name,
    pss.calls,
    pss.shared_blks_hit,
    pss.shared_blks_read,
    pss.shared_blks_written,
    pss.shared_blks_dirtied,
    pss.temp_blks_read,
    pss.temp_blks_written,
    round(pss.blk_read_time::numeric, 2)                        AS blk_read_ms,
    round(pss.blk_write_time::numeric, 2)                       AS blk_write_ms,
    round(pss.total_exec_time::numeric, 2)                      AS total_exec_ms,
    round(pss.mean_exec_time::numeric, 2)                       AS mean_exec_ms,
    -- Cache hit ratio for this query
    round(
        pss.shared_blks_hit::numeric /
        nullif(pss.shared_blks_hit + pss.shared_blks_read, 0) * 100,
        2
    )                                                           AS cache_hit_pct,
    left(pss.query, 200)                                        AS query_text
FROM pg_stat_statements pss
WHERE (pss.shared_blks_read + pss.shared_blks_written + pss.temp_blks_written) > 0
ORDER BY (pss.shared_blks_read + pss.temp_blks_written) DESC
LIMIT 20;

-- ============================================================
-- cache_hit_pct: a low value (e.g. below 90%) for a frequently
-- called query suggests it is not benefiting from shared buffers
-- and is reading from disk regularly.
--
-- High temp_blks_written with no corresponding index can often
-- be resolved by adding an index or increasing work_mem for
-- the specific workload.
--
-- To enable I/O timing:
--   ALTER SYSTEM SET track_io_timing = on;
--   SELECT pg_reload_conf();
--
-- For PostgreSQL 12 and earlier, replace:
--   total_exec_time ->  total_time
--   mean_exec_time  ->  mean_time
-- ============================================================
