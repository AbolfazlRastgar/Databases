/*
Script Name:     database-owner-check.sql
Purpose:         Lists all databases with their current owner, and flags
                 databases not owned by 'sa' or a designated service account.
                 Individual logins owning databases is a common security and
                 operational risk — if that login is dropped, the database
                 becomes inaccessible.
SQL Server Version: 2005 and later
Required Permissions: VIEW ANY DATABASE
Safety Level:    Read-only
How to Use:      Run as-is. Review the review_flag column and investigate any
                 databases owned by individual user accounts.
                 Best practice is to set database owner to 'sa' or a dedicated
                 service account using:
                   ALTER AUTHORIZATION ON DATABASE::[DatabaseName] TO [sa];
Notes:           sa is disabled on many hardened instances. In that case,
                 use a dedicated service account login as the standard owner.
                 Adjust the @ExpectedOwners list to match your environment.
Author:          Abolfazl Rastgar
*/

SET NOCOUNT ON;

SELECT
    d.name                              AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    SUSER_SNAME(d.owner_sid)           AS owner_login,
    d.create_date,
    -- Flag databases not owned by expected accounts
    CASE
        WHEN SUSER_SNAME(d.owner_sid) NOT IN ('sa', 'NT AUTHORITY\SYSTEM')
         AND SUSER_SNAME(d.owner_sid) IS NOT NULL
        THEN 'Review owner'
        WHEN SUSER_SNAME(d.owner_sid) IS NULL
        THEN 'Owner login missing'
        ELSE ''
    END                                 AS review_flag
FROM sys.databases AS d
WHERE d.name NOT IN ('tempdb')  -- tempdb owner is not meaningful
ORDER BY
    review_flag DESC,
    d.name;
