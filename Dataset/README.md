# 数据说明

## 原始数据
- 来源：阿里天池 UserBehavior 数据集
- 官方链接：https://tianchi.aliyun.com/dataset/649
- 文件：`UserBehavior.csv`
- 字段：`user_id`, `item_id`, `category_id`, `behavior_type`, `timestamp`
- 规模：约 1 亿条，压缩包约 906 MB，解压后约 3.5 GB

## 仓库中的数据处理
由于 GitHub 单文件限制为 100 MB，原始数据未上传。仓库中提供：
- `Data_Generator/sample_data.py`：从原始 CSV 中随机抽样，生成小样本。
- `sample_user_behavior.csv`：已生成的抽样数据（约 5 万条），可直接用于分析和调试。

## 如何生成样本
1. 从天池下载 `UserBehavior.csv`，放到本地任意路径。
2. 修改 `sample_data.py` 中的 `INPUT_PATH` 为实际路径。
3. 运行脚本：
   ```bash
   python sample_data.py


---

### 生成小样本 CSV（可选但推荐）

如果本地已有原始 `UserBehavior.csv`，可以生成一个约 5 万行的小样本提交到仓库，方便他人直接运行。

### 1. 修改或创建 `Dataset/Data_Generator/sample_data.py`

内容示例：

```python
import pandas as pd

# 原始 CSV 路径，请按实际路径修改
INPUT_PATH = "Dataset/UserBehavior.csv/UserBehavior.csv"
OUTPUT_PATH = "Dataset/sample_user_behavior.csv"
SAMPLE_SIZE = 50000

columns = ['user_id', 'item_id', 'category_id', 'behavior_type', 'timestamp']

df = pd.read_csv(INPUT_PATH, header=None, names=columns)
sample = df.sample(n=SAMPLE_SIZE, random_state=42)
sample.to_csv(OUTPUT_PATH, index=False)

print(f"已生成样本：{OUTPUT_PATH}，共 {len(sample)} 行")
```
