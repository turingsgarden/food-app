from collections import Counter
from pathlib import Path
import pandas as pd

CYCLES = {
    "2011-2012": "NHANES/2011-2012/DR1IFF_G.XPT",
    "2013-2014": "NHANES/2013-2014/DR1IFF_H.XPT",
    "2015-2016": "NHANES/2015-2016/DR1IFF_I.XPT",
    "2017-Mar2020": "NHANES/2017 March-2020 Pre-pandemic/P_DR1IFF.XPT",
}

# 1. NHANES top 1000（复现 asa_proc.py：DR1DRSTZ==1，按 DR1IFDCD 记录数）
total = Counter()
for name, path in CYCLES.items():
    df = pd.read_sas(path)
    n_all = len(df)
    df = df[df["DR1DRSTZ"] == 1]
    codes = pd.to_numeric(df["DR1IFDCD"], errors="coerce").dropna().astype(int)
    c = Counter(codes.tolist())
    total.update(c)
    print(f"{name}: rows={n_all}, status==1 rows={len(df)}, distinct codes={len(c)}")

ranked = total.most_common()
top = ranked[:1000]
share = sum(v for _, v in top) / sum(total.values())
print(f"\ndistinct codes overall: {len(ranked)} | top1000 share of records: {share:.3f}")

# 2. FNDDS 2019-2020
foods = pd.read_csv("outputs/kb/foods.csv")
fnd = set(foods["Food code"].astype(int))
desc = dict(zip(foods["Food code"].astype(int), foods["Main food description"]))

# 3. ASA24：PORTION 类、ModCode==0、图在磁盘上，每个 code 的图片数
META = Path("data/asa24/ASA24_ImageMetadata.xlsx")
IMG_DIR = Path("data/asa24/Asa24PortionImages")
on_disk = {p.name for p in IMG_DIR.glob("*.png")}
ac = pd.read_excel(META, sheet_name="AssociatedCodes").drop_duplicates()
ac["FoodCode"] = pd.to_numeric(ac["FoodCode"], errors="coerce")
ac = ac.dropna(subset=["FoodCode"])
ac["FoodCode"] = ac["FoodCode"].astype(int)
d = ac[(ac["ModCode"] == 0) & (ac["ImageType"] == "PORTION") & ac["Image"].isin(on_disk)]
per = d.groupby("FoodCode")["Image"].nunique()

# 4. 交集
rows = []
for rank, (c, n) in enumerate(top, start=1):
    rows.append({"rank": rank, "food_code": c, "count": n,
                 "in_fndds_2019_2020": c in fnd,
                 "asa24_portion_images": int(per.get(c, 0))})
out = pd.DataFrame(rows)
Path("outputs").mkdir(exist_ok=True)
out.to_csv("outputs/top1000_nhanes.csv", index=False)

print("\n[交集]")
print("top1000 in FNDDS 2019-2020:", int(out["in_fndds_2019_2020"].sum()))
print("top1000 with >=1 ASA24 PORTION image:", int((out["asa24_portion_images"] >= 1).sum()))
print("top1000 with >=3 ASA24 PORTION images:", int((out["asa24_portion_images"] >= 3).sum()))
both = out[out["in_fndds_2019_2020"] & (out["asa24_portion_images"] >= 3)]
print("in FNDDS 2019-2020 AND >=3 images:", len(both), "(论文: 1000 x 3 = 3000 张)")

print("\n[top 10 及描述]")
for r in rows[:10]:
    print(r["rank"], r["food_code"], r["count"], desc.get(r["food_code"], "(not in FNDDS 2019-2020)"))

print("\n[排名最靠前、但不在 FNDDS 2019-2020 里的 10 个 code]")
print(out[~out["in_fndds_2019_2020"]].head(10).to_string(index=False))
print("\nsaved outputs/top1000_nhanes.csv")
