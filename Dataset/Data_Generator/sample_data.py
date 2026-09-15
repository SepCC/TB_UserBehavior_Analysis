
import pandas as pd

df = pd.read_csv(
    r"C:\WorkSpace\Project\TB_UserBehavior_Analysis\Dataset\UserBehavior.csv\UserBehavior.csv",
    header = None,
    names = [
        "user_id",
        "item_id",
        "category_id",
        "behavior_type",
        "timestamp"
    ]
)

sample_df = df.sample(n = 5000000, random_state = 111)

sample_df.to_csv(
    r"C:\WorkSpace\Project\TB_UserBehavior_Analysis\Dataset\UserBehavior.csv\UserBehavior.csv",
    index = False
)
