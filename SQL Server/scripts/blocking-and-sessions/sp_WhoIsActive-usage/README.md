# sp_WhoIsActive — Usage Examples

This folder contains usage examples for **sp_WhoIsActive** by Adam Machanic.

`sp_WhoIsActive` is a free, open-source stored procedure for monitoring active SQL Server sessions. It is significantly more practical for daily DBA work than querying DMVs manually, and is widely used across the SQL Server community.

---

## Before Using These Scripts

**You must download and install sp_WhoIsActive separately.**

Official source: [http://whoisactive.com](http://whoisactive.com)
GitHub repository: [https://github.com/amachanic/sp_whoisactive](https://github.com/amachanic/sp_whoisactive)

Install `sp_WhoIsActive` in a utility database (commonly `master` or a dedicated DBA database) before running any script in this folder.

## License and Attribution

`sp_WhoIsActive` is written by **Adam Machanic** and is licensed under the Apache License 2.0.

The scripts in this folder are **usage examples only**. They do not contain any code from `sp_WhoIsActive` itself.

---

## Scripts

| File | Purpose |
|---|---|
| `01-basic-usage.sql` | Common parameter combinations for everyday monitoring |
| `02-find-blocking-chain.sql` | Using sp_WhoIsActive to identify blocking chains |
| `03-capture-whoisactive-to-table.sql` | Capturing output to a table for later analysis |

---

## When to Use sp_WhoIsActive

- As a first response to "the server is slow" calls
- When monitoring active workloads during deployments or maintenance windows
- For capturing a baseline of session activity over time
- During blocking or deadlock investigations

## Permissions Required

- `VIEW SERVER STATE` is typically sufficient for basic usage
- Some parameters (e.g., `@get_plans`) may require additional permissions
- Check the sp_WhoIsActive documentation for details
