import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 45)
D = "FNDDS/full/sas/"

fw = pd.read_sas(D + "foodweights.sas7bdat", encoding="latin-1")
fp = pd.read_sas(D + "foodportiondesc.sas7bdat", encoding="latin-1")
for name, df in [("foodweights", fw), ("foodportiondesc", fp)]:
    print("=" * 60)
    print(name, df.shape)
    print(list(df.columns))
    print(df.head(5).to_string(index=False))


def find(df, key):
    for c in df.columns:
        if "".join(ch for ch in str(c).lower() if ch.isalnum()) == key:
            return c
    return None


c_food, c_pc, c_w = find(fw, "foodcode"), find(fw, "portioncode"), find(fw, "portionweight")
c_fpc, c_fpd = find(fp, "portioncode"), find(fp, "portiondescription")
print("\ncolumns used:", c_food, c_pc, c_w, "|", c_fpc, c_fpd)
if None in (c_food, c_pc, c_w, c_fpc, c_fpd):
    raise SystemExit("column names differ from expectation: paste the output above")

fw["k_food"] = pd.to_numeric(fw[c_food]).astype(int)
fw["k_pc"] = pd.to_numeric(fw[c_pc]).astype(int)
print("duplicate (food, portion code) pairs in FoodWeights:", int(fw.duplicated(["k_food", "k_pc"]).sum()))
w = fw.drop_duplicates(["k_food", "k_pc"]).set_index(["k_food", "k_pc"])[c_w]
desc = dict(zip(pd.to_numeric(fp[c_fpc]).astype(int), fp[c_fpd]))

s = pd.read_csv("outputs/asa24_sample.csv")


def unit_g(f, p):
    if int(p) == 98:          # ASA24 ReadMe: 98 = 1 gram
        return 1.0
    return w.get((int(f), int(p)))


s["unit_g"] = [unit_g(f, p) for f, p in zip(s["food_code"], s["portion_code"])]
s["grams"] = s["unit_g"].astype(float) * s["multiplier"]

ok = s["grams"].notna()
print(f"\nrows with grams: {int(ok.sum())}/{len(s)}  (portion code 98 rows: {int((s['portion_code'] == 98).sum())})")
by = s.groupby("food_code")["grams"].apply(lambda x: x.notna().all())
print(f"food codes with all 3 images covered: {int(by.sum())}/{len(by)}")
print("\nportion codes not found (top 10):")
print(s[~ok]["portion_code"].value_counts().head(10).to_string())

print("\nmost common portion codes in the sample and their FNDDS meaning:")
for pc, n in s["portion_code"].value_counts().head(8).items():
    print(pc, n, "->", desc.get(int(pc)))

full = s[s["food_code"].isin(by[by].index)]
piv = full.pivot(index="food_code", columns="size", values="grams")
mono = ((piv["smallest"] <= piv["median"]) & (piv["median"] <= piv["largest"])).mean()
print("\ngrams ordered smallest<=median<=largest:", round(float(mono), 3))

print("\nrandom rows:")
r = s[ok].sample(10, random_state=0).copy()
r["unit_desc"] = [desc.get(int(p)) for p in r["portion_code"]]
print(r[["food_code", "description", "portion_text", "multiplier", "portion_code", "unit_desc", "unit_g", "grams"]].to_string(index=False))
s.to_csv("outputs/asa24_sample_grams_fw.csv", index=False)
print("\nsaved outputs/asa24_sample_grams_fw.csv")
