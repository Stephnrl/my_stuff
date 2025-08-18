SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.fragment_count,
    ips.page_count,
    ips.last_update
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.last_update > DATEADD(day, -7, GETDATE())
ORDER BY ips.last_update DESC;


SELECT 
    t.name AS TableName,
    s.name AS StatName,
    STATS_DATE(s.object_id, s.stats_id) AS LastUpdated,
    s.auto_created,
    s.user_created
FROM sys.stats s
INNER JOIN sys.tables t ON s.object_id = t.object_id
WHERE STATS_DATE(s.object_id, s.stats_id) > DATEADD(day, -7, GETDATE())
ORDER BY STATS_DATE(s.object_id, s.stats_id) DESC;


EXEC xp_readerrorlog 0, 1, N'rebuild', N'index'
EXEC xp_readerrorlog 0, 1, N'statistics', N'update'






SELECT 
    operation,
    context,
    [transaction id],
    [begin time],
    [transaction name]
FROM fn_dblog(NULL, NULL)
WHERE operation IN ('LOP_BEGIN_XACT', 'LOP_COMMIT_XACT')
    AND [begin time] > DATEADD(hour, -48, GETDATE())
    AND [transaction name] LIKE '%maintenance%'
ORDER BY [begin time] DESC;
