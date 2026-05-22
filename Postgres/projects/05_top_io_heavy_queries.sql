-- ============================================================
-- Script   : 05_top_io_heavy_queries.sql
-- Purpose  : Queries with the most block-level I/O activity
-- Read-only : Yes
-- ============================================================
-- Use this when: disk or I/O appears to be a bottleneck,
-- or when queries are slower than their execution plan suggests.
--
-- shared_blks_read : blocks fetched from disk or OS cache
--                    (not served from shared_buffers)
-- shared_blks_hit  : blocks served from shared_buffers (good)
-- temp_blks_written: sort or hash operations that spilled to
--                    disk due to insufficient work_mem
--
-- cache_hit_pct: percentage of block accesses served from
-- shared_buffers. A low value for a frequent query is a signal
-- worth investigating.
--
-- blk_read_time / blk_write_time are only populated when
-- track_io_timing = on. If both show 0, I/O timing is not
-- enabled. It can be enabled without a restart:
--   ALTER SYSTEM SET track_io_timing = on;
--   SELECT pg_reload_conf();
-- This requires superuser. Confirm with your DBA before changing.
--
-- Column note (PostgreSQL version differences):
--   PG 13+  : total_exec_time, mean_exec_time
--   PG 12   : total_time, mean_time
-- ============================================================

SELECT
    pss.userid::regrole                                            AS db_user,
    pss.dbid::regdatabase                                         AS database_name,
    pss.calls,
    pss.shared_blks_hit,
    pss.shared_blks_read,
    pss.shared_blks_dirtied,
    pss.shared_blks_written,
    pss.temp_blks_read,
    pss.temp_blks_written,
    round(pss.blk_read_time::numeric,  2)                         AS blk_read_ms,
    round(pss.blk_write_time::numeric, 2)                         AS blk_write_ms,
    round(
        pss.shared_blks_hit::numeric
        / nullif(pss.shared_blks_hit + pss.shared_blks_read, 0) * 100
    , 2)                                                          AS cache_hit_pct,
    round(pss.total_exec_time::numeric, 2)                        AS total_exec_ms,
    round(pss.mean_exec_time::numeric,  2)                        AS mean_exec_ms,
    left(pss.query, 200)                                          AS query_text
FROM pg_stat_statements pss
WHERE (pss.shared_blks_read + pss.temp_blks_written) > 0
ORDER BY (pss.shared_blks_read + pss.temp_blks_written) DESC
LIMIT 20;
