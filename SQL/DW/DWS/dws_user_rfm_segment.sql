
/*
=======================================================================
5. RFM 用户分层
由于数据集中无金额字段，采用 R(最近购买时间) 和 F(购买频次) 两个维度，M 用 F 近似代替，形成二维分层。

R(Recency)：用户最近一次购买距离指定日期的天数，值越小代表越活跃。
F(Frequency)：用户在统计周期内的购买次数，值越大代表越忠诚。
用户分层：根据 R、F 的组合将用户划分为不同价值群体。

分层规则示例(简单实用版)：
# 重要价值客户：R ≤ 30 且 F ≥ 5 (近期高频)
# 重要发展客户：R ≤ 30 且 F < 5 (近期但购买频次低)
# 重要保持客户：R > 30 且 F ≥ 5 (一段时间未买但历史高频)
# 一般客户：R > 30 且 F < 5 (低频且久未购买)
也可采用 R、F 各自评分(如 1 - 3 分)后组成9类，此处保持简单，便于解释。
*/
CREATE TABLE IF NOT EXISTS dws_user_rfm_segment (
    user_id STRING COMMENT '用户ID',
    r_value BIGINT COMMENT 'R值(最近购买时间)',
    f_value BIGINT COMMENT 'F值(购买频次)',
    segment_label STRING COMMENT '用户分层：重要价值客户/重要发展客户/重要保持客户/一般客户'
)
COMMENT '用户 RFM 分层结果表'
PARTITIONED BY (
    dt STRING COMMENT '统计日期：yyyy-MM-dd'
)
LIFECYCLE 30;


/*
===================================================================================
5. dws_user_rfm_segment 

dt
user_id：用户ID。
r_value：用户最近一次购买距离指定日期的天数，值越小代表越活跃。
f_value：用户在统计周期内的购买次数，值越大代表越忠诚。
segment_label：用户分层标签。
    # 分层规则：
    ## 重要价值客户：R ≤ 30 且 F ≥ 5 (近期高频)
    ## 重要发展客户：R ≤ 30 且 F < 5 (近期但购买频次低)
    ## 重要保持客户：R > 30 且 F ≥ 5 (一段时间未买但历史高频)
    ## 一般客户：R > 30 且 F < 5 (低频且久未购买)
*/

-- 一次性历史数据导入(动态分区)
INSERT OVERWRITE TABLE dws_user_rfm_segment PARTITION (dt)
WITH user_date_pair AS (
    SELECT /*+ MAPJOIN(D) */  -- MAXCOMPUTE 默认禁止笛卡尔积，需使用 MAPJOIN 将小表加载到内存
        U.user_id,
        D.dt
    FROM (
        SELECT DISTINCT 
            user_id
        FROM dwd_user_behavior_detail 
        WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    ) U
    JOIN (
        SELECT DISTINCT
            dt
        FROM dwd_user_behavior_detail 
        WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    ) D
        ON 1 = 1
),
daily_buy AS (
    SELECT 
        user_id,
        dt,
        COUNT(*) AS buy_cnt
    FROM dwd_user_behavior_detail 
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
        AND behavior_type = 'buy'
    GROUP BY user_id, dt
),
history_data AS (
    SELECT 
        T.user_id,
        T.dt,
        SUM(COALESCE(B.buy_cnt, 0)) OVER(
            PARTITION BY T.user_id ORDER BY T.dt 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS  f_value,
        MAX(CASE WHEN B.buy_cnt > 0 THEN T.dt ELSE NULL END) OVER(
            PARTITION BY T.user_id ORDER BY T.dt 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS last_buy_date
    FROM user_date_pair T
    LEFT JOIN daily_buy B
        ON T.user_id = B.user_id
        AND T.dt = B.dt
),
calculate_r_value AS (
    SELECT 
        user_id,
        dt,
        DATEDIFF(TO_DATE(dt, 'yyyy-MM-dd'), TO_DATE(last_buy_date, 'yyyy-MM-dd'), 'dd') AS r_value,
        f_value
    FROM history_data
    WHERE last_buy_date IS NOT NULL
)
SELECT 
    user_id,
    r_value,
    f_value,
    CASE WHEN r_value <= 30 AND f_value >= 5 THEN '重要价值客户'
        WHEN r_value <= 30 AND f_value < 5 THEN '重要发展客户'
        WHEN r_value > 30 AND f_value >= 5 THEN '重要保持客户'
        WHEN r_value > 30 AND f_value < 5 THEN '一般客户'
        ELSE '其他'
        END AS segment_label,
    
    dt
FROM calculate_r_value;

-- SHOW PARTITIONS dws_user_rfm_segment ;
-- 检查下 dws_user_rfm_segment 中是否有数据
-- SELECT 
--     *
-- FROM dws_user_rfm_segment 
-- WHERE dt = '2017-11-28'
-- ORDER BY CASE segment_label
--             WHEN '重要价值客户' THEN 1
--             WHEN '重要发展客户' THEN 2
--             WHEN '重要保持客户' THEN 3
--             WHEN '一般客户' THEN 4
--             ELSE 5
--             END
-- LIMIT 1000;


-- 每日调度，静态分区 + 参数，只处理前一天的数据，即数据时效 T + 1，dt = $[yyyy-MM-dd-1]
INSERT OVERWRITE TABLE dws_user_rfm_segment PARTITION (dt = '${dt}')
SELECT 
    user_id,
    DATEDIFF(TO_DATE('${dt}', 'yyyymmdd'), TO_DATE(MAX(dt), 'yyyy-mm-dd'), 'dd') AS r_value,
    COUNT(*) AS f_value,
    CASE 
        WHEN DATEDIFF(TO_DATE('${dt}', 'yyyymmdd'), TO_DATE(MAX(dt), 'yyyy-mm-dd'), 'dd') <= 30 
            AND COUNT(*) >= 5 
            THEN '重要价值客户'
        WHEN DATEDIFF(TO_DATE('${dt}', 'yyyymmdd'), TO_DATE(MAX(dt), 'yyyy-mm-dd'), 'dd') <= 30 
            AND COUNT(*) < 5 
            THEN '重要发展客户'
        WHEN DATEDIFF(TO_DATE('${dt}', 'yyyymmdd'), TO_DATE(MAX(dt), 'yyyy-mm-dd'), 'dd') > 30 
            AND COUNT(*) >= 5 
            THEN '重要保持客户'
        WHEN DATEDIFF(TO_DATE('${dt}', 'yyyymmdd'), TO_DATE(MAX(dt), 'yyyy-mm-dd'), 'dd') > 30 
            AND COUNT(*) < 5 
            THEN '一般客户'
        ELSE '其他'
    END AS segment_label
    
FROM dwd_user_behavior_detail 
WHERE behavior_type = 'buy'
    AND dt <= '${dt}'
GROUP BY user_id;
