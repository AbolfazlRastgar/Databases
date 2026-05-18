/*
Script Name:     orphaned-users-check.sql
Purpose:         Finds database users that do not have a matching server-level
                 login (orphaned users). This typically happens after database
                 restores to a different server, or when a login is dropped
                 without first removing the database user.
SQL Server Version: 2005 and later
Required Permissions: VIEW DATABASE STATE; runs in the context of each database
Safety Level:    Read-only
How to Use:      This script checks the current database only.
                 To check all user databases, run it from each database
                 or wrap it in sp_MSforeachdb (not recommended for production
                 use — test in your environment first).
                 To fix an orphaned user, use one of:
                   -- Re-link to an existing login:
                   ALTER USER [username] WITH LOGIN = [existing_login];
                   -- Or drop the user if it is no longer needed:
                   DROP USER [username];
Notes:           Windows Authentication users (type = 'E' or 'X') may appear
                 as orphaned if the domain or AD group is not reachable.
                 Certificate-mapped and key-mapped users (type = 'C' or 'K')
                 are expected to have no login and are excluded below.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    dp.name                             AS database_user,
    dp.type_desc                        AS user_type,
    dp.create_date,
    dp.modify_date,
    dp.default_schema_name,
    -- Try to find a matching server-level login by SID
    SUSER_SNAME(dp.sid)                AS mapped_login,
    CASE
        WHEN SUSER_SNAME(dp.sid) IS NULL THEN 'Orphaned — no matching login'
        ELSE 'Login found'
    END                                 AS status
FROM sys.database_principals AS dp
WHERE dp.type IN ('S', 'U', 'G')   -- SQL users, Windows users, Windows groups
  AND dp.name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
  AND dp.sid IS NOT NULL
  AND SUSER_SNAME(dp.sid) IS NULL   -- No matching server login
ORDER BY
    dp.name;
