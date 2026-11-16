from pathlib import Path
import re
import numpy as np
import pandas as pd

ROOT = Path("FNDDS")
OUT = Path("outputs/kb")
OUT.mkdir(parents=True, exist_ok=True)

TARGETS = ["Energy (kcal)", "Protein (g)", "Carbohydrate (g)", "Total Fat (g)"]


def read(path, sheet):
    df = pd.read_excel(path, sheet_name=sheet, header=1)
    df.columns = [" ".join(str(c).split()) for c in df.columns]  # 去掉列名里的换行
    return df


foods_path = ROOT / "2019-2020 FNDDS At A Glance - Foods and Beverages.xlsx"
portions_path = ROOT / "2019-2020 FNDDS At A Glance - Portions and Weights.xlsx"
nut_matches = list(ROOT.glob("*FNDDS Nutrient Values*.xlsx"))
assert len(nut_matches) == 1, nut_matches
nut_path = nut_matches[0]

foods_raw = read(foods_path, "Food and Beverages")
nut = read(nut_path, "FNDDS Nutrient Values")
por = read(portions_path, "Portions and Weights")

# ---------- 1. 食物描述（复现 fndds_proc.py 的规则） ----------
def expand(s):
    if pd.isna(s):
        return s
    s = re.sub(r"\bNFS\b", "not further specified subcategory assigned", s)
    s = re.sub(r"\bNS\b", "not specified subcategory", s)
    return s


def build_description(main, add):
    if pd.isna(main):
        return np.nan
    s = "The image shows the food category of " + main[0].lower() + main[1:] + "."
    if not pd.isna(add):
        s += " Additional details include " + add[0].lower() + add[1:] + "."
    return s


foods = foods_raw[["Food code", "Main food description", "Additional food description"]].copy()
n_changed = 0
for col in ["Main food description", "Additional food description"]:
    new = foods[col].map(expand)
    n_changed += int((new.fillna("") != foods[col].fillna("")).sum())
    foods[col] = new
foods["description"] = [
    build_description(m, a)
    for m, a in zip(foods["Main food description"], foods["Additional food description"])
]
n_before = len(foods)
foods = foods.dropna(subset=["description"]).reset_index(drop=True)

# ---------- 2. 营养表、portion 表 ----------
id_cols = ["Food code", "Main food description", "WWEIA Category number", "WWEIA Category description"]
nutrient_cols = [c for c in nut.columns if c not in id_cols]
nutrients = nut[["Food code"] + nutrient_cols].copy()
portions = por[["Food code", "Seq num", "Portion description", "Portion weight (g)"]].copy()

# ---------- 3. 检查项 ----------
print("=" * 70)
print("[A] 数量")
print(f"foods:     {n_before} rows -> {len(foods)} after dropping empty main description (论文: 5624)")
print(f"nutrients: {len(nutrients)} rows, {len(nutrient_cols)} nutrient columns (论文: 65)")
print(f"portions:  {len(portions)} rows, {portions['Food code'].nunique()} distinct food codes")
print(f"NFS/NS 被展开的描述字段数: {n_changed}")

print("\n[B] food code 一致性")
f, n, p = set(foods["Food code"]), set(nutrients["Food code"]), set(portions["Food code"])
print("foods - nutrients:", len(f - n), "| nutrients - foods:", len(n - f))
print("foods - portions: ", len(f - p), "| portions - foods: ", len(p - f))
print("food code 重复数: foods", foods["Food code"].duplicated().sum(),
      "| nutrients", nutrients["Food code"].duplicated().sum())

print("\n[C] 目标营养素列是否存在、有无缺失")
for c in TARGETS:
    print(f"{c!r}: present={c in nutrients.columns}, missing={nutrients[c].isna().sum()}")

print("\n[D] 模板描述示例")
with_add = foods[foods["Additional food description"].notna()].sample(2, random_state=0)
without_add = foods[foods["Additional food description"].isna()].sample(2, random_state=0)
for _, r in pd.concat([without_add, with_add]).iterrows():
    print(f"{r['Food code']}: {r['description']}")

print("\n[E] portion 表")
per_food = portions.groupby("Food code").size()
print("每个食物的 portion 数: min", per_food.min(), "median", per_food.median(), "max", per_food.max())
zero = portions[portions["Portion weight (g)"].fillna(0) == 0]
print("克重为 0 或缺失的行:", len(zero))
print(zero["Portion description"].value_counts().head(5).to_string())

print("\n[F] 手算核对：Milk, human (11000000)")
code = 11000000
kcal100 = nutrients.loc[nutrients["Food code"] == code, "Energy (kcal)"].iloc[0]
rows = portions[portions["Food code"] == code]
print(rows.to_string(index=False))
w = rows.iloc[0]["Portion weight (g)"]
print(f"Energy per 100 g = {kcal100}; first portion = {w} g -> {kcal100} * {w} / 100 = {kcal100 * w / 100:.2f} kcal")

print("\n[G] Nutrient Values 的 Variable Descriptions 全文（确认单位是 per 100 g）")
pd.set_option("display.max_colwidth", None)
print(pd.read_excel(nut_path, sheet_name="Variable Descriptions").to_string(index=False))

# ---------- 4. 保存 ----------
foods.to_csv(OUT / "foods.csv", index=False)
nutrients.to_csv(OUT / "nutrients.csv", index=False)
portions.to_csv(OUT / "portions.csv", index=False)
print("\nsaved to", OUT)
