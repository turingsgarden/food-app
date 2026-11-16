
import pandas as pd

pd.set_option("display.width", 250)

top = pd.read_csv("outputs/top1000_nhanes.csv")
gt = pd.read_csv("outputs/asa24_ground_truth.csv")
ours = set(gt["food_code"].astype(int))

names = {"1": "Milk/dairy", "2": "Meat/poultry/fish/mixtures", "3": "Eggs",
         "4": "Beans/nuts/seeds", "5": "Grain products", "6": "Fruits",
         "7": "Vegetables", "8": "Fats/oils/dressings", "9": "Sugars/sweets/beverages"}

top["group"] = top["food_code"].astype(int).astype(str).str[0]
top["in_ours"] = top["food_code"].isin(ours)

g = top.groupby("group").agg(top1000=("food_code", "size"),
                             in_fndds=("in_fndds_2019_2020", "sum"),
                             ours=("in_ours", "sum"))
g["coverage"] = (g["ours"] / g["top1000"]).round(2)
g["records_share_top1000"] = (top.groupby("group")["count"].sum() / top["count"].sum()).round(3)
kept = top[top["in_ours"]]
g["records_share_ours"] = (kept.groupby("group")["count"].sum() / kept["count"].sum()).round(3)
g.index = [f"{i} {names[i]}" for i in g.index]
print("food groups: top 1000 vs. what we kept")
print(g.to_string())

gt["group"] = gt["food_code"].astype(int).astype(str).str[0]
m = gt.groupby("group").agg(images=("food_code", "size"), grams=("grams", "mean"),
                            kcal=("energy_kcal", "mean"), carb=("carb_g", "mean"),
                            protein=("protein_g", "mean")).round(1)
m.index = [f"{i} {names[i]}" for i in m.index]
print("\nour test set: mean per image by group")
print(m.to_string())