import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 40)

s = pd.read_csv("outputs/asa24_sample_grams_07.csv")

# 标记文字与 Multiplier 对不上的 22 行
chk = pd.read_csv("outputs/asa24_text_vs_multiplier.csv")
chk = chk[(chk["ratio"] - 1).abs() > 0.03]
disputed = set(zip(chk["food_code"], chk["portion_text"], chk["multiplier"]))
s["disputed"] = [(f, t, m) in disputed for f, t, m in zip(s["food_code"], s["portion_text"], s["multiplier"])]

# 只保留三张图都有克重的食物
ok = s.groupby("food_code")["grams"].apply(lambda x: x.notna().all())
s = s[s["food_code"].isin(ok[ok].index)].copy()
s["food_code"] = s["food_code"].astype(int)

# 每 100 g 营养值（FNDDS 2019-2020）
nut = pd.read_csv("outputs/kb/nutrients.csv")
cols = {"Energy (kcal)": "energy_kcal", "Total Fat (g)": "fat_g",
        "Carbohydrate (g)": "carb_g", "Protein (g)": "protein_g"}
nut = nut[["Food code"] + list(cols)].rename(columns=cols).rename(columns={"Food code": "food_code"})
nut["food_code"] = nut["food_code"].astype(int)
s = s.merge(nut, on="food_code", how="left")
print("rows:", len(s), "| food codes:", s["food_code"].nunique(),
      "| rows without nutrient values:", int(s["energy_kcal"].isna().sum()))
print("disputed rows (text vs Multiplier disagree):", int(s["disputed"].sum()))

s["energy_per100"] = s["energy_kcal"]
for c in cols.values():
    s[c] = s[c] * s["grams"] / 100

# 手算核对
r = s[s["energy_per100"] > 0].iloc[0]
print(f"\nhand check: food {r['food_code']} | {r['grams']:.1f} g x {r['energy_per100']} kcal/100 g = {r['energy_kcal']:.2f} kcal")

# 与论文隐含的平均值对照（平均值 = MAE per dish / MAE per unit）
paper = {"grams": (49.4, 0.348), "energy_kcal": (47.7, 0.196), "fat_g": (1.8, 0.174),
         "carb_g": (6.95, 0.208), "protein_g": (1.38, 0.233)}
print("\nmean ground truth per image: ours vs implied by the paper (Table 1)")
for c, (mae, rel) in paper.items():
    print(f"{c:12s} ours = {s[c].mean():8.2f} | paper-implied = {mae / rel:8.2f}")

print("\nmean grams by size:")
print(s.groupby("size")["grams"].mean().round(1).to_string())

out_cols = ["rank", "food_code", "description", "size", "image", "portion_text", "multiplier",
            "portion_code", "portion_subcode", "grams", "energy_kcal", "fat_g", "carb_g",
            "protein_g", "disputed"]
s = s.sort_values(["rank", "grams"])[out_cols]
s.to_csv("outputs/asa24_ground_truth.csv", index=False)
print("\nfirst 6 rows:")
print(s.head(6).to_string(index=False))
print("\nsaved outputs/asa24_ground_truth.csv")