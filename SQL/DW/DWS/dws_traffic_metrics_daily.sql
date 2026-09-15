
/*
=======================================================================
1. 流量指标
PV：页面浏览量(Page View)，每次浏览行为计 1 次。
UV：独立访客数(Unique Visitor)，一个用户一天内多次访问只计 1 个 UV。 
人均访问页面数：平均每个用户浏览的页面数量，反映用户访问深度，PV / UV。
跳出率：只访问了一个页面(单次浏览)的用户占比，衡量流量质量。近似口径，因无会话 ID，用"当日仅 1 次 pv 的用户"近似"跳出用户"。

每日用户行为分析
=======================================================================
*/
-- 创建 DWS 层表，表名：dws_traffic_metrics_daily 每日流量核心指标汇总表
CREATE TABLE IF NOT EXISTS dws_traffic_metrics_daily (
    pv BIGINT COMMENT '页面浏览量(pv次数)',
    uv BIGINT COMMENT '独立访客数(去重用户数)',
    visit_depth DOUBLE COMMENT '人均访问页面数(PV/UV)',
    bounce_rate DOUBLE COMMENT '跳出率(仅1次pv的用户占比)'
)
COMMENT '每日流量核心指标表'
PARTITIONED BY (
    dt STRING COMMENT '统计日期：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
1. dws_traffic_metrics_daily

dt
pv：页面浏览量(Page View)，每次浏览行为计 1 次。
uv：独立访客数(Unique Visitor)，一个用户一天内多次访问只计 1 个 UV。 
visit_depth：平均每个用户浏览的页面数量，反映用户访问深度，PV / UV。
bounce_rate：只访问了一个页面(单次浏览)的用户占比，衡量流量质量。近似口径，因无会话 ID，用"当日仅 1 次 pv 的用户"近似"跳出用户"。
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE dws_traffic_metrics_daily PARTITION (dt)
WITH pv_count AS(
    SELECT 
        event_date,
        user_id,
        SUM(CASE WHEN behavior_type = 'pv' THEN 1 ELSE 0 END) AS pv_cnt
    FROM dwd_user_behavior_detail 
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    GROUP BY event_date, user_id
)
SELECT
    SUM(pv_cnt) AS pv,
    COUNT(DISTINCT user_id) AS uv,
    CASE WHEN COUNT(DISTINCT user_id) = 0 THEN 0
         ELSE SUM(pv_cnt) / COUNT(DISTINCT user_id)
         END AS visit_depth,
    CASE WHEN SUM(pv_cnt) = 0 THEN 0
         ELSE SUM(CASE WHEN pv_cnt = 1 THEN 1 ELSE 0 END) / SUM(CASE WHEN pv_cnt > 0 THEN 1 ELSE 0 END)
         END AS bounce_rate,

    event_date AS dt
FROM pv_count 
GROUP BY event_date;

-- DataWorks 需要显示指定分区，首次同步时为全量同步，需要授权全表扫描，如未授权可以使用选择全部分区
-- SHOW PARTITIONS dwd_user_behavior_detail;

-- 检查下 dws_traffic_metrics_daily 中是否有数据
-- SELECT 
--     *
-- FROM dws_traffic_metrics_daily 
-- WHERE dt BETWEEN '1970-01-01' AND '1979-03-16';

-- SELECT 
--     *
-- FROM dws_traffic_metrics_daily 
-- WHERE dt BETWEEN '2025-01-01' AND '2037-04-09';


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE dws_traffic_metrics_daily PARTITION (dt = '${dt}')
WITH pv_count AS(
    SELECT 
        dt,
        user_id,
        SUM(CASE WHEN behavior_type = 'pv' THEN 1 ELSE 0 END) AS pv_cnt
    FROM dwd_user_behavior_detail 
    WHERE dt = '${dt}'
    GROUP BY dt, user_id
)
SELECT
    SUM(pv_cnt) AS pv,
    COUNT(DISTINCT user_id) AS uv,
    CASE WHEN COUNT(DISTINCT user_id) = 0 THEN 0
         ELSE SUM(pv_cnt) / COUNT(DISTINCT user_id)
         END AS visit_depth,
    CASE WHEN SUM(pv_cnt) = 0 THEN 0
         ELSE SUM(CASE WHEN pv_cnt = 1 THEN 1 ELSE 0 END) / SUM(CASE WHEN pv_cnt > 0 THEN 1 ELSE 0 END)
         END AS bounce_rate
FROM pv_count 
GROUP BY dt;
