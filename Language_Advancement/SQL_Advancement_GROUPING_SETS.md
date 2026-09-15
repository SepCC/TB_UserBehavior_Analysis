# Project Name: TB_UserBehavior_Analysis —— SQL Advancement

Date：2026-09-03

## 目录

1. 背景与原始 SQL 问题
2. 问题诊断与修正
3. 优化方案一：两次扫描 CTE (推荐)
4. 优化方案二：GROUPING SETS 一次扫描(ODPS 专属)
5. MySQL 社区版下的替代方案：WITH ROLLUP
6. 性能对比与选型建议
7. 附录：GROUPING() 函数详解

## 1. 背景与原始 SQL 问题

业务需求：统计每个日期下每个商品的购买次数及购买用户数，并按日期对商品进行购买次数排名。  
同时需要保留所有日期(即使该日期下无购买记录)。

### 原始 SQL （ODPS 语法）

```SQL
WITH date_dim AS (
    SELECT dt
    FROM dwd_user_behavior_detail 
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    GROUP BY dt
),
item_buy_data AS (
    SELECT
        dt,
        item_id,
        COUNT(*) AS buy_cnt,
        COUNT(DISTINCT user_id) AS buy_user_cnt
    FROM dwd_user_behavior_detail 
    WHERE behavior_type = 'buy'
    GROUP BY dt, item_id
)
SELECT
    T.dt,
    B.item_id,
    B.buy_cnt,
    B.buy_user_cnt,
    RANK() OVER (PARTITION BY B.dt ORDER BY B.buy_cnt DESC) AS item_rank
FROM date_dim T
LEFT JOIN item_buy_data B
    ON T.dt = B.dt;
```

## 2. 问题诊断与修正

| 问题点 | 严重程度 | 说明 |  
| :---- | :---- | :---- |
| 分区列使用了右表字段 **B.dt** | 致命错误逻辑 | 当某天无购买时，**B.dt** 为 **NULL**，所有无购买日期被分到同一个 **NULL** 分区，排名完全错乱。 |
| **date_dim** 使用 **GROUP BY** 而非 **DISTINCT** | 性能略差 | 可优化，但影响不大 |
| 两次全表扫描 | 性能瓶颈 | 数据量大时 **I/O** 开销高 |

## 3. 优化方案一：两次扫描 CTE (推荐)

**适用引擎**：ODPS / MySQL / PostgreSQL / 所有主流引擎  
**优点**：逻辑清晰、易维护、并行扫描效率高  
**缺点**：扫描两次源表(但现代分布式引擎可并行，通常可接受)

```SQL
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
```

## 4. 优化方案二：GROUPING SETS 一次扫描 (ODPS 专属)

**适用引擎**：ODPS(MaxCompute)、PostgrepSQL、SQL Server、Oracle (不适用于 MySQL 社区版)  
**优点**：只扫描一次表，极大降低 I/O  
**缺点**：SQL 复杂度增加，COUNT(DISTINCT) 在多个分组集下消耗大量内存

### 4.1 核心思路

利用 **GROUPING SETS** 同时产出 **日期维度** (按 dt 汇总)和 **日期 + 商品明细**，再通过 **GROUPING()** 标记区分。

### 4.2 实现 SQL

```SQL
WITH combined AS (
    SELECT
        dt,
        item_id,
        COUNT(IF(behavior_type = 'buy', 1, NULL)) AS buy_cnt,
        COUNT(DISTINCT IF(behavior_type = 'buy', user_id, NULL)) AS buy_user_cnt,
        GROUPING(item_id) AS is_date_rollup   -- 1=日期汇总行，0=商品明细行
    FROM dwd_user_behavior_detail
    WHERE dt BETWEEN '1970-01-01' AND '2037-04-09'
    GROUP BY dt, item_id
    GROUPING SETS ((dt, item_id), (dt))
),
all_dates AS (
    SELECT dt
    FROM combined
    WHERE is_date_rollup = 1    -- 提取所有日期（包括无购买日期）
    GROUP BY dt                 -- 去重
),
item_buy_data AS (
    SELECT
        dt,
        item_id,
        buy_cnt,
        buy_user_cnt,
        RANK() OVER (PARTITION BY dt ORDER BY buy_cnt DESC) AS item_rank
    FROM combined
    WHERE is_date_rollup = 0
      AND buy_cnt > 0           -- 只保留真正有购买的商品
)
SELECT
    B.item_id,
    B.buy_cnt,
    B.buy_user_cnt,
    B.item_rank,

    T.dt,
FROM all_dates T
LEFT JOIN item_buy_data B 
    ON T.dt = B.dt;
```

### 4.3 ODPS 特别提醒

- **内存风险**：**COUNT(DISTINCT IF(...))** 在每个分组集内独立维护去重结构，若数据量大且分区多，可能导致 **OOM**。建议：  
  - 改用 **APPROX_COUNT_DISTINCT** (近似去重)若精度允许。
  - 或拆分两次扫描(回到方案一)。
- **分组集字段**：若原始表中 **item_id** 本身有 **NULL**，需用 **GROUPING(item_id)** 区分"汇总产生的 **NULL**"和"受数据本身的 **NULL**"。

## 5. MySQL 社区版下的替代方案：WITH ROLLUP

MySQL 社区版 **不支持** **GROUPING SETS** 和 **CUBE**，但原生支持 **GROUP BY .... WITH ROLLUP**，可用于严格层级汇总。

### 5.1 ROLLUP 层级规则

**WITH ROLLUP** 按照 **GROUP BY** 字段 **从左到右**，**从右向左** 逐级去掉维度进行汇总。

例如：

```SQL
GROUP BY 大区, 网点, 门店, 产品 WITH ROLLUP
```

将依次生成：  

1. **(大区, 网点, 门店, 产品)** —— 明细
2. **(大区, 网点, 门店)** —— 门店小计
3. **(大区, 网点)** —— 网点小计
4. **(大区)** —— 大区小计
5. **()** —— 全国总计

### 5.2 使用 GROUPING() 区分汇总行

```SQL
SELECT
    大区, 网点, 门店, 产品,
    SUM(销售额) AS total_sales,
    GROUPING(大区) AS g_大区,
    GROUPING(网点) AS g_网点,
    GROUPING(门店) AS g_门店,
    GROUPING(产品) AS g_产品,
    CASE
        WHEN GROUPING(大区)=1 THEN '全国总计'
        WHEN GROUPING(网点)=1 THEN '大区小计'
        WHEN GROUPING(门店)=1 THEN '网点小计'
        WHEN GROUPING(产品)=1 THEN '门店小计'
        ELSE '产品明细'
    END AS 汇总层级
FROM 销售表
GROUP BY 大区, 网点, 门店, 产品 WITH ROLLUP;
```

### 5.3 重要限制与注意事项

- **只能生成从左到右递减的层级组合**，无法生成 **(大区, 产品)** 这种跨级组合。
- 当与 **ORDER BY**、**LIMIT**、**HAVING** 同时使用时，汇总行的位置和行为可能不符合预期，需谨慎处理。
- 对于本文的业务(日期 + 商品)，若需求是 "每天按商品排名" 且要保留所有日期，**WITH ROLLUP** **无法直接产生"日期维表"** (因为日期不是层级递减关系)。此时仍需使用 **DISTINCT 日期** 左连接或 **UNION ALL** 模拟。

## 6. 性能对比与选型建议

| 方案 | 扫描次数 | SQL 复杂度 | 内存消耗 | 适用引擎 |  
| :--- | :--- | :--- | :--- | :--- |  
| **两次扫描** | 2 | 低 | 低 | 所有引擎(推荐) |  
| **GROUPING SETS** | 1 | 中 ~ 高 | 高(尤其 **DISTINCT**) | OPDS、PG、SQL Server |  
| **WITH ROLLUP** | 1 | 低 | 低 | MySQL、PG、SQL Server(仅层级场景) |

### 选型决策树

```TEXT
是否需要保留无购买行为的日期？
│
├── 是 → 必须构建日期维表，推荐“两次扫描 CTE”（方案一）
│       若用 ODPS 且表极大，可尝试 GROUPING SETS（方案二）并评估内存
│
└── 否 → 直接 INNER JOIN 即可，可使用任意方案
```

#### 最终推荐

在绝大多数场景下，方案一(两次扫描 CTE) 是最稳妥、最易维护的选择。  
只有当表规模巨大(> 100TB) 且 I/O 是瓶颈时，才考虑方案二或数据预聚合。

## 7. 附录

### GROUP SETS 详解

**核心定义**：

**GROUPING SETS** 是 **GROUP BY**的扩展子句。它允许在 **一次查询** 中，按照 **多种维度组合** 分别进行聚合，相当于把多个 **GROUP BY** 的结果用 **UNION ALL** 拼在一起，但 **只扫描一次源表**，

**基础语法**：

```SQL
SELECT 列1, 列2, 聚合函数(列3)
FROM 表
GROUP BY 列1, 列2
GROUPING SETS ( (列1, 列2), (列1), (列2), () );
```

- **(列1, 列2)**：按这两个字段精确分组(明细)
- **(列1)**：只按 列1 分组(小计)
- **(列2)**：只按 列2 分组(小计)
- **()**：全局总计(不分组)

**等效的 UNION ALL 写法(对比理解)**：

```SQL
-- 使用 GROUPING SETS
SELECT dt, item_id, COUNT(*) AS cnt
FROM table
GROUP BY dt, item_id
GROUPING SETS ((dt, item_id), (dt));

-- 等效于 UNION ALL
SELECT dt, item_id, COUNT(*) FROM table GROUP BY dt, item_id
UNION ALL
SELECT dt, NULL AS item_id, COUNT(*) FROM table GROUP BY dt;
```

**常用组合扩展： ROLLUP 与 CUBE**:

**GROUPING SETS** 是基础，它还能快捷生成两种常用组合：

| 写法 | 含义 | 等价 **GROUPING SETS** |
| :--- | :--- | :--- |
| **GROUP BY ROLLUP(a, b)** | 从右向左递减：**(a,b)**, **(a)**, **()** | **GROUPING SERS ((a, b), (a), ())** |
| **GROUP BY CUBE(a, b)** | 所有组合：**(a, b)**, **(a)**, **(b)**, **()** | **GROUPING SETS ((a, b), (a), (b), ())** |

### GROUPING() 函数详解

**GROUPING(column)** 用于判断当前行的该列是否参与了 **GROUP BY** 分组。

| 返回值 | 含义 |
| :--- | :--- |
| 0 | 该列参与了当前分组，值来自原始数据 |
| 1 | 该列未参与当前分组，值是汇总行填充的 **NULL** |

**应用场景**：

- 在多级汇总结果中区分 "真实 **NULL**" 和 "汇总占位 **NULL**"。
- 生成可读的层级标识(如 "小计"、"总计")。
- 在 **ORDER BY** 中控制汇总行的排序位置。

**兼容性**：

- ODPS(MaxCompute)：支持
- MySQL 5.7+ / 8.0+：支持(与 WITH ROLLUP 配合)
- PostgreSQL：支持
- SQL Server：支持（GROUPING 函数，但语法略有不同）
