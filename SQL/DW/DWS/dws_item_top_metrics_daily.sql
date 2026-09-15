
/*
=======================================================================
6. 商品分析指标
热销类目 TOP N：按照购买次数或购买用户数排名最高的商品类目。
热销商品 TOP N：按照购买次数或购买用户数排名最高的商品。
关联购买：经常在同一用户的购买清单中共同出现的商品组合，反映商品关联度。
    基于用户购买商品集合做关联规则挖掘，常用指标：支持度、置信度、提升度。
*/
CREATE TABLE IF NOT EXISTS dws_item_top_metrics_daily (
    item_id BIGINT COMMENT '商品ID',
    buy_cnt BIGINT COMMENT '购买次数',
    buy_user_cnt BIGINT COMMENT '购买用户数',
    item_rank BIGINT COMMENT '商品排名'
)
COMMENT '每日热销商品 TOP 榜'
PARTITIONED BY (
    dt STRING COMMENT '统计日期：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
6. dws_item_top_metrics_daily 

dt
item_id：商品ID。
buy_cnt：购买次数。
buy_user_cnt：购买用户数，单个用户当日多次购买计为 1 次。
item_rank：按照购买次数降序排序，相同排名时占位。
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE dws_item_top_metrics_daily PARTITION (dt)
WITH date_dim AS (
    SELECT DISTINCT
        dt
    FROM dwd_user_behavior_detail 
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
),
item_buy_data AS (
    SELECT
        dt,
        item_id,
        COUNT(*) AS buy_cnt,
        COUNT(DISTINCT user_id) AS buy_user_cnt,
        RANK() OVER (PARTITION BY dt ORDER BY COUNT(*) DESC) AS item_rank
    FROM dwd_user_behavior_detail 
    WHERE behavior_type = 'buy'
    GROUP BY dt, item_id
)
SELECT
    B.item_id,
    B.buy_cnt,
    B.buy_user_cnt,
    B.item_rank,

    T.dt
FROM date_dim T
LEFT JOIN item_buy_data B
    ON T.dt = B.dt;
-- 一次扫描 + GROUPING SETS 优化思路
-- WITH combined AS (
--     SELECT
--         dt,
--         item_id,
--         -- 统计购买次数（非购买行为计为 NULL，不影响 COUNT）
--         COUNT(IF(behavior_type = 'buy', 1, NULL)) AS buy_cnt,
--         -- 统计购买用户数（非购买行为 user_id 计为 NULL，DISTINCT 自动忽略）
--         COUNT(DISTINCT IF(behavior_type = 'buy', user_id, NULL)) AS buy_user_cnt,
--         -- 标记当前行是否为日期汇总行（1=汇总，0=明细）
--         GROUPING(item_id) AS is_date_rollup
--     FROM dwd_user_behavior_detail
--     WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
--     GROUP BY dt, item_id GROUPING SETS ((dt, item_id), (dt))
-- ),
-- -- 提取所有存在的日期（包含无购买行为的日期，因为汇总行仍会保留）
-- all_dates AS (
--     SELECT dt
--     FROM combined
--     WHERE is_date_rollup = 1   -- 每个日期只有一条汇总行
--     GROUP BY dt                -- 去重，确保唯一
-- ),
-- -- 提取有购买的商品明细（过滤掉汇总行和购买数为0的商品）
-- item_buy_data AS (
--     SELECT
--         dt,
--         item_id,
--         buy_cnt,
--         buy_user_cnt,
--     RANK() OVER (PARTITION BY T.dt ORDER BY B.buy_cnt DESC) AS item_rank
--     FROM combined
--     WHERE is_date_rollup = 0
--       AND buy_cnt > 0          -- 只保留真正有购买的商品
-- )
-- SELECT
--     B.item_id,
--     B.buy_cnt,
--     B.buy_user_cnt,
--     -- 关键修正：使用 T.dt 分区，保证按日期独立排名
--     B.item_rank,

--     T.dt,
-- FROM all_dates T
-- LEFT JOIN item_buy_data B
--     ON T.dt = B.dt;

-- SHOW PARTITIONS dws_item_top_metrics_daily ;
-- 检查下 dws_item_top_metrics_daily 中是否有数据
-- SELECT 
--     *
-- FROM dws_item_top_metrics_daily 
-- WHERE dt = '2017-11-28'
--     AND item_rank <= 50;


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE dws_item_top_metrics_daily PARTITION (dt = '${dt}')
SELECT
    dt,
    item_id,
    COUNT(*) AS buy_cnt,
    COUNT(DISTINCT user_id) AS buy_user_cnt,
    RANK() OVER (PARTITION BY dt ORDER BY COUNT(*) DESC) AS item_rank
FROM dwd_user_behavior_detail 
WHERE behavior_type = 'buy'
    AND dt = '${dt}'
GROUP BY item_id;
