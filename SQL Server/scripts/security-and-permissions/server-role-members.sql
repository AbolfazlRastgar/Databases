/*
Script Name:     server-role-members.sql
Purpose:         Lists members of the most important fixed server roles:
                 sysadmin, securityadmin, serveradmin, setupadmin,
                 processadmin, diskadmin, dbcreator, and bulkadmin.
                 Useful for auditing who has elevated server-level access.
SQL Server Version: 2005 and later
Required Permissions: VIEW SERVER STATE or membership in public role
Safety Level:    Read-only
How to Use:      Run as-is. Review the sysadmin list especially carefully —
                 it should contain only the accounts that genuinely need it.
                 Service accounts, application accounts, and developer accounts
                 should generally not be in sysadmin.
Notes:           This script covers fixed server roles only. For user-defined
                 server roles (SQL Server 2012+), query sys.server_role_members
                 without the WHERE filter below, or add your custom role names.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    r.name                              AS server_role,
    m.name                              AS member_name,
    m.type_desc                         AS member_type,
    m.is_disabled,
    m.create_date,
    m.modify_date,
    -- Flag accounts that may be worth reviewing
    CASE
        WHEN r.name = 'sysadmin'
         AND m.name NOT IN ('sa', 'NT SERVICE\MSSQLSERVER', 'NT SERVICE\SQLSERVERAGENT',
                             'NT SERVICE\SQLWriter', 'NT AUTHORITY\SYSTEM')
        THEN 'Review'
        ELSE ''
    END                                 AS review_flag
FROM sys.server_role_members AS srm
INNER JOIN sys.server_principals AS r
    ON srm.role_principal_id = r.principal_id
INNER JOIN sys.server_principals AS m
    ON srm.member_principal_id = m.principal_id
WHERE r.name IN (
    'sysadmin', 'securityadmin', 'serveradmin',
    'setupadmin', 'processadmin', 'diskadmin',
    'dbcreator', 'bulkadmin'
)
ORDER BY
    r.name,
    m.name;
