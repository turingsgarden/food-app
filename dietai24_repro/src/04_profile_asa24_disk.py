from pathlib import Path
import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 50)

META = Path("data/asa24/ASA24_ImageMetadata.xlsx")
IMG_DIR = Path("data/asa24/Asa24PortionImages")

inv = pd.read_excel(META, sheet_name="ImageFileInventory")
ac = pd.read_excel(META, sheet_name="AssociatedCodes")
foods = pd.read_csv("outputs/kb/foods.csv")
fnd = set(foods["Food code"].astype(int))
on_disk = {p.name for p in IMG_DIR.glob("*.png")}

ac = ac.drop_duplicates().copy()
ac["FoodCode"] = pd.to_numeric(ac["FoodCode"], errors="coerce")
print("rows with non-numeric FoodCode:", int(ac["FoodCode"].isna().sum()))
ac = ac.dropna(subset=["FoodCode"]).copy()
ac["FoodCode"] = ac["FoodCode"].astype(int)
ac["on_disk"] = ac["Image"].isin(on_disk)

print("\n[A] 图片层面")
imgs = ac["Image"].drop_duplicates()
print("distinct images in AssociatedCodes:", len(imgs))
print("  on disk:", int(imgs.isin(on_disk).sum()), "| in inventory:", int(imgs.isin(set(inv["FileName"])).sum()))
print("examples of AC images NOT on disk:", imgs[~imgs.isin(on_disk)].head(8).tolist())
print("disk files not referenced by AC:", len(on_disk - set(ac["Image"])))

print("\n[B] SIZE 与 PORTION 各长什么样（只看磁盘上有的图）")
meta_small = inv[["FileName", "Portion"]].drop_duplicates("FileName")
m = ac.merge(meta_small, left_on="Image", right_on="FileName", how="left")
for t in ["PORTION", "SIZE"]:
    s = m[(m["ImageType"] == t) & m["on_disk"]]
    print(f"\n{t}: rows on disk = {len(s)}, with Portion text = {int(s['Portion'].notna().sum())}")
    cols = ["FoodCode", "FC_Description", "PortionCode", "PortionSubCode", "Multiplier", "Portion"]
    print(s[cols].sample(min(8, len(s)), random_state=1).to_string(index=False))

print("\n[C] 一张图对应几个 food code（去重, ModCode==0, 在 2019-2020 中, 图在磁盘上）")
d = ac[(ac["ModCode"] == 0) & ac["FoodCode"].isin(fnd) & ac["on_disk"]]
codes_per_img = d.groupby("Image")["FoodCode"].nunique()
print("images:", len(codes_per_img),
      "| map to exactly 1 code:", int((codes_per_img == 1).sum()),
      "| map to >1 codes:", int((codes_per_img > 1).sum()))

print("\n[D] 不同过滤条件下，每个 food code 有几张图")
single = set(codes_per_img[codes_per_img == 1].index)
has_txt = set(inv.loc[inv["Portion"].notna(), "FileName"])
variants = {
    "all types": d,
    "PORTION only": d[d["ImageType"] == "PORTION"],
    "PORTION + image maps to 1 code": d[(d["ImageType"] == "PORTION") & d["Image"].isin(single)],
    "PORTION + 1 code + Portion text": d[(d["ImageType"] == "PORTION") & d["Image"].isin(single) & d["Image"].isin(has_txt)],
}
for name, v in variants.items():
    per = v.groupby("FoodCode")["Image"].nunique()
    print(f"{name:34s} codes>=1: {len(per):5d} | codes>=3: {int((per >= 3).sum()):5d}")
