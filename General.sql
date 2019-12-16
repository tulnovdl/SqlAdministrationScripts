-- Select all users from Database role
SELECT DP1.name AS DatabaseRoleName,
    isnull (DP2.name, 'No members') AS DatabaseUserName
FROM sys.database_role_members AS DRM
    RIGHT OUTER JOIN sys.database_principals AS DP1
    ON DRM.role_principal_id = DP1.principal_id
    LEFT OUTER JOIN sys.database_principals AS DP2
    ON DRM.member_principal_id = DP2.principal_id
WHERE DP1.type = 'R' and (DP1.name = 'OGM' OR DP1.name = 'OGM' OR DP1.name = 'OGM')
ORDER BY DP1.name;


-- sp_who2 with filter
CREATE TABLE #sp_who2
(
    SPID INT,
    Status VARCHAR(255),
    Login VARCHAR(255),
    HostName VARCHAR(255),
    BlkBy VARCHAR(255),
    DBName VARCHAR(255),
    Command VARCHAR(255),
    CPUTime INT,
    DiskIO INT,
    LastBatch VARCHAR(255),
    ProgramName VARCHAR(255),
    SPID2 INT,
    REQUESTID INT
)
INSERT INTO #sp_who2
EXEC sp_who2
SELECT *
FROM #sp_who2
WHERE       Login = 'testuser'
ORDER BY    DBName ASC

DROP TABLE #sp_who2


-- Query by SPID
DECLARE @sqltext VARBINARY(128)
SELECT @sqltext = sql_handle
FROM sys.sysprocesses
WHERE spid = @SPID
SELECT TEXT
FROM ::fn_get_sql(@sqltext)
GO


-- Copy users from application role 'A' to application role 'B'
Use %DATABASE%

DECLARE @user varchar(50)
DECLARE users_cursor CURSOR FOR
SELECT
    isnull (DP2.name, 'No members') AS DatabaseUserName
FROM [Metall].sys.database_role_members AS DRM
    RIGHT OUTER JOIN [Metall].sys.database_principals AS DP1
    ON DRM.role_principal_id = DP1.principal_id
    LEFT OUTER JOIN [Metall].sys.database_principals AS DP2
    ON DRM.member_principal_id = DP2.principal_id
WHERE DP1.type = 'R' and (DP1.name = 'ROLE1' OR DP1.name = 'ROLE2')
ORDER BY DP1.name;

OPEN users_cursor;
FETCH NEXT FROM users_cursor INTO @user
WHILE @@FETCH_STATUS = 0
BEGIN
    use Accountant
    execute sp_adduser @user
    exec sp_addrolemember 'ROLE3', @user;
    FETCH NEXT FROM users_cursor INTO @user
END
CLOSE users_cursor
DEALLOCATE users_cursor


-- Drop all users in database
DECLARE @user varchar(50)
DECLARE @usertodelete nvarchar(80);
DECLARE @schematodelete nvarchar(80);
DECLARE users_cursor CURSOR FOR
select name
from sys.sysusers
where islogin = 1
    and name not in ('INFORMATION_SCHEMA', 'dbo', 'sys', 'guest', 'AMK\Программисты', 'OCC')
order by name
OPEN users_cursor;
FETCH NEXT FROM users_cursor INTO @user
WHILE @@FETCH_STATUS = 0
BEGIN
    use Ledger
    set @usertodelete = 'drop user [' + @user + ']'
    set @schematodelete = 'drop schema [' + @user + ']'
    execute (@schematodelete)
    execute(@usertodelete)
    FETCH NEXT FROM users_cursor INTO @user
END
CLOSE users_cursor
DEALLOCATE users_cursor


-- Compare users in application roles
SELECT
    *
FROM (SELECT DISTINCT
        [Economic] = u.name
    FROM [Economic].sys.database_role_members ru
        LEFT JOIN [Economic].sys.database_principals r
        ON r.principal_id = ru.role_principal_id
        LEFT JOIN [Economic].sys.database_principals u
        ON u.principal_id = ru.member_principal_id
    WHERE r.name LIKE '%test1%'
        OR r.name LIKE '%test1%') Economic
    FULL OUTER JOIN (SELECT DISTINCT
        [economic2test] = u.name
    FROM [economic2test].sys.database_role_members ru
        LEFT JOIN [economic2test].sys.database_principals r
        ON r.principal_id = ru.role_principal_id
        LEFT JOIN [economic2test].sys.database_principals u
        ON u.principal_id = ru.member_principal_id
    WHERE r.name LIKE '%test2%'
        OR r.name LIKE '%test2%') Economic2test
    ON economic2test.economic2test = economic2test.[economic2test]
        /* WHERE economic2test.economic2test IS NULL    -- uncomment for missing users only */
        AND economic2test.[economic2test] NOT LIKE '%test2%'


-- Copy application role permission
declare @RoleName varchar(50) = 'role_name'
declare @Script varchar(max) = 'CREATE ROLE ' + @RoleName + char(13)
select
    @script = @script + 'GRANT ' + prm.permission_name + ' ON ' +
OBJECT_SCHEMA_NAME(major_id) + '.' + OBJECT_NAME(major_id) + ' TO ' + rol.name + char(13) COLLATE Latin1_General_CI_AS
from sys.database_permissions prm
    join sys.database_principals rol on
        prm.grantee_principal_id = rol.principal_id
where rol.name = @RoleName
print @script


-- TMG report #1
USE TMG_Logs
GO
DECLARE @IPint BIGINT ,@IP VARCHAR(15)
SELECT
    ClientUserName
   , dbo.parseIP(ClientIP) AS IP
   , DestHost
   , uri
   , bytesrecvd
   , bytessent

FROM WebProxyLog
WHERE logTime BETWEEN '2018-05-10' AND '2018-09-10'
    AND ClientUserName NOT LIKE 'anonymous'
    AND ClientUserName LIKE 'user%'

-- TMG report #2
Use TMG_Logs
GO
declare
  @Dtbegin varchar(16), @DtEnd varchar(16)
, @IPint bigint
, @IP varchar(15)
select
    @Dtbegin = '2018-01-03 00:00'
, @DtEnd = '2018-31-03 23:59'


select top 30
    TMG_Logs.dbo.getIP(WebProxyLog.ClientIP) as ИпКлиента,
    WebProxyLog.ClientUserName as ЮзернеймКлиента,
    ПолученоМбайт=cast(sum(bytessent)/1048576  as decimal(15, 2)),
    ОтправленоМбайт=cast(sum(BytesRECVD)/1048576  as decimal(15, 2))
from WebProxyLog with(nolock)
where logTime between @Dtbegin and @DtEnd and ClientUserName not like 'anonymous'
group by WebProxyLog.ClientIP, WebProxyLog.ClientUserName
ORDER BY ПолученоМбайт desc


-- Disk usage by database
use %DATABASE%
SELECT
    [TYPE] = A.TYPE_DESC
    , [FILE_Name] = A.name
    , [FILEGROUP_NAME] = fg.name
    , [File_Location] = A.PHYSICAL_NAME
    , [FILESIZE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0)
    , [USEDSPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - ((SIZE/128.0) - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0))
    , [FREESPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)
    , [FREESPACE_%] = CONVERT(DECIMAL(10,2),((A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)/(A.SIZE/128.0))*100)
    , [AutoGrow] = 'By ' + CASE is_percent_growth WHEN 0 THEN CAST(growth/128 AS VARCHAR(10)) + ' MB -'
        WHEN 1 THEN CAST(growth AS VARCHAR(10)) + '% -' ELSE '' END
        + CASE max_size WHEN 0 THEN 'DISABLED' WHEN -1 THEN ' Unrestricted'
            ELSE ' Restricted to ' + CAST(max_size/(128*1024) AS VARCHAR(10)) + ' GB' END
        + CASE is_percent_growth WHEN 1 THEN ' [autogrowth by percent, BAD setting!]' ELSE '' END
FROM sys.database_files A LEFT JOIN sys.filegroups fg ON A.data_space_id = fg.data_space_id
order by A.TYPE desc, A.NAME;


-- Full path to all DBs files
SELECT
    db.name AS DBName,
    type_desc AS FileType,
    Physical_Name AS Location
FROM
    sys.master_files mf
    INNER JOIN
    sys.databases db ON db.database_id = mf.database_id

-- Instance rename (restart needed)
DECLARE @SRVNAME varchar(255) = (select @@SERVERNAME)
exec sp_dropserver @SRVNAME
GO
exec sp_addserver [NEW_NAME] , local
GO

-- Shrink tempdb USE CAREFULLY
use tempdb
GO
DBCC FREEPROCCACHE
DBCC DROPCLEANBUFFERS
DBCC FREESYSTEMCACHE ('ALL')
DBCC FREESESSIONCACHE
DBCC SHRINKDATABASE(tempdb, 10);
dbcc shrinkfile ('tempdev')
dbcc shrinkfile ('templog') 
GO

-- Unlinked domain users
EXEC [sys].[sp_validatelogins]


-- recreate user on server and in each database
USE [master]
GO
DECLARE @domainLogin varchar(1000) = N'user'
DECLARE @drop NVARCHAR(1000)
SET @drop = N'DROP LOGIN [' + @domainLogin + ']'
DECLARE @create NVARCHAR(1000)
SET @create = N'CREATE LOGIN ['+ @domainLogin + '] FROM WINDOWS WITH DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[русский]'
exec(@drop)
exec(@create)
declare @dropFromDbs NVARCHAR(1000)
set @dropFromDbs = N'
USE ?;
IF  EXISTS (SELECT * FROM sys.database_principals WHERE name = N''' + @domainLogin + ''')
DROP USER [' + @domainLogin + ']'
EXEC sp_MSforeachdb @dropFromDbs


-- Clean replication from database
DECLARE @subscriptionDB AS sysname
SET @subscriptionDB = N'DATABASE'
USE master
EXEC sp_removedbreplication @subscriptionDB
GO
EXEC sp_MSforeachdb
@command1='
    USE master;
 EXEC sp_removedbreplication ?;
'

-- CPU stress test
USE master;
DROP TABLE #temp
SELECT MyInt = CONVERT(BIGINT, o1.object_id) + CONVERT(BIGINT, o2.object_id) + CONVERT(BIGINT, o3.object_id)
INTO #temp
FROM sys.objects o1
    JOIN sys.objects o2
    ON o1.object_id < o2.object_id
    JOIN sys.objects o3
    ON o1.object_id < o3.object_id;
SELECT SUM(CONVERT(BIGINT, o1.MyInt) + CONVERT(BIGINT, o2.MyInt))
FROM #temp o1
    JOIN #temp o2
    ON o1.MyInt < o2.MyInt;