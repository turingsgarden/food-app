import re
from fractions import Fraction
import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 40)

ALIAS = {"fo": "fl oz", "fluid ounce": "fl oz", "fluid ounces": "fl oz"}
IRREG = {"leaves": "leaf", "loaves": "loaf", "halves": "half", "knives": "knife"}


def singular(w):
    if w in IRREG:
        return IRREG[w]
    if w.endswith("ies") and len(w) > 4:
        return w[:-3] + "y"
    if w.endswith(("ches", "shes", "xes", "sses")):
        return w[:-2]
    if w.endswith("s") and not w.endswith("ss") and len(w) > 3:
        return w[:-1]
    return w


def norm_unit(u):
    u = " ".join(str(u).lower().split())
    if u in ALIAS:
        return ALIAS[u]
    parts = u.split(" ")
    parts[-1] = singular(parts[-1])
    u = " ".join(parts)
    return ALIAS.get(u, u)


def parse_portion(text):
    if not isinstance(text, str):
        return None
    m = re.match(r"^\s*(\d+\s+\d+/\d+|\d+/\d+|\d*\.?\d+)\s*(.*)$", text.strip())
    if not m:
        return None
    try:
        amt = float(sum(Fraction(p) for p in m.group(1).split()))
    except Exception:
        return None
    if amt <= 0:
        return None
    return amt, norm_unit(m.group(2))


sample = pd.read_csv("outputs/asa24_sample.csv")
por = pd.read_csv("outputs/kb/portions.csv")
por = por[por["Portion weight (g)"].fillna(0) > 0]

recs = []
for _, r in por.iterrows():
    p = parse_portion(r["Portion description"])
    if p:
        recs.append((int(r["Food code"]), p[0], p[1], r["Portion description"], float(r["Portion weight (g)"])))
pt = pd.DataFrame(recs, columns=["code", "amt", "unit", "desc", "wt"])
print("FNDDS portion rows usable for matching:", len(pt), "of", len(por))

rows = []
for _, r in sample.iterrows():
    out = dict(r)
    out.update(parsed_amt=None, parsed_unit=None, matched_desc=None, grams=None)
    p = parse_portion(r["portion_text"])
    if p:
        a, u = p
        out["parsed_amt"], out["parsed_unit"] = a, u
        c = pt[(pt["code"] == r["food_code"]) & (pt["unit"] == u)]
        if len(c):
            c = c.iloc[(c["amt"] - a).abs().to_numpy().argmin()]
            out["matched_desc"] = c["desc"]
            out["grams"] = a * c["wt"] / c["amt"]
    rows.append(out)
res = pd.DataFrame(rows)
res.to_csv("outputs/asa24_sample_grams.csv", index=False)

n, ok = len(res), int(res["grams"].notna().sum())
print(f"\nrows with grams: {ok}/{n}")
bad = res[res["grams"].isna()]
print("unmatched: portion text not parsed =", int(bad["parsed_unit"].isna().sum()),
      "| parsed, but no FNDDS portion with that unit =", int(bad["parsed_unit"].notna().sum()))
print("\nmost common unparsed portion texts:")
print(bad[bad["parsed_unit"].isna()]["portion_text"].astype(str).value_counts().head(8).to_string())
print("\nmost common units with no FNDDS match:")
print(bad[bad["parsed_unit"].notna()]["parsed_unit"].value_counts().head(12).to_string())

full = res.groupby("food_code")["grams"].apply(lambda s: s.notna().all())
print(f"\nfood codes with all 3 images matched: {int(full.sum())}/{len(full)}")
piv = res[res["food_code"].isin(full[full].index)].pivot(index="food_code", columns="size", values="grams")
mono = ((piv["smallest"] <= piv["median"]) & (piv["median"] <= piv["largest"])).mean()
print(f"of those, grams ordered smallest<=median<=largest: {mono:.3f}")

print("\nrandom matched rows:")
print(res[res["grams"].notna()].sample(10, random_state=0)
      [["food_code", "description", "portion_text", "matched_desc", "grams"]].to_string(index=False))
print("\nsaved outputs/asa24_sample_grams.csv")
