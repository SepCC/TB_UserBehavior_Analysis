
/*
=======================================================================
3. 商品榜单 ads_item_top_daily
目的：快速查看每天商品榜单，用于趋势分析；统一 TOP 口径。
也可以保留 DWS 层 dws_item_top_metrics_daily  直接使用。
*/
-- 创建 ADS 层，表名：ads_item_top_daily
CREATE TABLE IF NOT EXISTS ads_item_top50_daily (
    item_id BIGINT COMMENT '商品ID',
    buy_cnt BIGINT COMMENT '购买次数',
    buy_user_cnt BIGINT COMMENT '购买用户数',
    item_rank BIGINT COMMENT '商品排名'
)
COMMENT '商品榜单 TOP 50'
PARTITIONED BY (
    dt STRING COMMENT '统计日期：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
3. ads_item_top50_daily
*/

INSERT OVERWRITE TABLE ads_item_top50_daily PARTITION (dt)
SELECT
    item_id,
    buy_cnt,
    buy_user_cnt,
    item_rank,
    
    dt
FROM dws_item_top_metrics_daily 
WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    AND item_rank <= 50;

-- SHOW PARTITIONS ads_item_top50_daily;
-- 检查下 ads_item_top50_daily 是否有数据
-- SELECT *
-- FROM ads_item_top50_daily
-- WHERE dt BETWEEN '2017-11-20' AND '2017-12-05'
-- ORDER BY TO_DATE(dt, 'yyyy-MM-dd'), item_rank;


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE ads_item_top50_daily PARTITION (dt = '${dt}')
SELECT
    item_id,
    buy_cnt,
    buy_user_cnt,
    item_rank
FROM dws_item_top_metrics_daily 
WHERE dt = '${dt}'
    AND item_rank <= 50;

