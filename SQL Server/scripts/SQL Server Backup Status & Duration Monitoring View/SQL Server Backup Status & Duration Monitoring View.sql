USE [RedGateMonitor]
GO

/****** Object:  View [dbo].[vw_BackupMonitoring_WithFileNames_withDuration]    Script Date: 4/17/2026 5:06:09 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE VIEW [dbo].[vw_BackupMonitoring_WithFileNames_withDuration]
AS

/* 
    CTE: BackupRanked

    Purpose:
    Prepare the full backup history dataset and assign a sequence number
    per Cluster / Server / Database / BackupType.

    Why:
    This makes it possible to reliably identify:
    - the latest backup for each backup type
    - the previous backup for comparison scenarios

    Notes:
    - COPY_ONLY backups are excluded because they are not considered part
      of the regular backup chain for operational monitoring purposes.
*/
WITH BackupRanked AS
(
    SELECT
        Cluster_Name,
        Cluster_SqlServer_Name AS ServerName,
        Cluster_SqlServer_Database_Name AS DatabaseName,
        Cluster_SqlServer_Database_BackupType_Type AS BackupType,

        Cluster_SqlServer_Database_BackupType_Backup_StartDate_DateTime AS StartDate,
        Cluster_SqlServer_Database_BackupType_Backup_FinishDate_DateTime AS FinishDate,

        Cluster_SqlServer_Database_BackupType_Backup_DeviceName AS DeviceName,

        /*
            rn meaning:
            - rn = 1  -> latest backup of this type
            - rn = 2  -> previous backup of this type
        */
        ROW_NUMBER() OVER(
            PARTITION BY 
                Cluster_Name,
                Cluster_SqlServer_Name,
                Cluster_SqlServer_Database_Name,
                Cluster_SqlServer_Database_BackupType_Type
            ORDER BY Cluster_SqlServer_Database_BackupType_Backup_FinishDate_DateTime DESC
        ) AS rn
    FROM [RedGateMonitor].[data].[Cluster_SqlServer_Database_BackupType_Backup_Instances_View]
    WHERE Cluster_SqlServer_Database_BackupType_Backup_IsCopyOnly = 0
),

/*
    CTE: FullList

    Purpose:
    Keep only the last two FULL backups for each database.

    Why:
    FULL backup duration is later compared against the previous FULL backup
    duration in order to highlight changes in runtime.
*/
FullList AS
(
    SELECT
        Cluster_Name,
        ServerName,
        DatabaseName,
        StartDate,
        FinishDate,
        rn
    FROM BackupRanked
    WHERE BackupType = 'D' AND rn <= 2
),

/*
    CTE: FullPairs

    Purpose:
    Pair the latest FULL backup with the previous FULL backup.

    Why:
    This gives us the two execution windows required to compute:
    - latest FULL duration
    - previous FULL duration
    - duration delta between consecutive FULL backups
*/
FullPairs AS
(
    SELECT
        f1.Cluster_Name,
        f1.ServerName,
        f1.DatabaseName,

        f1.StartDate AS LastFullStart,
        f1.FinishDate AS LastFullFinish,

        f2.StartDate AS PrevFullStart,
        f2.FinishDate AS PrevFullFinish
    FROM FullList f1
    LEFT JOIN FullList f2
        ON f1.Cluster_Name = f2.Cluster_Name
        AND f1.ServerName = f2.ServerName
        AND f1.DatabaseName = f2.DatabaseName
        AND f1.rn = 1
        AND f2.rn = 2
),

/*
    CTE: LastBackups

    Purpose:
    Build the latest backup snapshot per database.

    Output:
    - latest FULL backup finish time
    - latest DIFF backup finish time
    - latest LOG backup finish time
    - latest backup file name for each type

    Why:
    This is the core operational summary used later to evaluate
    backup freshness and expose file-level reference data.

    Note:
    The file name is extracted from DeviceName by removing the directory path.
*/
LastBackups AS
(
    SELECT
        Cluster_Name,
        ServerName,
        DatabaseName,

        MAX(CASE WHEN BackupType='D' THEN FinishDate END) AS LastFull,
        MAX(CASE WHEN BackupType='I' THEN FinishDate END) AS LastDiff,
        MAX(CASE WHEN BackupType='L' THEN FinishDate END) AS LastLog,

        MAX(CASE WHEN BackupType='D'
            THEN RIGHT(DeviceName, CHARINDEX('\', REVERSE(DeviceName)) - 1) END) AS LastFullFileName,

        MAX(CASE WHEN BackupType='I'
            THEN RIGHT(DeviceName, CHARINDEX('\', REVERSE(DeviceName)) - 1) END) AS LastDiffFileName,

        MAX(CASE WHEN BackupType='L'
            THEN RIGHT(DeviceName, CHARINDEX('\', REVERSE(DeviceName)) - 1) END) AS LastLogFileName
    FROM BackupRanked
    WHERE rn = 1
    GROUP BY Cluster_Name, ServerName, DatabaseName
),

/*
    CTE: AdjustedTimes

    Purpose:
    Convert latest backup timestamps to local reporting time.

    Why:
    Operational monitoring is easier to read when timestamps are shown
    in the local timezone expected by the team.

    Current implementation:
    - Adds 210 minutes to convert to Tehran time
*/
AdjustedTimes AS
(
    SELECT
        LB.Cluster_Name,
        LB.ServerName,
        LB.DatabaseName,

        DATEADD(MINUTE, 210, LB.LastFull) AS LastFullTehran,
        DATEADD(MINUTE, 210, LB.LastDiff) AS LastDiffTehran,
        DATEADD(MINUTE, 210, LB.LastLog) AS LastLogTehran,

        LB.LastFullFileName,
        LB.LastDiffFileName,
        LB.LastLogFileName,

        FP.PrevFullStart,
        FP.PrevFullFinish,
        FP.LastFullStart,
        FP.LastFullFinish
    FROM LastBackups LB
    LEFT JOIN FullPairs FP
        ON LB.Cluster_Name = FP.Cluster_Name
        AND LB.ServerName = FP.ServerName
        AND LB.DatabaseName = FP.DatabaseName
)

SELECT
    Cluster_Name,
    ServerName,
    DatabaseName,

    /*
        Backup freshness status

        Thresholds used in this view:
        - FULL <= 24 hours
        - DIFF <= 12 hours
        - LOG  <= 1 hour

        Return values:
        - 'True'  : backup is within expected interval
        - 'False' : backup is older than expected interval
        - 'N/A'   : no backup of that type was found
    */
    CASE 
         WHEN LastFullTehran IS NULL THEN 'N/A'
         WHEN DATEDIFF(HOUR, LastFullTehran, GETDATE()) <= 24 THEN 'True' 
         ELSE 'False' 
    END AS FullBackupOK,

    CASE 
         WHEN LastDiffTehran IS NULL THEN 'N/A'
         WHEN DATEDIFF(HOUR, LastDiffTehran, GETDATE()) <= 12 THEN 'True' 
         ELSE 'False' 
    END AS DiffBackupOK,

    CASE 
         WHEN LastLogTehran IS NULL THEN 'N/A'
         WHEN DATEDIFF(HOUR, LastLogTehran, GETDATE()) <= 1 THEN 'True' 
         ELSE 'False' 
    END AS LogBackupOK,

    /*
        Human-readable backup age

        These columns are intended for dashboard/reporting consumption,
        not for further time arithmetic.
    */
    ISNULL(CAST(DATEDIFF(DAY, LastFullTehran, GETDATE()) AS VARCHAR(10)) + 'd', 'N/A') AS FullAge,
    ISNULL(CAST(DATEDIFF(HOUR, LastDiffTehran, GETDATE()) AS VARCHAR(10)) + 'h', 'N/A') AS DiffAge,
    ISNULL(CAST(DATEDIFF(MINUTE, LastLogTehran, GETDATE()) AS VARCHAR(10)) + 'm', 'N/A') AS LogAge,

    /*
        Latest backup file names

        These values are useful for:
        - quick validation
        - operational tracing
        - restore-related reference checks
    */
    ISNULL(LastFullFileName, 'No Full Backup Found') AS LastFullFile,
    ISNULL(LastDiffFileName, 'No Diff Backup Found') AS LastDiffFile,
    ISNULL(LastLogFileName, 'No Log Backup Found') AS LastLogFile,

    /*
        Latest FULL backup duration in minutes
    */
    CASE WHEN LastFullStart IS NULL THEN NULL
         ELSE DATEDIFF(MINUTE, LastFullStart, LastFullFinish)
    END AS LastFullDuration,

    /*
        Previous FULL backup duration in minutes
    */
    CASE WHEN PrevFullStart IS NULL THEN NULL
         ELSE DATEDIFF(MINUTE, PrevFullStart, PrevFullFinish)
    END AS PrevFullDuration,

    /*
        Delta between latest and previous FULL backup durations

        Interpretation:
        - positive value  -> latest FULL took longer
        - negative value  -> latest FULL completed faster
        - NULL            -> previous FULL not available

        This metric can help identify:
        - abnormal growth in backup duration
        - storage / I/O pressure
        - data volume changes
    */
    CASE
        WHEN PrevFullStart IS NULL THEN NULL
        ELSE DATEDIFF(MINUTE, LastFullStart, LastFullFinish)
           - DATEDIFF(MINUTE, PrevFullStart, PrevFullFinish)
    END AS FullBackupDuration

FROM AdjustedTimes;

GO