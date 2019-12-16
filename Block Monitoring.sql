-- Blocking tree
SET NOCOUNT ON
GO
SELECT SPID, BLOCKED, REPLACE (REPLACE (T.TEXT, CHAR(10), ' '), CHAR (13), ' ' ) AS BATCH
INTO #T
FROM sys.sysprocesses R CROSS APPLY sys.dm_exec_sql_text(R.SQL_HANDLE) T
GO
WITH
    BLOCKERS (SPID, BLOCKED, LEVEL, BATCH)
    AS
    (
                    SELECT SPID,
                BLOCKED,
                CAST (REPLICATE ('0', 4-LEN (CAST (SPID AS VARCHAR))) + CAST (SPID AS VARCHAR) AS VARCHAR (1000)) AS LEVEL,
                BATCH
            FROM #T R
            WHERE (BLOCKED = 0 OR BLOCKED = SPID)
                AND EXISTS (SELECT *
                FROM #T R2
                WHERE R2.BLOCKED = R.SPID AND R2.BLOCKED <> R2.SPID)
        UNION ALL
            SELECT R.SPID,
                R.BLOCKED,
                CAST (BLOCKERS.LEVEL + RIGHT (CAST ((1000 + R.SPID) AS VARCHAR (100)), 4) AS VARCHAR (1000)) AS LEVEL,
                R.BATCH
            FROM #T AS R
                INNER JOIN BLOCKERS ON R.BLOCKED = BLOCKERS.SPID
            WHERE R.BLOCKED > 0 AND R.BLOCKED <> R.SPID
    )
SELECT N'    ' + REPLICATE (N'|         ', LEN (LEVEL)/4 - 1) +
CASE WHEN (LEN(LEVEL)/4 - 1) = 0
THEN 'HEAD -  '
ELSE '|------  ' END
+ CAST (SPID AS NVARCHAR (10)) + N' ' + BATCH AS BLOCKING_TREE
FROM BLOCKERS
ORDER BY LEVEL ASC
GO
DROP TABLE #T
GO

-- Blocked queries
SELECT s.session_id,
    r.status,
    r.blocking_session_id                                 'Blk by',
    r.wait_type,
    wait_resource,
    r.wait_time / (1000.0)                             'Wait Sec',
    r.cpu_time,
    r.logical_reads,
    r.reads,
    r.writes,
    r.total_elapsed_time / (1000.0)                    'Elaps Sec',
    Substring(st.TEXT,(r.statement_start_offset / 2) + 1,
                    ((CASE r.statement_end_offset
                        WHEN -1
                        THEN Datalength(st.TEXT)
                        ELSE r.statement_end_offset
                        END - r.statement_start_offset) / 2) + 1) AS statement_text,
    Coalesce(Quotename(Db_name(st.dbid)) + N'.' + Quotename(Object_schema_name(st.objectid,st.dbid)) + N'.' + Quotename(Object_name(st.objectid,st.dbid)),
                    '') AS command_text,
    r.command,
    s.login_name,
    s.host_name,
    s.program_name,
    s.last_request_end_time,
    s.login_time,
    r.open_transaction_count
FROM sys.dm_exec_sessions AS s
    JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
            CROSS APPLY sys.Dm_exec_sql_text(r.sql_handle) AS st
WHERE    r.session_id != @@SPID
ORDER BY r.cpu_time desc, r.status,
            r.blocking_session_id,
            s.session_id


-- Block with query by SPID
DECLARE @SPID INT = _REPLACE_WITH_SPID_
IF OBJECT_ID('TEMPDB..#sp_who2') is not null DROP TABLE #sp_who2
CREATE TABLE #sp_who2 (
  SPID INT
, Status VARCHAR(255)
, Login  VARCHAR(255)
, HostName  VARCHAR(255)
, BlkBy  VARCHAR(255)
, DBName  VARCHAR(255)
, Command VARCHAR(255)
, CPUTime INT
, DiskIO INT
, LastBatch VARCHAR(255)
, ProgramName VARCHAR(255)
, SPID2 INT
, REQUESTID INT
)
INSERT INTO #sp_who2 EXEC sp_who2
 
SELECT DISTINCT w.*, text = CAST(t.text AS NVARCHAR(100))
FROM #sp_who2 w
LEFT JOIN sys.sysprocesses p on w.SPID = p.SPID
CROSS APPLY ::fn_get_sql(p.sql_handle) t
where BlkBy <> '  .'
OR w.SPID = @SPID
ORDER BY w.BlkBy desc, w.SPID desc
  
DROP TABLE #sp_who2
 
DECLARE @sqltext VARBINARY(128)
SELECT @sqltext = sql_handle
FROM sys.sysprocesses
WHERE spid = @SPID
SELECT TEXT
FROM ::fn_get_sql(@sqltext)
GO


-- Head blocker
SELECT
    [Session ID]    = s.session_id,
    [User Process]  = CONVERT(CHAR(1), s.is_user_process),
    [Login]         = s.login_name,
    [Database]      = case when p.dbid=0 then N'' else ISNULL(db_name(p.dbid),N'') end,
    [Task State]    = ISNULL(t.task_state, N''),
    [Command]       = ISNULL(r.command, N''),
    [Application]   = ISNULL(s.program_name, N''),
    [Wait Time (ms)]     = ISNULL(w.wait_duration_ms, 0),
    [Wait Type]     = ISNULL(w.wait_type, N''),
    [Wait Resource] = ISNULL(w.resource_description, N''),
    [Blocked By]    = ISNULL(CONVERT (varchar, w.blocking_session_id), ''),
    [Head Blocker]  =
        CASE
            -- session has an active request, is blocked, but is blocking others or session is idle but has an open tran and is blocking others
            WHEN r2.session_id IS NOT NULL AND (r.blocking_session_id = 0 OR r.session_id IS NULL) THEN '1'
            -- session is either not blocking someone, or is blocking someone but is blocked by another party
            ELSE ''
        END,
    [Total CPU (ms)] = s.cpu_time,
    [Total Physical I/O (MB)]   = (s.reads + s.writes) * 8 / 1024,
    [Memory Use (KB)]  = s.memory_usage * (8192 / 1024),
    [Open Transactions] = ISNULL(r.open_transaction_count,0),
    [Login Time]    = s.login_time,
    [Last Request Start Time] = s.last_request_start_time,
    [Host Name]     = ISNULL(s.host_name, N''),
    [Net Address]   = ISNULL(c.client_net_address, N''),
    [Execution Context ID] = ISNULL(t.exec_context_id, 0),
    [Request ID] = ISNULL(r.request_id, 0),
    [Workload Group] = ISNULL(g.name, N'')
FROM sys.dm_exec_sessions s LEFT OUTER JOIN sys.dm_exec_connections c ON (s.session_id = c.session_id)
    LEFT OUTER JOIN sys.dm_exec_requests r ON (s.session_id = r.session_id)
    LEFT OUTER JOIN sys.dm_os_tasks t ON (r.session_id = t.session_id AND r.request_id = t.request_id)
    LEFT OUTER JOIN
    (
    -- In some cases (e.g. parallel queries, also waiting for a worker), one thread can be flagged as
    -- waiting for several different threads.  This will cause that thread to show up in multiple rows
    -- in our grid, which we don't want.  Use ROW_NUMBER to select the longest wait for each thread,
    -- and use it as representative of the other wait relationships this thread is involved in.
    SELECT *, ROW_NUMBER() OVER (PARTITION BY waiting_task_address ORDER BY wait_duration_ms DESC) AS row_num
    FROM sys.dm_os_waiting_tasks
) w ON (t.task_address = w.waiting_task_address) AND w.row_num = 1
    LEFT OUTER JOIN sys.dm_exec_requests r2 ON (s.session_id = r2.blocking_session_id)
    LEFT OUTER JOIN sys.dm_resource_governor_workload_groups g ON (g.group_id = s.group_id)
    LEFT OUTER JOIN sys.sysprocesses p ON (s.session_id = p.spid)
WHERE r2.session_id IS NOT NULL AND (r.blocking_session_id = 0 OR r.session_id IS NULL)

ORDER BY s.session_id;