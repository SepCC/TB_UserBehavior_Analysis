
/*
=======================================================================
2. 转化漏斗：浏览 → 收藏/加购 → 购买
第一步：pv，浏览。
第二步：fav/cart，收藏/加购，因为收藏与加购均为强意向行为，合并为一层。
第三步：buy，购买。

第一步 UV：统计周期内发生过浏览行为的去重用户数。
第二步 UV：第一步用户中，发生过收藏或加购行为的去重用户数。
第三步 UV：第二步用户中，发生过购买行为的去重用户数。
浏览 → 收藏/加购转化率：第二步 UV / 第一步 UV
收藏/加购 → 购买转化率：第三步 UV / 第二步 UV
整体转化率：第三步 UV / 第一步 UV
*/
-- 创建 DWS 层表，表名：dws_funnel_metrics_daily 每日转化漏斗指标汇总表
CREATE TABLE IF NOT EXISTS dws_funnel_metrics_daily (
    pv_uv BIGINT COMMENT '浏览用户数(pv去重)',
    fav_cart_uv BIGINT COMMENT '收藏或加购用户数(fav/cart去重)',
    buy_uv BIGINT COMMENT '购买用户数(buy去重)',
    pv_2_fav_cart_rate DOUBLE COMMENT '浏览 → 收藏/加购转化率',
    fav_cart_2_buy_rate DOUBLE COMMENT '收藏/加购 → 购买转化率',
    overall_rate DOUBLE COMMENT '整体转化率'
)
COMMENT '每日转化漏斗指标汇总表'
PARTITIONED BY (
    dt STRING COMMENT '统计日期：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
2. dws_funnel_metrics_daily

dt
pv_uv：统计周期内发生过浏览行为的去重用户数。
fav_cart_uv：第一步用户中，发生过收藏或加购行为的去重用户数。
buy_uv：第二步用户中，发生过购买行为的去重用户数。
pv_2_fav_cart_rate：第二步 UV / 第一步 UV
fav_cart_2_buy_rate：第三步 UV / 第二步 UV
overall_rate：第三步 UV / 第一步 UV
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE dws_funnel_metrics_daily PARTITION (dt)
WITH behavior_sign AS (
    SELECT
        dt,
        user_id,
        SUM(CASE WHEN behavior_type = 'pv' THEN 1 ELSE 0 END) AS pv_cnt,
        SUM(CASE WHEN behavior_type IN ('fav', 'cart') THEN 1 ELSE 0 END) AS fav_cart_cnt,
        SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) AS buy_cnt
    FROM dwd_user_behavior_detail 
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    GROUP BY dt, user_id
),
data_summary AS (
    SELECT
        dt,
        SUM(CASE WHEN pv_cnt > 0 THEN 1 
                 ELSE 0 
                 END) AS pv_uv,
        SUM(CASE WHEN pv_cnt > 0 AND fav_cart_cnt > 0 
                 THEN 1 ELSE 0 
                 END) AS fav_cart_uv,
        SUM(CASE WHEN pv_cnt > 0 AND fav_cart_cnt >0 AND buy_cnt > 0 
                 THEN 1 ELSE 0 
                 END) AS buy_uv
    FROM behavior_sign 
    GROUP BY dt
)
SELECT
    pv_uv,
    fav_cart_uv,
    buy_uv,
    CASE WHEN pv_uv > 0 THEN CAST(fav_cart_uv AS DOUBLE) / pv_uv
         ELSE 0
         END AS pv_2_fav_cart_rate,
    CASE WHEN fav_cart_uv > 0 THEN CAST(buy_uv AS DOUBLE) / fav_cart_uv
         ELSE 0
         END AS fav_cart_2_buy_rate,
    CASE WHEN pv_uv > 0 THEN CAST(buy_uv AS DOUBLE) / pv_uv
         ELSE 0
         END AS overall_rate,
    
    dt
FROM data_summary;

-- 检查下 dws_funnel_metrics_daily 中是否有数据
-- SELECT 
--     *
-- FROM dws_funnel_metrics_daily
-- WHERE dt BETWEEN '1970-01-01' AND '1979-03-16';


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE dws_funnel_metrics_daily PARTITION (dt = '${dt}')
WITH behavior_sign AS (
    SELECT
        dt,
        user_id,
        SUM(CASE WHEN behavior_type = 'pv' THEN 1 ELSE 0 END) AS pv_cnt,
        SUM(CASE WHEN behavior_type IN ('fav', 'cart') THEN 1 ELSE 0 END) AS fav_cart_cnt,
        SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) AS buy_cnt
    FROM dwd_user_behavior_detail 
    WHERE dt = '${dt}'
    GROUP BY dt, user_id
),
data_summary AS (
    SELECT
        dt,
        SUM(CASE WHEN pv_cnt > 0 THEN 1 
                 ELSE 0 
                 END) AS pv_uv,
        SUM(CASE WHEN pv_cnt > 0 AND fav_cart_cnt > 0 
                 THEN 1 ELSE 0 
                 END) AS fav_cart_uv,
        SUM(CASE WHEN pv_cnt > 0 AND fav_cart_cnt >0 AND buy_cnt > 0 
                 THEN 1 ELSE 0 
                 END) AS buy_uv
    FROM behavior_sign 
    GROUP BY dt
)
SELECT
    pv_uv,
    fav_cart_uv,
    buy_uv,
    CASE WHEN pv_uv > 0 THEN CAST(fav_cart_uv AS DOUBLE) / pv_uv
         ELSE 0
         END AS pv_2_fav_cart_rate,
    CASE WHEN fav_cart_uv > 0 THEN CAST(buy_uv AS DOUBLE) / fav_cart_uv
         ELSE 0
         END AS fav_cart_2_buy_rate,
    CASE WHEN pv_uv > 0 THEN CAST(buy_uv AS DOUBLE) / pv_uv
         ELSE 0
         END AS overall_rate
FROM data_summary;
