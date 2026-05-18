# 07 — Security and Permissions

Scripts for auditing SQL Server server-level roles, database ownership, and orphaned users.

All scripts in this folder are **read-only**.

---

## Scripts

| File | Purpose |
|---|---|
| `server-role-members.sql` | Members of important fixed server roles |
| `database-owner-check.sql` | Database owners, with flags for unusual ownership |
| `orphaned-users-check.sql` | Database users with no matching server-level login |

---

## When to Use

- During security audits or compliance reviews
- When onboarding a new SQL Server instance to understand who has access
- After personnel changes to verify that access has been revoked appropriately
- When a new database user is reporting login issues (orphaned user diagnosis)

## Permissions Required

- `VIEW ANY DATABASE` and `VIEW SERVER STATE`
- `SELECT` on system catalog views
- Members of sysadmin have full access

## SQL Server Version Compatibility

- All scripts: SQL Server 2005 and later
- `sys.server_role_members` and `sys.server_principals`: available from SQL Server 2005

## Safety Level

**Read-only** — No changes are made to permissions, roles, or users.
