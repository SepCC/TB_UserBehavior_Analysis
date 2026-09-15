
/*
=======================================================================
3. 用户留存指标
定义：在基准日活跃的用户中，在后续第 N 天仍然活跃的用户占比。
活跃口径：当日发生任意行为(pv，fav，cart，buy)即视为活跃。

次日留存率：基准日活跃用户中，基准日次日仍活跃的用户占比。
3 日留存率：基准日活跃用户中，基准日后第 3 天仍活跃的用户占比。
7 日留存率：基准日活跃用户中，基准日后第 7 天仍活跃的用户占比。
*/
-- 创建 DWS 层表，表名：dws_retention_metrics_daily 每日用户留存指标汇总表
CREATE TABLE IF NOT EXISTS dws_retention_metrics_daily (
    active_uv BIGINT COMMENT '基准日活跃用户数',
    retention_1d DOUBLE COMMENT '次日留存率',
    retention_3d DOUBLE COMMENT '3日留存率',
    retention_7d DOUBLE COMMENT '7日留存率'
)
COMMENT '每日用户留存指标汇总表'
PARTITIONED BY (
    dt STRING COMMENT '基准日期(用户活跃日期)：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
3. dws_retention_metrics_daily

dt
active_uv：当日发生任意行为(pv，fav，cart，buy)即视为活跃。
retention_1d：基准日活跃用户中，基准日次日仍活跃的用户占比。
retention_3d：基准日活跃用户中，基准日后第 3 天仍活跃的用户占比。
retention_7d：基准日活跃用户中，基准日后第 7 天仍活跃的用户占比。
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE dws_retention_metrics_daily PARTITION (dt)
WITH drop_duplicate_data AS (
    SELECT
        dt,
        user_id
    FROM dwd_user_behavior_detail 
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
        AND behavior_type IN ('pv', 'buy', 'cart', 'fav')
    GROUP BY dt, user_id
),
retention_data AS (
    SELECT
        T.dt,
        COUNT(T.user_id) AS active_uv,
        COUNT(N1.user_id) AS retention_1d_uv,
        COUNT(N3.user_id) AS retention_3d_uv,
        COUNT(N7.user_id) AS retention_7d_uv
    FROM drop_duplicate_data T
    LEFT JOIN drop_duplicate_data AS N1
        ON T.user_id = N1.user_id
        AND N1.dt = TO_CHAR(DATE_ADD(TO_DATE(T.dt, 'yyyy-MM-dd'),  1), 'yyyy-MM-dd')
    LEFT JOIN drop_duplicate_data AS N3
        ON T.user_id = N3.user_id
        AND N3.dt = TO_CHAR(DATE_ADD(TO_DATE(T.dt, 'yyyy-MM-dd'),  3), 'yyyy-MM-dd')
    LEFT JOIN drop_duplicate_data AS N7
        ON T.user_id = N7.user_id
        AND N7.dt = TO_CHAR(DATE_ADD(TO_DATE(T.dt, 'yyyy-MM-dd'),  7), 'yyyy-MM-dd')
    GROUP BY T.dt
)
SELECT 
    active_uv,
    CASE WHEN active_uv > 0 THEN CAST(retention_1d_uv AS DOUBLE) / active_uv
         ELSE 0
         END AS retention_1d,
    CASE WHEN active_uv > 0 THEN CAST(retention_3d_uv AS DOUBLE) / active_uv
         ELSE 0
         END AS retention_3d,
    CASE WHEN active_uv > 0 THEN CAST(retention_7d_uv AS DOUBLE) / active_uv
         ELSE 0
         END AS retention_7d,
    
    dt
FROM retention_data;

-- 检查下 dws_retention_metrics_daily 中是否有数据
-- SELECT 
--     *
-- FROM dws_retention_metrics_daily
-- WHERE dt BETWEEN '1970-01-01' AND '1979-03-16';


-- 每日调度，静态分区 + 参数，数据补数，dt_sub_7 = $[yyyy-MM-dd-7]
INSERT OVERWRITE TABLE dws_retention_metrics_daily PARTITION (dt = '${dt_sub_7}')
WITH drop_duplicate_data AS (
    SELECT
        dt,
        user_id
    FROM dwd_user_behavior_detail 
    WHERE dt >= '${dt_sub_7}'
        AND behavior_type IN ('pv', 'buy', 'cart', 'fav')
    GROUP BY dt, user_id
),
retention_data AS (
    SELECT
        T.dt,
        COUNT(T.user_id) AS active_uv,
        COUNT(N1.user_id) AS retention_1d_uv,
        COUNT(N3.user_id) AS retention_3d_uv,
        COUNT(N7.user_id) AS retention_7d_uv
    FROM drop_duplicate_data T
    LEFT JOIN drop_duplicate_data AS N1
        ON T.user_id = N1.user_id
        AND N1.dt = TO_CHAR(DATE_ADD(TO_DATE(T.dt, 'yyyy-MM-dd'),  1), 'yyyy-MM-dd')
    LEFT JOIN drop_duplicate_data AS N3
        ON T.user_id = N3.user_id
        AND N3.dt = TO_CHAR(DATE_ADD(TO_DATE(T.dt, 'yyyy-MM-dd'),  3), 'yyyy-MM-dd')
    LEFT JOIN drop_duplicate_data AS N7
        ON T.user_id = N7.user_id
        AND N7.dt = TO_CHAR(DATE_ADD(TO_DATE(T.dt, 'yyyy-MM-dd'),  7), 'yyyy-MM-dd')
    GROUP BY T.dt
)
SELECT 
    active_uv,
    CASE WHEN active_uv > 0 THEN CAST(retention_1d_uv AS DOUBLE) / active_uv
         ELSE 0
         END AS retention_1d,
    CASE WHEN active_uv > 0 THEN CAST(retention_3d_uv AS DOUBLE) / active_uv
         ELSE 0
         END AS retention_3d,
    CASE WHEN active_uv > 0 THEN CAST(retention_7d_uv AS DOUBLE) / active_uv
         ELSE 0
         END AS retention_7d
FROM retention_data
WHERE dt = '${dt_sub_7}';
