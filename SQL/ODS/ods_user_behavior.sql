
-- 创建 ODS 表，表名 ods_user_behavior_sync
CREATE TABLE IF NOT EXISTS ods_user_behavior_sync
(
    user_id        BIGINT COMMENT '用户ID'
    ,item_id       BIGINT COMMENT '商品ID'
    ,category_id   BIGINT COMMENT '商品类目ID'
    ,behavior_type STRING COMMENT '行为类型：pv/buy/cart/fav'
    ,`timestamp`   BIGINT COMMENT '行为发生时间戳(秒级)'
)
COMMENT '用户行为原始数据'
;


-- 测试 OSS → ODS 后是否有数据
-- SELECT
--     user_id,
--     item_id,
--     category_id,
--     behavior_type,
--     `timestamp`
-- FROM ods_user_behavior_sync
-- LIMIT 20;
-- 也可以使用 TABLESAMPLE