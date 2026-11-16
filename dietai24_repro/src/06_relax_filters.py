from pathlib import Path
import pandas as pd

top = pd.read_csv("outputs/top1000_nhanes.csv")
top_codes = set(top["food_code"])
fnd = set(top.loc[top["in_fndds_2019_2020"], "food_code"])

META = Path("data/asa24/ASA24_ImageMetadata.xlsx")
IMG_DIR = Path("data/asa24/Asa24PortionImages")
on_disk = {p.name for p in IMG_DIR.glob("*.png")}
ac = pd.read_excel(META, sheet_name="AssociatedCodes").drop_duplicates()
ac["FoodCode"] = pd.to_numeric(ac["FoodCode"], errors="coerce")
ac = ac.dropna(subset=["FoodCode"]).copy()
ac["FoodCode"] = ac["FoodCode"].astype(int)
ac = ac[ac["FoodCode"].isin(top_codes) & ac["Image"].isin(on_disk)]


def count(df, need_fndds):
    if need_fndds:
        df = df[df["FoodCode"].isin(fnd)]
    per = df.groupby("FoodCode")["Image"].nunique()
    return int((per >= 1).sum()), int((per >= 3).sum())


print("top1000 codes: >=1 image / >=3 images")
for need_fndds in [True, False]:
    for types, lt in [(["PORTION"], "PORTION"), (["PORTION", "SIZE"], "PORTION+SIZE")]:
        for mods, lm in [(False, "ModCode=0"), (True, "incl. ModCode!=0")]:
            df = ac[ac["ImageType"].isin(types)]
            if not mods:
                df = df[df["ModCode"] == 0]
            a, b = count(df, need_fndds)
            fl = "in FNDDS 2019-2020" if need_fndds else "any code (no FNDDS filter)"
            print(f"{fl:28s} | {lt:13s} | {lm:17s} -> {a:4d} / {b:4d}")
