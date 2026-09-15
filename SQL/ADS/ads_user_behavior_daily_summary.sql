
/*
=======================================================================
1. 核心日报表 ads_user_behavior_daily_summary
目的：将每日流量、漏斗、留存、复购指标合并成一张宽表，Qucik Bi 直接读取。
*/
-- 创建 ADS 层，表名：ads_user_behavior_daily_summary
CREATE TABLE IF NOT EXISTS ads_user_behavior_daily_summary (
    pv BIGINT COMMENT '页面浏览量(pv 次数)',
    uv BIGINT COMMENT '独立访客数(去重用户数)',
    visit_depth DOUBLE COMMENT '人均访问页面数(pv / uv)',
    bounce_rate DOUBLE COMMENT '跳出率(仅 1 次 pv 的用户占比)',
    pv_uv BIGINT COMMENT '浏览用户数(pv 去重)',
    fav_cart_uv BIGINT COMMENT '收藏或加购用户数(fav/cart去重)',
    buy_uv BIGINT COMMENT '购买用户数(buy 去重)',
    pv_2_fav_cart_rate DOUBLE COMMENT '浏览 → 收藏/加购转化率',
    fav_cart_2_buy_rate DOUBLE COMMENT '收藏/加购 → 购买转化率',
    overall_rate DOUBLE COMMENT '整体转化率',
    active_uv BIGINT COMMENT '基准日活跃用户数',
    retention_1d DOUBLE COMMENT '次日留存率',
    rerention_3d DOUBLE COMMENT '3 日留存率',
    retention_7d DOUBLE COMMENT '7 日留存率',
    buy_user_uv BIGINT COMMENT '30 天内购买用户数',
    repurchase_user_uv BIGINT COMMENT '30 天内复购用户数(购买次数 ≥ 2)',
    repurchase_rate DOUBLE COMMENT '复购率(购买 2 次以上用户占比)'
)
COMMENT '用户行为核心指标日汇总宽表'
PARTITIONED BY (
    dt STRING COMMENT '统计日期：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
1. ads_user_behavior_daily_summary
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE ads_user_behavior_daily_summary PARTITION (dt)
SELECT 
    -- dws_traffic_metrics_daily
    COALESCE(T.pv, 0) AS pv,
    COALESCE(T.uv, 0) AS uv,
    COALESCE(T.visit_depth, 0) AS visit_depth,
    COALESCE(T.bounce_rate, 0) AS bounce_rate,

    -- dws_funnel_metrics_daily
    COALESCE(F.pv_uv, 0) AS pv_uv,
    COALESCE(F.fav_cart_uv, 0) AS fav_cart_uv,
    COALESCE(F.buy_uv, 0) AS buy_uv,
    COALESCE(F.pv_2_fav_cart_rate, 0) AS pv_2_fav_cart_rate,
    COALESCE(F.fav_cart_2_buy_rate, 0) AS fav_cart_2_buy_rate,
    COALESCE(F.overall_rate, 0) AS overall_rate,

    -- dws_retention_metrics_daily
    COALESCE(RT.active_uv, 0) AS d1_retention,
    COALESCE(RT.retention_1d, 0) AS retention_1d,
    COALESCE(RT.retention_3d, 0) AS retention_3d,
    COALESCE(RT.retention_7d, 0) AS retention_7d,

    -- dws_repurchase_metrics
    COALESCE(RP.buy_user_uv, 0) AS buy_user_uv,
    COALESCE(RP.repurchase_user_uv, 0) AS repurchase_user_uv,
    COALESCE(RP.repurchase_rate, 0) AS repurchase_rate,
    
    T.dt
FROM (
    SELECT 
        pv,
        uv,
        visit_depth,
        bounce_rate,
        dt
    FROM dws_traffic_metrics_daily
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
 ) T
LEFT JOIN (
    SELECT 
        pv_uv,
        fav_cart_uv,
        buy_uv,
        pv_2_fav_cart_rate,
        fav_cart_2_buy_rate,
        overall_rate,
        dt
    FROM dws_funnel_metrics_daily
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
 ) F
    ON T.dt = F.dt
LEFT JOIN (
    SELECT 
        active_uv,
        retention_1d,
        retention_3d,
        retention_7d,
        dt
    FROM dws_retention_metrics_daily
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
 ) RT
    ON T.dt = RT.dt
LEFT JOIN (
    SELECT 
        buy_user_uv,
        repurchase_user_uv,
        repurchase_rate,
        dt
    FROM dws_repurchase_metrics
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
 ) RP
    ON T.dt = RP.dt;

-- SHOW PARTITIONS ads_user_behavior_daily_summary;
-- 检查下 ads_user_behavior_daily_summary 是否有数据
-- SELECT *
-- FROM ads_user_behavior_daily_summary
-- WHERE dt BETWEEN '2017-11-20' AND '2017-12-10'
-- ORDER BY TO_DATE(dt, 'yyyy-MM-dd');


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE ads_user_behavior_daily_summary PARTITION (dt = '${dt}')
SELECT 
    -- dws_traffic_metrics_daily
    COALESCE(T.pv, 0) AS pv,
    COALESCE(T.uv, 0) AS uv,
    COALESCE(T.visit_depth, 0) AS visit_depth,
    COALESCE(T.bounce_rate, 0) AS bounce_rate,

    -- dws_funnel_metrics_daily
    COALESCE(F.pv_uv, 0) AS pv_uv,
    COALESCE(F.fav_cart_uv, 0) AS fav_cart_uv,
    COALESCE(F.buy_uv, 0) AS buy_uv,
    COALESCE(F.pv_2_fav_cart_rate, 0) AS pv_2_fav_cart_rate,
    COALESCE(F.fav_cart_2_buy_rate, 0) AS fav_cart_2_buy_rate,
    COALESCE(F.overall_rate, 0) AS overall_rate,

    -- dws_retention_metrics_daily 
    NULL AS active_uv,
    NULL AS retention_1d,
    NULL AS retention_3d,
    NULL AS retention_7d,

    -- dws_repurchase_metrics
    COALESCE(RP.buy_user_uv, 0) AS buy_user_uv,
    COALESCE(RP.repurchase_user_uv, 0) AS repurchase_user_uv,
    COALESCE(RP.repurchase_rate, 0) AS repurchase_rate
FROM (
    SELECT 
        pv,
        uv,
        visit_depth,
        bounce_rate,dt
    FROM dws_traffic_metrics_daily
    WHERE dt = '${dt}'
 ) T
LEFT JOIN (
    SELECT 
        pv_uv,
        fav_cart_uv,
        buy_uv,
        pv_2_fav_cart_rate,
        fav_cart_2_buy_rate,
        overall_rate
    FROM dws_funnel_metrics_daily
    WHERE dt = '${dt}'
 ) F
    ON T.dt = F.dt
LEFT JOIN (
    SELECT 
        buy_user_uv,
        repurchase_user_uv,
        repurchase_rate
    FROM dws_repurchase_metrics
    WHERE dt = '${dt}'
 ) RP
    ON T.dt = RP.dt;


-- 每日调度，静态分区 + 参数，数据补数，dt_sub_7 = $[yyyy-MM-dd-7]
INSERT OVERWRITE TABLE ads_user_behavior_daily_summary PARTITION (dt = '${dt_sub_7}')
SELECT 
    -- dws_traffic_metrics_daily
    COALESCE(T.pv, 0) AS pv,
    COALESCE(T.uv, 0) AS uv,
    COALESCE(T.visit_depth, 0) AS visit_depth,
    COALESCE(T.bounce_rate, 0) AS bounce_rate,

    -- dws_funnel_metrics_daily
    COALESCE(F.pv_uv, 0) AS pv_uv,
    COALESCE(F.fav_cart_uv, 0) AS fav_cart_uv,
    COALESCE(F.buy_uv, 0) AS buy_uv,
    COALESCE(F.pv_2_fav_cart_rate, 0) AS pv_2_fav_cart_rate,
    COALESCE(F.fav_cart_2_buy_rate, 0) AS fav_cart_2_buy_rate,
    COALESCE(F.overall_rate, 0) AS overall_rate,

    -- dws_retention_metrics_daily
    COALESCE(RT.active_uv, 0) AS d1_retention,
    COALESCE(RT.retention_1d, 0) AS retention_1d,
    COALESCE(RT.retention_3d, 0) AS retention_3d,
    COALESCE(RT.retention_7d, 0) AS retention_7d,

    -- dws_repurchase_metrics
    COALESCE(RP.buy_user_uv, 0) AS buy_user_uv,
    COALESCE(RP.repurchase_user_uv, 0) AS repurchase_user_uv,
    COALESCE(RP.repurchase_rate, 0) AS repurchase_rate
FROM (
    SELECT 
        pv,
        uv, 
        visit_depth, 
        bounce_rate
    FROM dws_traffic_metrics_daily
    WHERE dt = '${dt_sub_7}'
 ) T
LEFT JOIN (
    SELECT 
        pv_uv, 
        fav_cart_uv,
        buy_uv, 
        pv_2_fav_cart_rate, 
        fav_cart_2_buy_rate, 
        overall_rate
    FROM dws_funnel_metrics_daily
    WHERE dt = '${dt_sub_7}'
 ) F
    ON T.dt = F.dt
LEFT JOIN (
    SELECT 
        active_uv, 
        retention_1d, 
        retention_3d, 
        retention_7d
    FROM dws_retention_metrics_daily
    WHERE dt = '${dt_sub_7}'
 ) RT
    ON T.dt = RT.dt
LEFT JOIN (
    SELECT 
        buy_user_uv, 
        repurchase_user_uv,
        repurchase_rate
    FROM dws_repurchase_metrics
    WHERE dt = '${dt_sub_7}'
 ) RP
    ON T.dt = RP.dt;
