
-- ========== 建表 ==========
-- 创建 DWD 层，表名：dwd_user_behavior_detail
CREATE TABLE IF NOT EXISTS dwd_user_behavior_detail(
    user_id        BIGINT COMMENT '用户ID',
    item_id        BIGINT COMMENT '商品ID',
    category_id    BIGINT COMMENT '类目ID',
    behavior_type  STRING COMMENT '行为类型：pv/buy/cart/fav',
    event_date     STRING COMMENT '事件日期：yyyy-MM-dd',
    event_hour     INT COMMENT '事件小时：0 - 23'
)
COMMENT '用户行为明细表'
PARTITIONED BY 
(
    dt             STRING COMMENT '日期分区'
)
LIFECYCLE 30
;


-- ========== 数据导入 ==========
-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE dwd_user_behavior_detail PARTITION(dt)
SELECT 
    user_id,
    item_id,
    category_id,
    behavior_type,
    SUBSTR(FROM_UNIXTIME(`timestamp`), 1, 10) AS event_date,
    HOUR(CAST(FROM_UNIXTIME(`timestamp`) AS DATETIME )) AS event_hour,
    SUBSTR(FROM_UNIXTIME(`timestamp`), 1, 10) AS dt
FROM ods_user_behavior_sync 
WHERE user_id IS NOT NULL 
    AND item_id > 0
    AND behavior_type IN ('pv','buy','cart','fav')
    AND `timestamp` > 0;

-- 测试 ODS → DWD 导入后是否有数据
-- SELECT
--     *
-- FROM dwd_user_behavior_detail
-- WHERE dt = '2019-10-20'
-- LIMIT 20;


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE dwd_user_behavior_detail PARTITION(dt = '${dt}')
SELECT 
    user_id,
    item_id,
    category_id,
    behavior_type,
    SUBSTR(FROM_UNIXTIME(`timestamp`), 1, 10) AS event_date,
    HOUR(CAST(FROM_UNIXTIME(`timestamp`) AS DATETIME )) AS event_hour
FROM ods_user_behavior_sync 
WHERE user_id IS NOT NULL 
    AND item_id > 0
    AND behavior_type IN ('pv','buy','cart','fav')
    AND SUBSTR(FROM_UNIXTIME(`timestamp`), 1, 10) = '${dt}';
