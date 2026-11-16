from pathlib import Path
import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 45)

PLACEHOLDER = "000000000.png"   # 图片内容是 "No image available"

top = pd.read_csv("outputs/top1000_nhanes.csv")
fnd = set(top.loc[top["in_fndds_2019_2020"], "food_code"])
rank = dict(zip(top["food_code"], top["rank"]))

META = Path("data/asa24/ASA24_ImageMetadata.xlsx")
IMG_DIR = Path("data/asa24/Asa24PortionImages")
on_disk = {p.name for p in IMG_DIR.glob("*.png")}

ac = pd.read_excel(META, sheet_name="AssociatedCodes").drop_duplicates()
ac["FoodCode"] = pd.to_numeric(ac["FoodCode"], errors="coerce")
ac = ac.dropna(subset=["FoodCode"]).copy()
ac["FoodCode"] = ac["FoodCode"].astype(int)
ac = ac[ac["FoodCode"].isin(fnd) & (ac["ModCode"] == 0)
        & (ac["ImageType"] == "PORTION") & ac["Image"].isin(on_disk)]

n_ph = int((ac["Image"] == PLACEHOLDER).sum())
ac = ac[ac["Image"] != PLACEHOLDER]
print("placeholder rows removed before sampling:", n_ph)

inv = pd.read_excel(META, sheet_name="ImageFileInventory")[["FileName", "Portion", "Display"]]
inv = inv.drop_duplicates("FileName")
ac = ac.merge(inv, left_on="Image", right_on="FileName", how="left")

picked = []
n_codes = n_ok = n_multi = 0
for code, g in ac.groupby("FoodCode"):
    n_codes += 1
    s = (g.groupby(["PortionCode", "PortionSubCode"])["Multiplier"].nunique()
           .reset_index(name="n")
           .sort_values(["n", "PortionCode", "PortionSubCode"], ascending=[False, True, True]))
    if len(s) > 1:
        n_multi += 1
    pc, psc = s.iloc[0]["PortionCode"], s.iloc[0]["PortionSubCode"]
    best = g[(g["PortionCode"] == pc) & (g["PortionSubCode"] == psc)]
    best = best.sort_values(["Multiplier", "Image"]).drop_duplicates("Multiplier")
    if len(best) < 3:
        continue
    n_ok += 1
    for label, i in zip(["smallest", "median", "largest"], [0, len(best) // 2, len(best) - 1]):
        r = best.iloc[i]
        picked.append({"rank": rank[code], "food_code": code, "description": r["FC_Description"],
                       "size": label, "image": r["Image"], "portion_code": pc,
                       "portion_subcode": psc, "multiplier": r["Multiplier"],
                       "portion_text": r["Portion"], "display": r["Display"]})

out = pd.DataFrame(picked).sort_values(["rank", "multiplier"])
out.to_csv("outputs/asa24_sample.csv", index=False)

print(f"codes with >=1 usable image: {n_codes}")
print(f"codes whose images use more than one portion unit: {n_multi}")
print(f"codes with >=3 distinct sizes in one unit: {n_ok}  -> images: {len(out)}")
print("distinct images:", out["image"].nunique())
print("\nsaved outputs/asa24_sample.csv")
