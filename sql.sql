-- Check current user and permissions
SELECT 
    CURRENT_USER as CurrentUser,
    IS_SRVROLEMEMBER('sysadmin') as IsSysAdmin,
    IS_MEMBER('db_owner') as IsDbOwner,
    IS_MEMBER('db_ddladmin') as IsDbDDLAdmin

-- Check specific permissions for UPDATE STATISTICS
SELECT 
    p.permission_name,
    p.state_desc
FROM sys.database_permissions p
INNER JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE dp.name = USER_NAME()
AND p.permission_name IN ('UPDATE STATISTICS', 'ALTER', 'CONTROL')

-- Test if you can actually run the operations manually
-- (Run these one at a time to see if they work)
UPDATE STATISTICS [dbo].[Cipher] -- Replace with actual table name
-- or
EXEC sp_updatestats

-- Test index rebuild permission (replace with actual table)
ALTER INDEX ALL ON [dbo].[Cipher] REBUILD







step 2
-- Test the exact operations the jobs perform
-- This should match what's in your IMaintenanceRepository implementation

-- For DatabaseUpdateStatisticsJob:
EXEC sp_updatestats  -- Basic version
-- OR find the specific implementation in your Bitwarden codebase

-- For DatabaseRebuildlIndexesJob:
-- Check what indexes exist first
SELECT 
    OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc,
    s.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.avg_fragmentation_in_percent > 10
ORDER BY s.avg_fragmentation_in_percent DESC


step3
-- Look for Quartz tables (if using persistent job store)
SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_NAME LIKE 'QRTZ_%'

-- If Quartz tables exist, check scheduled jobs
SELECT 
    SCHED_NAME,
    JOB_NAME,
    JOB_GROUP,
    JOB_CLASS_NAME,
    IS_DURABLE,
    IS_NONCONCURRENT,
    IS_UPDATE_DATA
FROM QRTZ_JOB_DETAILS
WHERE JOB_NAME LIKE '%Database%'

-- Check triggers
SELECT 
    SCHED_NAME,
    TRIGGER_NAME,
    TRIGGER_GROUP,
    JOB_NAME,
    JOB_GROUP,
    NEXT_FIRE_TIME,
    PREV_FIRE_TIME,
    TRIGGER_STATE
FROM QRTZ_TRIGGERS
WHERE JOB_NAME LIKE '%Database%'
