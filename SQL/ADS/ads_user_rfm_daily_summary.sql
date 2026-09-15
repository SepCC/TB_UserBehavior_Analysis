
/*
=======================================================================
2. 用户分层汇总 ads_user_rfm_daily_summary
目的：快速查看每天各分层用户数量变化，用于趋势分析。
*/
-- 创建 ADS 层，表名：ads_user_rfm_daily_summary
CREATE TABLE IF NOT EXISTS ads_user_rfm_daily_summary (
    segment_label STRING COMMENT '用户分层：重要价值客户/重要发展客户/重要保持客户/一般客户',
    user_cnt BIGINT COMMENT '用户数量'
)
PARTITIONED BY (
    dt STRING COMMENT '统计日期：yyyy-MM-dd'
)
LIFECYCLE 30;

ALTER TABLE ads_user_rfm_daily_summary SET COMMENT '每日 RFM 各分层用户数';
DESC ads_user_rfm_daily_summary;


/*
===================================================================================
2. ads_user_rfm_daily_summary
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE ads_user_rfm_daily_summary PARTITION (dt)
SELECT
    segment_label,
    COUNT(segment_label) AS user_cnt,

    dt
FROM dws_user_rfm_segment
WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
GROUP BY dt, segment_label;

-- SHOW PARTITIONS ads_user_rfm_daily_summary;
-- 检查下 ads_user_rfm_daily_summary 是否有数据
-- SELECT *
-- FROM ads_user_rfm_daily_summary
-- WHERE dt BETWEEN '2017-11-20' AND '2017-12-05'
-- ORDER BY TO_DATE(dt, 'yyyy-MM-dd');

-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE ads_user_rfm_daily_summary PARTITION (dt = '${dt}')
SELECT
    segment_label,
    COUNT(segment_label) AS user_cnt
FROM dws_user_rfm_segment
WHERE dt = '${dt}'
GROUP BY segment_label;

