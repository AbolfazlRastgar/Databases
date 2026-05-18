# Ola Hallengren SQL Server Maintenance Solution — Usage Examples

This folder contains notes and example scripts for the **Ola Hallengren SQL Server Maintenance Solution**.

Ola's solution is the community-standard approach to SQL Server backup, integrity check, and index maintenance. It is production-tested, widely deployed, and actively maintained.

---

## Before Using These Scripts

**You must download and install the maintenance solution separately.**

Official source: [https://ola.hallengren.com](https://ola.hallengren.com)
GitHub repository: [https://github.com/olahallengren/sql-server-maintenance-solution](https://github.com/olahallengren/sql-server-maintenance-solution)

The solution installs several stored procedures and a `CommandLog` table in a database of your choice. The example scripts in this folder assume the solution has been installed in the `master` database. Adjust the database prefix if yours differs.

## License and Attribution

The Ola Hallengren SQL Server Maintenance Solution is written by **Ola Hallengren** and is free to use in any environment. See the license at [https://ola.hallengren.com/license.html](https://ola.hallengren.com/license.html).

The scripts in this folder are **usage examples only**. They do not contain any code from the maintenance solution itself.

---

## Files

| File | Description |
|---|---|
| `01-installation-notes.md` | How to install and configure the solution |
| `02-example-full-backup-job.sql` | Example SQL Agent job step for full database backups |
| `03-example-diff-backup-job.sql` | Example SQL Agent job step for differential backups |
| `04-example-log-backup-job.sql` | Example SQL Agent job step for log backups |
| `05-check-commandlog-results.sql` | Query the CommandLog table to review maintenance history |

---

## When to Use

- For all backup, integrity check, and index/statistics maintenance on SQL Server
- When setting up a new SQL Server instance
- When evaluating whether backup and maintenance jobs are completing successfully
