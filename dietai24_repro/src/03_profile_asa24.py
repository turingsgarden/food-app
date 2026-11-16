from pathlib import Path
import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 60)

META = Path("data/asa24/ASA24_ImageMetadata.xlsx")
IMG_DIR = Path("data/asa24/Asa24PortionImages")

inv = pd.read_excel(META, sheet_name="ImageFileInventory")
ac = pd.read_excel(META, sheet_name="AssociatedCodes")
foods = pd.read_csv("outputs/kb/foods.csv")
fnd = set(pd.to_numeric(foods["Food code"]))

print("[A] 文件")
on_disk = {p.name for p in IMG_DIR.glob("*.png")}
print("inventory rows:", len(inv), "| png on disk:", len(on_disk))
print("inventory files not on disk:", int((~inv["FileName"].isin(on_disk)).sum()))
print("disk files not in inventory:", len(on_disk - set(inv["FileName"])))
print("AssociatedCodes rows whose image is not on disk:", int((~ac["Image"].isin(on_disk)).sum()))

print("\n[B] inventory 字段")
print("Display:", inv["Display"].value_counts(dropna=False).to_dict())
print("ImageType:", inv["ImageType"].value_counts(dropna=False).to_dict())
print("sizes (top 5):")
print(inv.groupby(["ImgWidth", "ImgHeight"]).size().sort_values(ascending=False).head(5).to_string())

print("\n[C] AssociatedCodes")
print("rows:", len(ac), "| exact duplicate rows:", int(ac.duplicated().sum()))
print("ImageType:", ac["ImageType"].value_counts(dropna=False).to_dict())
print("ModCode != 0 rows:", int((ac["ModCode"] != 0).sum()))
print("distinct FoodCode:", ac["FoodCode"].nunique())
ac_codes = set(pd.to_numeric(ac["FoodCode"]))
print("FoodCode also in FNDDS 2019-2020:", len(ac_codes & fnd), "| not in 2019-2020:", len(ac_codes - fnd))

print("\n[D] 每个 food code 的图片数 (去重, ModCode==0, 在 2019-2020 中)")
d = ac.drop_duplicates()
d = d[(d["ModCode"] == 0) & (d["FoodCode"].isin(fnd))]
print("ImageType within:", d["ImageType"].value_counts().to_dict())
per = d.groupby("FoodCode")["Image"].nunique()
print(per.describe().to_string())
print("codes with >= 3 images:", int((per >= 3).sum()), "of", len(per))

print("\n[E] PortionCode / Multiplier / Portion 文字 对照")
m = d.merge(inv[["FileName", "Portion"]], left_on="Image", right_on="FileName", how="left")
print("Portion text missing:", int(m["Portion"].isna().sum()), "of", len(m))
print("top PortionCode:", m["PortionCode"].value_counts().head(8).to_dict())
print(m[["FoodCode", "FC_Description", "PortionCode", "PortionSubCode", "Multiplier", "Portion"]]
      .sample(10, random_state=0).to_string(index=False))
