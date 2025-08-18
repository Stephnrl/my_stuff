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
    AND OBJECT_NAME(ips.object_id) NOT LIKE 'Azure%'  -- Exclude Azure system tables
    AND OBJECT_NAME(ips.object_id) IN (
        SELECT TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_SCHEMA = 'dbo'
    )
ORDER BY ips.last_update DESC;
