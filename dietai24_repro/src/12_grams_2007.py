import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 45)
D07 = "FNDDS/full/sas_2007_2008/"
D19 = "FNDDS/full/sas/"

fw07 = pd.read_sas(D07 + "foodweights.sas7bdat", encoding="latin-1")
fp07 = pd.read_sas(D07 + "foodportiondesc.sas7bdat", encoding="latin-1")
fw19 = pd.read_sas(D19 + "foodweights.sas7bdat", encoding="latin-1")
for df in (fw07, fw19):
    df["Food_code"] = df["Food_code"].astype(int)
    df["Portion_code"] = df["Portion_code"].astype(int)
fw07["Subcode"] = fw07["Subcode"].astype(int)
print("2007-08 FoodWeights rows:", len(fw07),
      "| duplicate (food, portion, subcode):", int(fw07.duplicated(["Food_code", "Portion_code", "Subcode"]).sum()))
print("FoodPortionDesc 2007-08 columns:", list(fp07.columns))

pcol = [c for c in fp07.columns if c.lower() == "portion_code"][0]
dcol = [c for c in fp07.columns if "descr" in c.lower()][0]
desc07 = dict(zip(fp07[pcol].astype(int), fp07[dcol]))

grp07 = {k: g for k, g in fw07.groupby(["Food_code", "Portion_code"])}
w19 = fw19.drop_duplicates(["Food_code", "Portion_code"]).set_index(["Food_code", "Portion_code"])["Portion_weight"]
NAN = float("nan")


def unit07(f, pc, sub):
    if int(pc) == 98:
        return 1.0
    g = grp07.get((int(f), int(pc)))
    if g is None:
        return NAN
    if len(g) > 1:
        g = g[g["Subcode"] == int(sub)]
    return float(g["Portion_weight"].iloc[0]) if len(g) == 1 else NAN


def unit19(f, pc):
    if int(pc) == 98:
        return 1.0
    return float(w19.get((int(f), int(pc)), NAN))


s = pd.read_csv("outputs/asa24_sample.csv")
s["unit_g_07"] = [unit07(f, p, sb) for f, p, sb in zip(s["food_code"], s["portion_code"], s["portion_subcode"])]
s["unit_g_19"] = [unit19(f, p) for f, p in zip(s["food_code"], s["portion_code"])]
s["grams"] = s["unit_g_07"] * s["multiplier"]

ok07, ok19 = s["unit_g_07"].notna(), s["unit_g_19"].notna()
print(f"\nrows with a unit weight: 2007-08 = {int(ok07.sum())} | 2019-20 = {int(ok19.sum())} (of {len(s)})")
print("found in: both", int((ok07 & ok19).sum()), "| 2007-08 only", int((ok07 & ~ok19).sum()),
      "| 2019-20 only", int((~ok07 & ok19).sum()), "| neither", int((~ok07 & ~ok19).sum()))
by = s.groupby("food_code")["grams"].apply(lambda x: x.notna().all())
print(f"food codes with all 3 images covered (2007-08): {int(by.sum())}/{len(by)}")
print("rows with grams == 0:", int((s["grams"] == 0).sum()))

print("\nportion codes with no 2007-08 weight (top 10):")
miss = s[~ok07]["portion_code"].value_counts().head(10)
for pc, n in miss.items():
    print(pc, n, "->", desc07.get(int(pc)))

b = s[ok07 & ok19 & (s["portion_code"] != 98) & (s["unit_g_07"] > 0)]
ratio = b["unit_g_19"] / b["unit_g_07"]
print(f"\nunit weight 2019-20 vs 2007-08 on {len(b)} rows in both: within 1% = {((ratio - 1).abs() <= 0.01).mean():.3f}"
      f" | median |ratio-1| = {(ratio - 1).abs().median():.3f} | max |ratio-1| = {(ratio - 1).abs().max():.2f}")

full = s[s["food_code"].isin(by[by].index)]
piv = full.pivot(index="food_code", columns="size", values="grams")
print("grams ordered smallest<=median<=largest:", round(float(((piv["smallest"] <= piv["median"]) & (piv["median"] <= piv["largest"])).mean()), 3))

print("\nrandom rows:")
r = s[ok07].sample(10, random_state=0).copy()
r["unit_desc"] = [desc07.get(int(p)) for p in r["portion_code"]]
print(r[["food_code", "description", "portion_text", "multiplier", "portion_code", "unit_desc", "unit_g_07", "grams"]].to_string(index=False))
s.to_csv("outputs/asa24_sample_grams_07.csv", index=False)
print("\nsaved outputs/asa24_sample_grams_07.csv")