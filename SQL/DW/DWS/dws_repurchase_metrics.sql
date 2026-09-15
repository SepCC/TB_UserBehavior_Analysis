
/*
=======================================================================
4. 复购率指标
复购率：在统计周期内，购买次数 ≥ 2 的用户数占所有购买用户数的比例。

统计周期：通常为自然月或最近 30 天，此处使用最近 30 天(滚动查询)。
购买行为：同用户同商品多次购买计为多次。
*/
-- 创建 DWS 层表，表名：dws_repurchase_metrics 复购率指标表(最近 30 天滚动窗口)
CREATE TABLE IF NOT EXISTS dws_repurchase_metrics (
    buy_user_uv BIGINT COMMENT '统计周期内购买用户数',
    repurchase_user_uv BIGINT COMMENT '统计周期内复购用户数(购买次数 ≥ 2)',
    repurchase_rate DOUBLE COMMENT '复购率(购买 2 次以上用户占比)'
)
COMMENT '复购率指标表(最近 30 天滚动窗口)'
PARTITIONED BY (
    dt STRING COMMENT '计算日期(统计截止日)：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
4. dws_repurchase_metrics (最近 30 天，滚动查询)

dt
but_user_uv：在统计周期内，发生购买为的用户数。
repuechase_user_uv：在统计周期内，购买次数 ≥ 2 的用户数。
repurchase_rate：在统计周期内，购买次数 ≥ 2 的用户数占所有购买用户数的比例。
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE dws_repurchase_metrics PARTITION (dt)
WITH buy_data AS (
    SELECT
        dt,
        user_id,
        SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) AS buy_cnt
    FROM dwd_user_behavior_detail 
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    GROUP BY dt, user_id
),
recent_30d_data AS (
    SELECT
        T.dt,
        T.user_id,
        SUM(R.buy_cnt) AS recent_buy_cnt
    FROM buy_data T
    LEFT JOIN buy_data R
        ON CAST(R.dt AS DATE) >= DATE_SUB(TO_DATE(T.dt,'yyyy-MM-dd'), 29)
        AND CAST(R.dt AS DATE) <= CAST(T.dt AS DATE)
        AND T.user_id = R.user_id
    GROUP BY T.dt, T.user_id
),
atom_data AS (
    SELECT
        dt,
        SUM(CASE WHEN recent_buy_cnt > 0 THEN 1 ELSE 0 END) AS buy_user_uv,
        SUM(CASE WHEN recent_buy_cnt >= 2 THEN 1 ELSE 0 END) AS repurchase_user_uv
    FROM recent_30d_data
    GROUP BY dt
)
SELECT 
    buy_user_uv,
    repurchase_user_uv,
    CASE WHEN buy_user_uv > 0 THEN CAST(repuechase_user_uv AS DOUBLE) / buy_user_uv
         ELSE 0
         END AS repurchase_rate,
    
    dt
FROM atom_data;
-- 如果数据日期存在连续性，可以使用窗口函数，设置参数 ROWS BETWEEN 29 PRECEDING AND CURRENT NOW

-- 检查下 dws_repurchase_metrics 中是否有数据
-- SELECT 
--     *
-- FROM dws_repurchase_metrics
-- WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
--     AND buy_user_uv > 0;

-- SELECT 
--     *
-- FROM ods_user_behavior_sync TABLESAMPLE (100 ROWS);


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE dws_repurchase_metrics PARTITION (dt = '${dt}')
WITH buy_data AS (
    SELECT
        dt,
        user_id,
        SUM(CASE WHEN behavior_type = 'buy' THEN 1 ELSE 0 END) AS buy_cnt
    FROM dwd_user_behavior_detail 
    WHERE CAST(dt AS DATE) >= DATE_ADD(TO_DATE('${dt}','yyyy-MM-dd'), -29, 'dd')
        AND CAST(dt AS DATE) <= TO_DATE('${dt}','yyyy-MM-dd')
    GROUP BY dt, user_id
),
recent_30d_data AS (
    SELECT
        T.dt,
        T.user_id,
        SUM(R.buy_cnt) AS recent_buy_cnt
    FROM buy_data T
    LEFT JOIN buy_data R
        ON CAST(R.dt AS DATE) >= DATE_SUB(TO_DATE(T.dt,'yyyy-MM-dd'), 29)
        AND CAST(R.dt AS DATE) <= CAST(T.dt AS DATE)
        AND T.user_id = R.user_id
    GROUP BY T.dt, T.user_id
),
atom_data AS (
    SELECT
        dt,
        SUM(CASE WHEN recent_buy_cnt > 0 THEN 1 ELSE 0 END) AS buy_user_uv,
        SUM(CASE WHEN recent_buy_cnt >= 2 THEN 1 ELSE 0 END) AS repurchase_user_uv
    FROM recent_30d_data
    GROUP BY dt
)
SELECT 
    buy_user_uv,
    repurchase_user_uv,
    CASE WHEN buy_user_uv > 0 THEN CAST(repuechase_user_uv AS DOUBLE) / buy_user_uv
         ELSE 0
         END AS repurchase_rate
FROM atom_data
WHERE dt = '${dt}';
