# Installation Notes — Ola Hallengren SQL Server Maintenance Solution

## Source

Download the latest version from: [https://ola.hallengren.com](https://ola.hallengren.com)
Direct download link: [https://ola.hallengren.com/scripts/MaintenanceSolution.sql](https://ola.hallengren.com/scripts/MaintenanceSolution.sql)

The GitHub repository is at: [https://github.com/olahallengren/sql-server-maintenance-solution](https://github.com/olahallengren/sql-server-maintenance-solution)

---

## What Gets Installed

Running `MaintenanceSolution.sql` creates the following objects in the target database:

| Object | Type | Purpose |
|---|---|---|
| `DatabaseBackup` | Stored procedure | Backup operations |
| `DatabaseIntegrityCheck` | Stored procedure | DBCC CHECKDB operations |
| `IndexOptimize` | Stored procedure | Index rebuild/reorganize and statistics updates |
| `CommandExecute` | Stored procedure | Internal procedure used by the others |
| `CommandLog` | Table | Audit log of all maintenance operations |

---

## Installation Steps

1. Download `MaintenanceSolution.sql`.
2. Open it in SSMS and connect to the target SQL Server instance.
3. At the top of the script, find the `@CreateJobs` parameter and set it to:
   - `'Y'` if you want the script to create SQL Agent jobs automatically
   - `'N'` if you prefer to create jobs manually
4. Set the `@BackupDirectory` parameter to your default backup path.
5. Set the `@Database` parameter to the database where you want the objects installed (e.g. `master`).
6. Run the script.

---

## Recommended Configuration

- Install in `master` unless your organization has a dedicated DBA/utility database.
- Set `@CleanupTime` on backup procedures to automatically delete old backup files (e.g. 72 hours for full backups).
- Set `@Compress` to `'Y'` if your edition supports backup compression (Standard/Enterprise, SQL Server 2008+).
- Set `@CheckSum` to `'Y'` to validate backups during the backup operation.
- Review the `@LogToTable` parameter — setting it to `'Y'` enables CommandLog logging.

---

## SQL Server Version Compatibility

The maintenance solution supports SQL Server 2008 and later. It also supports Azure SQL Managed Instance.

---

## Permissions Required

The SQL Agent service account (or the account running the jobs) needs:
- `sysadmin` fixed server role (simplest), or
- Specific permissions documented on the Ola Hallengren website

---

## Notes

- Always test jobs in a non-production environment before deploying.
- Review the `@Databases` parameter — it accepts values like `'USER_DATABASES'`, `'SYSTEM_DATABASES'`, or specific database names.
- The `CommandLog` table is your audit trail. Query it regularly to confirm maintenance is completing successfully (see `05-check-commandlog-results.sql`).
