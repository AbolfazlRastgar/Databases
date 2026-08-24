/*
===============================================================================
 SQL Database Schema Compare Tool
 Version 1.4.1

 Purpose
 -------
 Compare the schema of:
   1) A source database on the SAME SQL Server instance where this procedure runs
   2) A target database that can be either:
      - LOCAL: another database on the same SQL Server instance
      - REMOTE: a database on another SQL Server instance

 Connection mode
 ---------------
 - If @TargetServer IS NULL or empty:
     The procedure assumes Source and Target are on the same SQL Server.
     No Linked Server is created.

 - If @TargetServer has a value:
     The procedure creates a temporary Linked Server to the target server,
     performs the comparison, and removes the Linked Server afterward.

 Recommended installation location
 ---------------------------------
 Install this procedure in a DBA/utility database such as:
   - DBA_Tools
   - zdba
   - another administration database

 The procedure DOES NOT create or modify objects in the source or target database.

 Current comparison scope
 ------------------------
 - Missing tables
 - Missing columns
 - Base data type differences
 - Character/binary length differences
 - Numeric precision/scale differences
 - time/datetime2/datetimeoffset scale differences
 - NULL / NOT NULL differences
 - IDENTITY differences

 Notes
 -----
 - Matching objects are not stored in the result table.
 - One column can produce multiple difference rows.
 - For remote targets, the remote login should have VIEW DEFINITION permission
   on the target database.
===============================================================================


 ------------------------------------------------------------------------------
 PARAMETERS GUIDE
 ------------------------------------------------------------------------------

 Procedure parameters:

    @SourceDatabase
        Required.
        The source database name.
        This database must exist on the same SQL Server instance where the
        procedure is installed.

        Example:
            @SourceDatabase = 'ProductionDB'


    @TargetDatabase
        Required.
        The database that will be compared against the source database.

        Example:
            @TargetDatabase = 'TestDB'


    @TargetServer
        Optional.

        If NULL or empty:
            The procedure assumes source and target are on the same SQL Server
            instance.
            No Linked Server is created.

        Example (same server):

            EXEC dbo.usp_CompareDatabaseSchema
                @SourceDatabase = 'ProductionDB',
                @TargetDatabase = 'TestDB';


        If a value is provided:
            The procedure assumes the target database is on another SQL Server.
            A temporary Linked Server will be created automatically.

        Example:

            @TargetServer = 'SQLSERVER02'

        or:

            @TargetServer = '10.10.10.20'


    @TargetUser
        Required only for remote target mode.

        SQL login used by the temporary Linked Server.

        Example:

            @TargetUser = 'schema_compare_user'


    @TargetPassword
        Required only for remote target mode.

        Password of the SQL login specified in @TargetUser.

        Example:

            @TargetPassword = 'YourStrongPassword'


    @ProviderString
        Optional.

        Additional MSOLEDBSQL provider options.

        Usually not required.

        Example:

            @ProviderString = N'encrypt=optional'


 ------------------------------------------------------------------------------
 COMPLETE EXECUTION EXAMPLES
 ------------------------------------------------------------------------------

 Example 1:
 Compare two databases on the same SQL Server.

    EXEC dbo.usp_CompareDatabaseSchema
        @SourceDatabase = 'DarichehPlus_Mazi',
        @TargetDatabase = 'DarichehPlus_New';


 Example 2:
 Compare a local database with a database on another SQL Server.

    EXEC dbo.usp_CompareDatabaseSchema
        @SourceDatabase = 'DarichehPlus_Mazi',
        @TargetDatabase = 'DarichehPlus_New',
        @TargetServer = '10.187.160.35',
        @TargetUser = 'schema_compare_user',
        @TargetPassword = 'YourPassword';


 Example 3:
 Remote SQL Server with provider options.

    EXEC dbo.usp_CompareDatabaseSchema
        @SourceDatabase = 'ProductionDB',
        @TargetDatabase = 'UAT_DB',
        @TargetServer = 'SQL-UAT-01',
        @TargetUser = 'schema_compare_user',
        @TargetPassword = 'YourPassword',
        @ProviderString = N'encrypt=optional';


 ------------------------------------------------------------------------------

*/

CREATE OR ALTER PROCEDURE dbo.usp_CompareDatabaseSchema
(
    @SourceDatabase   SYSNAME,

    @TargetDatabase   SYSNAME,
    @TargetServer     SYSNAME = NULL,
    @TargetUser       SYSNAME = NULL,
    @TargetPassword   NVARCHAR(256) = NULL,

    @ProviderString   NVARCHAR(4000) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    ---------------------------------------------------------------------------
     Runtime variables
    ---------------------------------------------------------------------------
    */
    DECLARE
        @RunID          UNIQUEIDENTIFIER = NEWID(),
        @LinkedServer   SYSNAME = NULL,
        @SQL            NVARCHAR(MAX),
        @ErrorMessage   NVARCHAR(4000),
        @IsRemote       BIT = 0;

    /*
    ---------------------------------------------------------------------------
     Determine connection mode.

     Empty/NULL @TargetServer => same-server mode
     Non-empty @TargetServer  => remote mode
    ---------------------------------------------------------------------------
    */
    IF NULLIF(LTRIM(RTRIM(@TargetServer)), N'') IS NOT NULL
        SET @IsRemote = 1;


    /*
    ---------------------------------------------------------------------------
     Generate a unique Linked Server name only for remote mode.
    ---------------------------------------------------------------------------
    */
    IF @IsRemote = 1
    BEGIN
        SET @LinkedServer =
            N'TMP_SCHEMA_COMPARE_' +
            REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'');
    END;


    BEGIN TRY

        /*
        -----------------------------------------------------------------------
         Create the run-history table if it does not already exist.

         Created only in the utility database where this procedure is installed.
        -----------------------------------------------------------------------
        */
        IF OBJECT_ID(N'dbo.SchemaCompare_Run', N'U') IS NULL
        BEGIN
            BEGIN TRY
                CREATE TABLE dbo.SchemaCompare_Run
                (
                    RunID           UNIQUEIDENTIFIER NOT NULL
                        CONSTRAINT PK_SchemaCompare_Run PRIMARY KEY,
                    SourceDatabase  SYSNAME          NOT NULL,
                    TargetServer    SYSNAME          NULL,
                    TargetDatabase  SYSNAME          NOT NULL,
                    StartTime       DATETIME2(3)     NOT NULL,
                    EndTime         DATETIME2(3)     NULL,
                    Status          VARCHAR(20)      NOT NULL,
                    ErrorMessage    NVARCHAR(4000)   NULL
                );
            END TRY
            BEGIN CATCH
                IF ERROR_NUMBER() <> 2714
                    THROW;
            END CATCH;
        END;


        /*
        -----------------------------------------------------------------------
         Upgrade compatibility for older versions.

         Versions before 1.4 created TargetServer as NOT NULL because every
         comparison was assumed to use a remote target.

         Version 1.4+ supports same-server comparisons, where TargetServer is
         intentionally NULL. If an older SchemaCompare_Run table already
         exists, make this column nullable automatically.
        -----------------------------------------------------------------------
        */
        IF EXISTS
        (
            SELECT 1
            FROM sys.columns
            WHERE object_id = OBJECT_ID(N'dbo.SchemaCompare_Run', N'U')
              AND name = N'TargetServer'
              AND is_nullable = 0
        )
        BEGIN
            ALTER TABLE dbo.SchemaCompare_Run
                ALTER COLUMN TargetServer SYSNAME NULL;
        END;


        /*
        -----------------------------------------------------------------------
         Create the result table if it does not already exist.

         Only differences are stored.
        -----------------------------------------------------------------------
        */
        IF OBJECT_ID(N'dbo.SchemaCompare_Result', N'U') IS NULL
        BEGIN
            BEGIN TRY
                CREATE TABLE dbo.SchemaCompare_Result
                (
                    ID               BIGINT IDENTITY(1,1) NOT NULL
                        CONSTRAINT PK_SchemaCompare_Result PRIMARY KEY,
                    RunID            UNIQUEIDENTIFIER NOT NULL,

                    SchemaName       SYSNAME NULL,
                    TableName        SYSNAME NULL,
                    ColumnName       SYSNAME NULL,

                    DifferenceType   VARCHAR(100) NOT NULL,

                    SourceDataType   NVARCHAR(256) NULL,
                    TargetDataType   NVARCHAR(256) NULL,

                    SourceLength     INT NULL,
                    TargetLength     INT NULL,

                    SourceNullable   BIT NULL,
                    TargetNullable   BIT NULL,

                    SourceIdentity   BIT NULL,
                    TargetIdentity   BIT NULL
                );

                CREATE INDEX IX_SchemaCompare_Result_RunID
                    ON dbo.SchemaCompare_Result(RunID);
            END TRY
            BEGIN CATCH
                IF ERROR_NUMBER() <> 2714
                    THROW;
            END CATCH;
        END;


        /*
        -----------------------------------------------------------------------
         Register this comparison run.
        -----------------------------------------------------------------------
        */
        INSERT INTO dbo.SchemaCompare_Run
        (
            RunID,
            SourceDatabase,
            TargetServer,
            TargetDatabase,
            StartTime,
            EndTime,
            Status,
            ErrorMessage
        )
        VALUES
        (
            @RunID,
            @SourceDatabase,
            NULLIF(LTRIM(RTRIM(@TargetServer)), N''),
            @TargetDatabase,
            SYSDATETIME(),
            NULL,
            'RUNNING',
            NULL
        );


        /*
        -----------------------------------------------------------------------
         Validate source database.
        -----------------------------------------------------------------------
        */
        IF NULLIF(LTRIM(RTRIM(@SourceDatabase)), N'') IS NULL
            THROW 50001, 'Source database name is required.', 1;

        IF DB_ID(@SourceDatabase) IS NULL
        BEGIN
            SET @ErrorMessage =
                N'Source database [' + ISNULL(@SourceDatabase, N'NULL') +
                N'] does not exist on the current SQL Server instance.';
            THROW 50002, @ErrorMessage, 1;
        END;

        IF HAS_DBACCESS(@SourceDatabase) <> 1
        BEGIN
            SET @ErrorMessage =
                N'The current login does not have access to source database [' +
                @SourceDatabase + N'].';
            THROW 50003, @ErrorMessage, 1;
        END;


        /*
        -----------------------------------------------------------------------
         Validate target parameters.

         In local mode:
           Only @TargetDatabase is required.

         In remote mode:
           @TargetServer, @TargetDatabase, @TargetUser and @TargetPassword
           are required.
        -----------------------------------------------------------------------
        */
        IF NULLIF(LTRIM(RTRIM(@TargetDatabase)), N'') IS NULL
            THROW 50004, 'Target database name is required.', 1;

        IF @IsRemote = 0
        BEGIN
            IF DB_ID(@TargetDatabase) IS NULL
            BEGIN
                SET @ErrorMessage =
                    N'Target database [' + @TargetDatabase +
                    N'] does not exist on the current SQL Server instance.';
                THROW 50005, @ErrorMessage, 1;
            END;

            IF HAS_DBACCESS(@TargetDatabase) <> 1
            BEGIN
                SET @ErrorMessage =
                    N'The current login does not have access to target database [' +
                    @TargetDatabase + N'].';
                THROW 50006, @ErrorMessage, 1;
            END;
        END
        ELSE
        BEGIN
            IF NULLIF(LTRIM(RTRIM(@TargetUser)), N'') IS NULL
                THROW 50007, 'Target user is required for remote mode.', 1;

            IF @TargetPassword IS NULL
                THROW 50008, 'Target password is required for remote mode.', 1;
        END;


        /*
        -----------------------------------------------------------------------
         Remote mode only:
         Create a temporary Linked Server and map the supplied credentials.
        -----------------------------------------------------------------------
        */
        IF @IsRemote = 1
        BEGIN
            EXEC master.dbo.sp_addlinkedserver
                @server     = @LinkedServer,
                @srvproduct = N'',
                @provider   = N'MSOLEDBSQL',
                @datasrc    = @TargetServer,
                @provstr    = @ProviderString;

            EXEC master.dbo.sp_addlinkedsrvlogin
                @rmtsrvname = @LinkedServer,
                @useself     = N'FALSE',
                @locallogin  = NULL,
                @rmtuser     = @TargetUser,
                @rmtpassword = @TargetPassword;

            EXEC master.dbo.sp_testlinkedserver @LinkedServer;
        END;


        /*
        -----------------------------------------------------------------------
         Temporary table lists for clean table-level comparison.
        -----------------------------------------------------------------------
        */
        CREATE TABLE #SourceTables
        (
            SchemaName SYSNAME NOT NULL,
            TableName  SYSNAME NOT NULL
        );

        CREATE TABLE #TargetTables
        (
            SchemaName SYSNAME NOT NULL,
            TableName  SYSNAME NOT NULL
        );

        CREATE TABLE #CommonTables
        (
            SchemaName SYSNAME NOT NULL,
            TableName  SYSNAME NOT NULL,
            PRIMARY KEY (SchemaName, TableName)
        );


        /*
        -----------------------------------------------------------------------
         Column metadata staging tables.
        -----------------------------------------------------------------------
        */
        CREATE TABLE #SourceMetadata
        (
            SchemaName       SYSNAME       NOT NULL,
            TableName        SYSNAME       NOT NULL,
            ColumnName       SYSNAME       NOT NULL,
            BaseDataType     SYSNAME       NOT NULL,
            TypeDefinition   NVARCHAR(256) NULL,
            MaxLengthBytes   SMALLINT      NULL,
            LogicalLength    INT           NULL,
            PrecisionValue   TINYINT       NULL,
            ScaleValue       TINYINT       NULL,
            IsNullable       BIT           NOT NULL,
            IsIdentity       BIT           NOT NULL
        );

        CREATE TABLE #TargetMetadata
        (
            SchemaName       SYSNAME       NOT NULL,
            TableName        SYSNAME       NOT NULL,
            ColumnName       SYSNAME       NOT NULL,
            BaseDataType     SYSNAME       NOT NULL,
            TypeDefinition   NVARCHAR(256) NULL,
            MaxLengthBytes   SMALLINT      NULL,
            LogicalLength    INT           NULL,
            PrecisionValue   TINYINT       NULL,
            ScaleValue       TINYINT       NULL,
            IsNullable       BIT           NOT NULL,
            IsIdentity       BIT           NOT NULL
        );


        /*
        -----------------------------------------------------------------------
         Read source tables from the local source database.
        -----------------------------------------------------------------------
        */
        SET @SQL = N'
            INSERT INTO #SourceTables (SchemaName, TableName)
            SELECT
                s.name,
                t.name
            FROM ' + QUOTENAME(@SourceDatabase) + N'.sys.tables AS t
            INNER JOIN ' + QUOTENAME(@SourceDatabase) + N'.sys.schemas AS s
                ON t.schema_id = s.schema_id
            WHERE t.is_ms_shipped = 0;';

        EXEC sys.sp_executesql @SQL;


        /*
        -----------------------------------------------------------------------
         Read source column metadata.
        -----------------------------------------------------------------------
        */
        SET @SQL = N'
            INSERT INTO #SourceMetadata
            (
                SchemaName,
                TableName,
                ColumnName,
                BaseDataType,
                TypeDefinition,
                MaxLengthBytes,
                LogicalLength,
                PrecisionValue,
                ScaleValue,
                IsNullable,
                IsIdentity
            )
            SELECT
                s.name,
                t.name,
                c.name,
                ty.name,
                NULL,
                c.max_length,
                NULL,
                c.precision,
                c.scale,
                c.is_nullable,
                c.is_identity
            FROM ' + QUOTENAME(@SourceDatabase) + N'.sys.tables AS t
            INNER JOIN ' + QUOTENAME(@SourceDatabase) + N'.sys.schemas AS s
                ON t.schema_id = s.schema_id
            INNER JOIN ' + QUOTENAME(@SourceDatabase) + N'.sys.columns AS c
                ON t.object_id = c.object_id
            INNER JOIN ' + QUOTENAME(@SourceDatabase) + N'.sys.types AS ty
                ON c.user_type_id = ty.user_type_id
            WHERE t.is_ms_shipped = 0;';

        EXEC sys.sp_executesql @SQL;


        /*
        -----------------------------------------------------------------------
         Read target table list.

         Local mode  -> direct three-part database references
         Remote mode -> four-part Linked Server references
        -----------------------------------------------------------------------
        */
        IF @IsRemote = 0
        BEGIN
            SET @SQL = N'
                INSERT INTO #TargetTables (SchemaName, TableName)
                SELECT
                    s.name,
                    t.name
                FROM ' + QUOTENAME(@TargetDatabase) + N'.sys.tables AS t
                INNER JOIN ' + QUOTENAME(@TargetDatabase) + N'.sys.schemas AS s
                    ON t.schema_id = s.schema_id
                WHERE t.is_ms_shipped = 0;';

            EXEC sys.sp_executesql @SQL;
        END
        ELSE
        BEGIN
            SET @SQL = N'
                SELECT
                    s.name,
                    t.name
                FROM ' + QUOTENAME(@LinkedServer) + N'.' +
                           QUOTENAME(@TargetDatabase) + N'.sys.tables AS t
                INNER JOIN ' + QUOTENAME(@LinkedServer) + N'.' +
                                QUOTENAME(@TargetDatabase) + N'.sys.schemas AS s
                    ON t.schema_id = s.schema_id
                WHERE t.is_ms_shipped = 0;';

            INSERT INTO #TargetTables (SchemaName, TableName)
            EXEC sys.sp_executesql @SQL;
        END;


        /*
        -----------------------------------------------------------------------
         Read target column metadata.

         Local mode  -> direct local database catalog views
         Remote mode -> remote catalog views through Linked Server
        -----------------------------------------------------------------------
        */
        IF @IsRemote = 0
        BEGIN
            SET @SQL = N'
                INSERT INTO #TargetMetadata
                (
                    SchemaName,
                    TableName,
                    ColumnName,
                    BaseDataType,
                    TypeDefinition,
                    MaxLengthBytes,
                    LogicalLength,
                    PrecisionValue,
                    ScaleValue,
                    IsNullable,
                    IsIdentity
                )
                SELECT
                    s.name,
                    t.name,
                    c.name,
                    ty.name,
                    NULL,
                    c.max_length,
                    NULL,
                    c.precision,
                    c.scale,
                    c.is_nullable,
                    c.is_identity
                FROM ' + QUOTENAME(@TargetDatabase) + N'.sys.tables AS t
                INNER JOIN ' + QUOTENAME(@TargetDatabase) + N'.sys.schemas AS s
                    ON t.schema_id = s.schema_id
                INNER JOIN ' + QUOTENAME(@TargetDatabase) + N'.sys.columns AS c
                    ON t.object_id = c.object_id
                INNER JOIN ' + QUOTENAME(@TargetDatabase) + N'.sys.types AS ty
                    ON c.user_type_id = ty.user_type_id
                WHERE t.is_ms_shipped = 0;';

            EXEC sys.sp_executesql @SQL;
        END
        ELSE
        BEGIN
            SET @SQL = N'
                SELECT
                    s.name,
                    t.name,
                    c.name,
                    ty.name,
                    NULL,
                    c.max_length,
                    NULL,
                    c.precision,
                    c.scale,
                    c.is_nullable,
                    c.is_identity
                FROM ' + QUOTENAME(@LinkedServer) + N'.' +
                           QUOTENAME(@TargetDatabase) + N'.sys.tables AS t
                INNER JOIN ' + QUOTENAME(@LinkedServer) + N'.' +
                                QUOTENAME(@TargetDatabase) + N'.sys.schemas AS s
                    ON t.schema_id = s.schema_id
                INNER JOIN ' + QUOTENAME(@LinkedServer) + N'.' +
                                QUOTENAME(@TargetDatabase) + N'.sys.columns AS c
                    ON t.object_id = c.object_id
                INNER JOIN ' + QUOTENAME(@LinkedServer) + N'.' +
                                QUOTENAME(@TargetDatabase) + N'.sys.types AS ty
                    ON c.user_type_id = ty.user_type_id
                WHERE t.is_ms_shipped = 0;';

            INSERT INTO #TargetMetadata
            (
                SchemaName,
                TableName,
                ColumnName,
                BaseDataType,
                TypeDefinition,
                MaxLengthBytes,
                LogicalLength,
                PrecisionValue,
                ScaleValue,
                IsNullable,
                IsIdentity
            )
            EXEC sys.sp_executesql @SQL;
        END;


        /*
        -----------------------------------------------------------------------
         Convert raw metadata into human-readable type definitions.
        -----------------------------------------------------------------------
        */
        UPDATE M
        SET
            LogicalLength =
                CASE
                    WHEN BaseDataType IN
                        (N'varchar',N'char',N'varbinary',N'binary')
                        THEN CASE WHEN MaxLengthBytes = -1
                                  THEN -1 ELSE MaxLengthBytes END

                    WHEN BaseDataType IN (N'nvarchar',N'nchar')
                        THEN CASE WHEN MaxLengthBytes = -1
                                  THEN -1 ELSE MaxLengthBytes / 2 END

                    ELSE NULL
                END,

            TypeDefinition =
                CASE
                    WHEN BaseDataType IN
                        (N'varchar',N'char',N'varbinary',N'binary')
                        THEN BaseDataType + N'(' +
                             CASE WHEN MaxLengthBytes = -1
                                  THEN N'max'
                                  ELSE CONVERT(NVARCHAR(20),MaxLengthBytes)
                             END + N')'

                    WHEN BaseDataType IN (N'nvarchar',N'nchar')
                        THEN BaseDataType + N'(' +
                             CASE WHEN MaxLengthBytes = -1
                                  THEN N'max'
                                  ELSE CONVERT(NVARCHAR(20),MaxLengthBytes / 2)
                             END + N')'

                    WHEN BaseDataType IN (N'decimal',N'numeric')
                        THEN BaseDataType + N'(' +
                             CONVERT(NVARCHAR(20),PrecisionValue) + N',' +
                             CONVERT(NVARCHAR(20),ScaleValue) + N')'

                    WHEN BaseDataType = N'float'
                        THEN BaseDataType + N'(' +
                             CONVERT(NVARCHAR(20),PrecisionValue) + N')'

                    WHEN BaseDataType IN
                        (N'datetime2',N'datetimeoffset',N'time')
                        THEN BaseDataType + N'(' +
                             CONVERT(NVARCHAR(20),ScaleValue) + N')'

                    ELSE BaseDataType
                END
        FROM #SourceMetadata AS M;


        UPDATE M
        SET
            LogicalLength =
                CASE
                    WHEN BaseDataType IN
                        (N'varchar',N'char',N'varbinary',N'binary')
                        THEN CASE WHEN MaxLengthBytes = -1
                                  THEN -1 ELSE MaxLengthBytes END

                    WHEN BaseDataType IN (N'nvarchar',N'nchar')
                        THEN CASE WHEN MaxLengthBytes = -1
                                  THEN -1 ELSE MaxLengthBytes / 2 END

                    ELSE NULL
                END,

            TypeDefinition =
                CASE
                    WHEN BaseDataType IN
                        (N'varchar',N'char',N'varbinary',N'binary')
                        THEN BaseDataType + N'(' +
                             CASE WHEN MaxLengthBytes = -1
                                  THEN N'max'
                                  ELSE CONVERT(NVARCHAR(20),MaxLengthBytes)
                             END + N')'

                    WHEN BaseDataType IN (N'nvarchar',N'nchar')
                        THEN BaseDataType + N'(' +
                             CASE WHEN MaxLengthBytes = -1
                                  THEN N'max'
                                  ELSE CONVERT(NVARCHAR(20),MaxLengthBytes / 2)
                             END + N')'

                    WHEN BaseDataType IN (N'decimal',N'numeric')
                        THEN BaseDataType + N'(' +
                             CONVERT(NVARCHAR(20),PrecisionValue) + N',' +
                             CONVERT(NVARCHAR(20),ScaleValue) + N')'

                    WHEN BaseDataType = N'float'
                        THEN BaseDataType + N'(' +
                             CONVERT(NVARCHAR(20),PrecisionValue) + N')'

                    WHEN BaseDataType IN
                        (N'datetime2',N'datetimeoffset',N'time')
                        THEN BaseDataType + N'(' +
                             CONVERT(NVARCHAR(20),ScaleValue) + N')'

                    ELSE BaseDataType
                END
        FROM #TargetMetadata AS M;


        /*
        -----------------------------------------------------------------------
         Identify tables that exist on both sides.
        -----------------------------------------------------------------------
        */
        INSERT INTO #CommonTables (SchemaName, TableName)
        SELECT S.SchemaName, S.TableName
        FROM #SourceTables AS S
        INNER JOIN #TargetTables AS T
            ON T.SchemaName = S.SchemaName
           AND T.TableName  = S.TableName;


        /*
        -----------------------------------------------------------------------
         Report completely missing tables once per table.
        -----------------------------------------------------------------------
        */
        INSERT INTO dbo.SchemaCompare_Result
        (
            RunID,
            SchemaName,
            TableName,
            ColumnName,
            DifferenceType,
            SourceDataType,
            TargetDataType,
            SourceLength,
            TargetLength,
            SourceNullable,
            TargetNullable,
            SourceIdentity,
            TargetIdentity
        )
        SELECT
            @RunID,
            COALESCE(S.SchemaName,T.SchemaName),
            COALESCE(S.TableName,T.TableName),
            NULL,
            CASE
                WHEN S.TableName IS NULL THEN 'Table Missing In Source'
                WHEN T.TableName IS NULL THEN 'Table Missing In Target'
            END,
            CASE WHEN S.TableName IS NOT NULL THEN N'TABLE EXISTS' END,
            CASE WHEN T.TableName IS NOT NULL THEN N'TABLE EXISTS' END,
            NULL,NULL,NULL,NULL,NULL,NULL
        FROM #SourceTables AS S
        FULL OUTER JOIN #TargetTables AS T
            ON T.SchemaName = S.SchemaName
           AND T.TableName  = S.TableName
        WHERE S.TableName IS NULL
           OR T.TableName IS NULL;


        /*
        -----------------------------------------------------------------------
         Compare columns only for tables existing on both sides.

         CROSS APPLY allows multiple differences for the same column to be
         preserved independently.
        -----------------------------------------------------------------------
        */
        ;WITH ColumnComparison AS
        (
            SELECT
                COALESCE(S.SchemaName,T.SchemaName) AS SchemaName,
                COALESCE(S.TableName,T.TableName)   AS TableName,
                COALESCE(S.ColumnName,T.ColumnName) AS ColumnName,

                S.BaseDataType    AS SourceBaseDataType,
                T.BaseDataType    AS TargetBaseDataType,

                S.TypeDefinition  AS SourceTypeDefinition,
                T.TypeDefinition  AS TargetTypeDefinition,

                S.LogicalLength   AS SourceLogicalLength,
                T.LogicalLength   AS TargetLogicalLength,

                S.PrecisionValue  AS SourcePrecision,
                T.PrecisionValue  AS TargetPrecision,

                S.ScaleValue      AS SourceScale,
                T.ScaleValue      AS TargetScale,

                S.IsNullable      AS SourceNullable,
                T.IsNullable      AS TargetNullable,

                S.IsIdentity      AS SourceIdentity,
                T.IsIdentity      AS TargetIdentity,

                CASE WHEN S.ColumnName IS NULL THEN 1 ELSE 0 END AS MissingInSource,
                CASE WHEN T.ColumnName IS NULL THEN 1 ELSE 0 END AS MissingInTarget

            FROM #SourceMetadata AS S
            FULL OUTER JOIN #TargetMetadata AS T
                ON T.SchemaName = S.SchemaName
               AND T.TableName  = S.TableName
               AND T.ColumnName = S.ColumnName

            WHERE EXISTS
            (
                SELECT 1
                FROM #CommonTables AS C
                WHERE C.SchemaName = COALESCE(S.SchemaName,T.SchemaName)
                  AND C.TableName  = COALESCE(S.TableName,T.TableName)
            )
        )
        INSERT INTO dbo.SchemaCompare_Result
        (
            RunID,
            SchemaName,
            TableName,
            ColumnName,
            DifferenceType,
            SourceDataType,
            TargetDataType,
            SourceLength,
            TargetLength,
            SourceNullable,
            TargetNullable,
            SourceIdentity,
            TargetIdentity
        )
        SELECT
            @RunID,
            C.SchemaName,
            C.TableName,
            C.ColumnName,
            D.DifferenceType,
            C.SourceTypeDefinition,
            C.TargetTypeDefinition,
            C.SourceLogicalLength,
            C.TargetLogicalLength,
            C.SourceNullable,
            C.TargetNullable,
            C.SourceIdentity,
            C.TargetIdentity
        FROM ColumnComparison AS C
        CROSS APPLY
        (
            VALUES
            (
                'Column Missing In Source',
                CASE WHEN C.MissingInSource = 1 THEN 1 ELSE 0 END
            ),
            (
                'Column Missing In Target',
                CASE WHEN C.MissingInTarget = 1 THEN 1 ELSE 0 END
            ),
            (
                'Datatype Difference',
                CASE
                    WHEN C.MissingInSource = 0
                     AND C.MissingInTarget = 0
                     AND C.SourceBaseDataType <> C.TargetBaseDataType
                    THEN 1 ELSE 0
                END
            ),
            (
                'Length Difference',
                CASE
                    WHEN C.MissingInSource = 0
                     AND C.MissingInTarget = 0
                     AND C.SourceBaseDataType = C.TargetBaseDataType
                     AND C.SourceBaseDataType IN
                         (N'varchar',N'nvarchar',N'char',N'nchar',
                          N'varbinary',N'binary')
                     AND ISNULL(C.SourceLogicalLength,-2147483648)
                         <> ISNULL(C.TargetLogicalLength,-2147483648)
                    THEN 1 ELSE 0
                END
            ),
            (
                'Precision/Scale Difference',
                CASE
                    WHEN C.MissingInSource = 0
                     AND C.MissingInTarget = 0
                     AND C.SourceBaseDataType = C.TargetBaseDataType
                     AND
                     (
                         (
                             C.SourceBaseDataType IN (N'decimal',N'numeric')
                             AND
                             (
                                 ISNULL(C.SourcePrecision,0) <> ISNULL(C.TargetPrecision,0)
                                 OR
                                 ISNULL(C.SourceScale,0) <> ISNULL(C.TargetScale,0)
                             )
                         )
                         OR
                         (
                             C.SourceBaseDataType = N'float'
                             AND ISNULL(C.SourcePrecision,0)
                                 <> ISNULL(C.TargetPrecision,0)
                         )
                         OR
                         (
                             C.SourceBaseDataType IN
                                 (N'datetime2',N'datetimeoffset',N'time')
                             AND ISNULL(C.SourceScale,0)
                                 <> ISNULL(C.TargetScale,0)
                         )
                     )
                    THEN 1 ELSE 0
                END
            ),
            (
                'Nullable Difference',
                CASE
                    WHEN C.MissingInSource = 0
                     AND C.MissingInTarget = 0
                     AND C.SourceNullable <> C.TargetNullable
                    THEN 1 ELSE 0
                END
            ),
            (
                'Identity Difference',
                CASE
                    WHEN C.MissingInSource = 0
                     AND C.MissingInTarget = 0
                     AND C.SourceIdentity <> C.TargetIdentity
                    THEN 1 ELSE 0
                END
            )
        ) AS D(DifferenceType, IsDifferent)
        WHERE D.IsDifferent = 1;


        /*
        -----------------------------------------------------------------------
         Remote mode only:
         Remove the temporary Linked Server after comparison.
        -----------------------------------------------------------------------
        */
        IF @IsRemote = 1
        BEGIN
            EXEC master.dbo.sp_dropserver
                @server     = @LinkedServer,
                @droplogins = N'droplogins';
        END;


        /*
        -----------------------------------------------------------------------
         Mark the run as successful.
        -----------------------------------------------------------------------
        */
        UPDATE dbo.SchemaCompare_Run
        SET
            EndTime = SYSDATETIME(),
            Status  = 'SUCCESS'
        WHERE RunID = @RunID;


        /*
        -----------------------------------------------------------------------
         Return differences for this run.
        -----------------------------------------------------------------------
        */
        SELECT
            ID,
            RunID,
            SchemaName,
            TableName,
            ColumnName,
            DifferenceType,
            SourceDataType,
            TargetDataType,
            SourceLength,
            TargetLength,
            SourceNullable,
            TargetNullable,
            SourceIdentity,
            TargetIdentity
        FROM dbo.SchemaCompare_Result
        WHERE RunID = @RunID
        ORDER BY
            SchemaName,
            TableName,
            ColumnName,
            DifferenceType;


    END TRY

    BEGIN CATCH

        SET @ErrorMessage = ERROR_MESSAGE();

        /*
        -----------------------------------------------------------------------
         Best-effort Linked Server cleanup only if remote mode created one.
        -----------------------------------------------------------------------
        */
        IF @IsRemote = 1 AND @LinkedServer IS NOT NULL
        BEGIN
            BEGIN TRY
                IF EXISTS
                (
                    SELECT 1
                    FROM sys.servers
                    WHERE name = @LinkedServer
                )
                BEGIN
                    EXEC master.dbo.sp_dropserver
                        @server     = @LinkedServer,
                        @droplogins = N'droplogins';
                END;
            END TRY
            BEGIN CATCH
                -- Do not hide the original error with a cleanup error.
            END CATCH;
        END;


        /*
        -----------------------------------------------------------------------
         Save failure information if the run-history table exists.
        -----------------------------------------------------------------------
        */
        IF OBJECT_ID(N'dbo.SchemaCompare_Run', N'U') IS NOT NULL
           AND EXISTS
           (
               SELECT 1
               FROM dbo.SchemaCompare_Run
               WHERE RunID = @RunID
           )
        BEGIN
            UPDATE dbo.SchemaCompare_Run
            SET
                EndTime      = SYSDATETIME(),
                Status       = 'FAILED',
                ErrorMessage = @ErrorMessage
            WHERE RunID = @RunID;
        END;


        THROW;

    END CATCH;
END;
GO
