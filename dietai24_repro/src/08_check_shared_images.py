import pandas as pd

df = pd.read_csv("outputs/asa24_sample.csv")
print("rows:", len(df), "| distinct food codes:", df["food_code"].nunique(), "| distinct images:", df["image"].nunique())

per = df.groupby("image")["food_code"].nunique().sort_values(ascending=False)
shared = per[per > 1]
print("images used by more than 1 food code:", len(shared),
      "| rows involving them:", int(df["image"].isin(shared.index).sum()))

print("\nmost shared images (image, number of food codes):")
print(per.head(8).to_string())

top_img = per.index[0]
print("\nexample food codes sharing", top_img)
print(df[df["image"] == top_img][["rank", "food_code", "description"]].head(10).to_string(index=False))
