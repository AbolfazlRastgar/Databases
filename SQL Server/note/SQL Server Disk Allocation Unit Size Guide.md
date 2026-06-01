

# SQL Server Disk Allocation Unit Size Guide

A practical reference for DBAs, Database Engineers, Data Engineers, and infrastructure teams working with production SQL Server deployments on Windows/NTFS.

---

## TL;DR

For most SQL Server workloads on NTFS, **64 KB allocation unit size** is the widely accepted default for data, log, and backup volumes. FILESTREAM volumes require additional consideration based on actual file-size distribution. Decide before formatting — changing allocation unit size requires reformatting the volume and migrating data.

---

## Recommended Defaults

| Volume Type | Typical I/O Pattern               | Recommended Allocation Unit Size                | Notes                                                                                             |
| ----------- | --------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Data        | Mixed random/sequential           | 64 KB                                           | Aligns with SQL Server extent size (8 pages × 8 KB)                                               |
| Log         | Sequential writes                 | 64 KB                                           | Practical default; log I/O is stream-based, not extent-based — latency and throughput matter more |
| Backup      | Large sequential reads/writes     | 64 KB                                           | Reasonable default; validate against backup platform, dedup/compression, and vendor guidance      |
| FILESTREAM  | Depends on file size distribution | 64 KB for large BLOBs; evaluate for small files | Profile real file-size distribution — wasted space is significant with many small files           |

---

## Why 64 KB Is Common for SQL Server

SQL Server uses **8 KB data pages**. Eight consecutive pages form a **64 KB extent**, which is the unit SQL Server uses for sequential read and write operations — table scans, index builds, bulk loads, checkpoint flushes, and read-ahead I/O.

Formatting data volumes with a 64 KB NTFS allocation unit aligns the filesystem's storage granularity with SQL Server's extent-based I/O. This reduces fragmentation at the filesystem level and avoids the overhead of multiple cluster allocations per extent during sequential operations.

This alignment argument applies specifically to **data files**. For log and backup volumes, 64 KB is still a practical default, but for different reasons covered in the sections below.

> **Note:** Allocation unit size is not the same as sector size or partition alignment. See [Common Mistakes](#common-mistakes).

> **Reference:** [Disk Partition Alignment Best Practices for SQL Server](https://techcommunity.microsoft.com/t5/sql-server-blog/disk-partition-alignment-best-practices-for-sql-server/ba-p/383853) — Microsoft SQL Server Blog

---

## Data Files

SQL Server data volumes (`.mdf`, `.ndf`) experience a **mixed I/O pattern**: random reads driven by OLTP queries, index seeks, and buffer pool page requests; sequential reads and writes during checkpoint operations, table scans, index builds, and bulk load activity.

Key infrastructure considerations:

- 64 KB allocation unit aligns with SQL Server's extent size, reducing filesystem fragmentation for large database files and minimizing cluster allocation overhead during sequential I/O.
- Random single-page I/O (8 KB) is managed at the SQL Server layer. The filesystem cluster size does not change SQL Server's page size — it affects how contiguous disk space is allocated, not how SQL Server reads individual pages.
- Keep data files on dedicated volumes, separate from the OS, page file, log files, and backup targets.

---

## Log Files

Transaction log files (`.ldf`) are written **sequentially** and are **highly latency-sensitive**. SQL Server writes log records as a stream and waits for confirmed write completion before a transaction commit is acknowledged.

Key infrastructure considerations:

- Log writes are stream-based, not extent-based. SQL Server's log manager does not write in 64 KB extents. 64 KB allocation unit is a practical default for log volumes because larger cluster sizes reduce allocation overhead as the log file grows and are appropriate for large, sequential write patterns — but the extent alignment argument does not apply here.
- What determines log volume performance: **write latency stability** and **consistent sequential throughput**. This depends on the underlying storage tier and I/O path, not on cluster size. Dedicated storage with a write-optimized path (NVMe, battery-backed write cache, dedicated spindles) matters far more than allocation unit size.
- Avoid sharing the log volume I/O path with data, backup, tempdb, or other workloads. Shared I/O contention can introduce commit latency variability.

---

## Backup Files

Backup volumes are dominated by **large sequential writes** (during backup operations) and **large sequential reads** (during restore). Files are typically large — often tens to hundreds of gigabytes or more.

Key infrastructure considerations:

- 64 KB is a reasonable default for backup volumes on local NTFS. The large sequential I/O pattern suits a larger cluster size.
- Backup target design introduces variables that can override the NTFS cluster size decision:
  - **Compression and deduplication** (storage-level, OS-level, or backup software-level) can alter effective block sizes and access patterns.
  - **Network storage (NAS/SMB/NFS)** has its own block transfer characteristics independent of the local NTFS cluster size.
  - **Object storage and cloud backup targets** do not use NTFS — allocation unit size is irrelevant for those targets.
  - **Backup software and appliance vendors** (Veeam, Commvault, Rubrik, Veritas, etc.) often publish specific storage formatting guidance. Follow vendor documentation when it exists.

---

## FILESTREAM

FILESTREAM stores BLOB data as individual files in the Windows filesystem rather than inside SQL Server data pages. The optimal cluster size depends on the **actual size distribution of the stored objects**.

Key infrastructure considerations:

- **Large BLOBs (documents, images, video, large binaries):** 64 KB allocation unit is generally appropriate. The per-file overhead is small relative to file size.
- **Many small files (thumbnails, short-text blobs, small attachments):** Each file, regardless of its actual size, consumes a minimum of one full cluster on disk. A 3 KB file on a 64 KB cluster volume occupies 64 KB. At millions of files, the wasted space is material and should be measured, not assumed.
- As file count scales, NTFS MFT (Master File Table) growth, directory entry overhead, and filesystem metadata management also become relevant — independent of cluster size.
- **Profile the actual file-size distribution before formatting.** A histogram of FILESTREAM object sizes will tell you whether 64 KB is appropriate or whether a smaller cluster size reduces waste without introducing unacceptable fragmentation.

---

## Practical Checklist Before Formatting

- [ ] Define the volume role (data, log, backup, FILESTREAM, tempdb) before formatting
- [ ] Confirm the appropriate allocation unit size for that role
- [ ] Avoid mixing OS, application, and SQL Server workloads on the same volume in production
- [ ] Check vendor or storage platform guidance (SAN, NAS, cloud, backup appliance)
- [ ] Validate storage latency and throughput independently — cluster size does not compensate for undersized or misconfigured storage
- [ ] Verify allocation unit size after formatting using `fsutil` (see commands below)
- [ ] Confirm partition alignment separately from allocation unit size
- [ ] Document the configuration decision
- [ ] Changing allocation unit size requires reformatting — plan the data migration before making changes to production volumes

---

## Useful Windows Commands

> **Warning:** Formatting destroys all existing data on the target volume. Verify the drive letter before executing any format command.

### Check current allocation unit size

```cmd
fsutil fsinfo ntfsinfo D:
```

Look for the **Bytes Per Cluster** field. `65536` = 64 KB.

### Format a volume with 64 KB allocation unit size

```powershell
# PowerShell — verify drive letter before running
# WARNING: This will erase all data on the target volume
Format-Volume -DriveLetter D -FileSystem NTFS -AllocationUnitSize 65536 -NewFileSystemLabel "SQL_Data" -Confirm:$false
```

```cmd
:: Command Prompt alternative
:: WARNING: This will erase all data on the target volume
format D: /FS:NTFS /A:64K /V:SQL_Data /Q
```

### Verify after formatting

```cmd
fsutil fsinfo ntfsinfo D:
```

Confirm `Bytes Per Cluster` reads `65536`.

---

## Common Mistakes

**Confusing allocation unit size, sector size, and partition alignment — these are three separate layers:**

- **Physical/logical sector size** (512B native, 4Kn, 512e): a hardware and storage driver property.
- **Partition alignment / starting offset**: how the partition boundary aligns to the underlying storage geometry. Typically 1 MB for modern storage.
- **NTFS allocation unit size (cluster size)**: configured at filesystem format time. This is what this guide addresses.

All three affect storage efficiency and performance. All three are configured independently. Conflating them — particularly partition alignment with cluster size — leads to incorrectly formatted volumes even when the right cluster size is chosen.

**Changing allocation unit size after production deployment without a migration plan.** Reformatting is required. Migrating data off a live production volume under time pressure is high-risk.

**Assuming 64 KB allocation unit size fixes bad storage.** It does not. Latency problems caused by saturated storage controllers, misconfigured RAID, or inadequate I/O bandwidth are not solved by cluster size.

**Mixing backup, data, and log workloads on the same physical I/O path.** When I/O queues are saturated, cluster size is irrelevant. Volume separation is an architectural and infrastructure decision.

**Ignoring vendor guidance for SAN, NAS, or cloud storage platforms.** Some storage platforms have their own alignment and block size requirements. Check vendor documentation before formatting.

**Applying 64 KB to FILESTREAM volumes without checking file-size distribution.** The wasted space from small files adds up quickly at scale. Profile first.

---

## Final Recommendation

64 KB allocation unit size is a well-supported, practical default for SQL Server data, log, and backup volumes on Windows/NTFS. For data volumes, it aligns with SQL Server's extent size. For log and backup volumes, it is appropriate for large sequential write patterns and reduces allocation overhead — though storage latency and throughput characteristics matter far more for those workloads than cluster size alone.

FILESTREAM and backup repositories on non-NTFS platforms are the two cases where the default should be validated against real workload characteristics before committing to a cluster size.

Decide before formatting. Verify after formatting. Measure storage performance independently.

---

## References

- [Disk Partition Alignment Best Practices for SQL Server](https://techcommunity.microsoft.com/t5/sql-server-blog/disk-partition-alignment-best-practices-for-sql-server/ba-p/383853) — Microsoft SQL Server Blog
- [SQL Server Best Practices — Storage](https://learn.microsoft.com/en-us/sql/relational-databases/policy-based-management/sql-server-storage-best-practices) — Microsoft Learn
- [FILESTREAM Overview](https://learn.microsoft.com/en-us/sql/relational-databases/blob/filestream-sql-server) — Microsoft Learn
- [fsutil fsinfo](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-fsinfo) — Windows Commands Reference

---