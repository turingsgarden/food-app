import re
from fractions import Fraction
import pandas as pd

pd.set_option("display.width", 250)
pd.set_option("display.max_colwidth", 40)

s = pd.read_csv("outputs/asa24_sample_grams_07.csv")
s = s[s["grams"].notna()].copy()

fp = pd.read_sas("FNDDS/full/sas_2007_2008/foodportiondesc.sas7bdat", encoding="latin-1")
desc = dict(zip(fp["Portion_code"].astype(int), fp["Portion_description"]))

PAT = re.compile(
    r"^\s*(\d+\s*-\s*\d+/\d+|\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s*(cups?|tablespoons?|teaspoons?|fl\.? oz|fo)\b",
    re.I,
)


def text_floz(t):
    if not isinstance(t, str):
        return None
    m = PAT.match(t)
    if not m:
        return None
    amt = sum(Fraction(p) for p in re.split(r"[\s-]+", m.group(1).strip()))
    u = m.group(2).lower()
    if u.startswith("cup"):
        f = 8.0
    elif u.startswith("tablespoon"):
        f = 0.5
    elif u.startswith("teaspoon"):
        f = 1.0 / 6
    else:
        f = 1.0
    return float(amt) * f


def code_floz(pc, mult):
    d = str(desc.get(int(pc), "")).lower()
    if d.startswith("1 cup"):
        f = 8.0
    elif d.startswith("1 fl oz"):
        f = 1.0
    elif d.startswith("1 tablespoon"):
        f = 0.5
    elif d.startswith("1 teaspoon"):
        f = 1.0 / 6
    else:
        return None
    return float(mult) * f


rows = []
for _, r in s.iterrows():
    t = text_floz(r["portion_text"])
    c = code_floz(r["portion_code"], r["multiplier"])
    if t is None or c is None or c == 0:
        continue
    rows.append((r["food_code"], r["description"], r["portion_text"], r["multiplier"],
                 r["portion_code"], desc.get(int(r["portion_code"])), t / c))
d = pd.DataFrame(rows, columns=["food_code", "description", "portion_text", "multiplier",
                                "portion_code", "unit_desc", "ratio"])

ok = (d["ratio"] - 1).abs() <= 0.03
print("rows in the sample with grams:", len(s))
print("rows comparable (volume units):", len(d))
print("consistent within 3%:", int(ok.sum()), "| inconsistent:", int((~ok).sum()))
print("\nratio = (volume from text) / (volume from Multiplier), inconsistent rows:")
print(d[~ok]["ratio"].round(2).value_counts().head(10).to_string())
print("\nexamples of inconsistent rows:")
print(d[~ok].head(15).to_string(index=False))
d.to_csv("outputs/asa24_text_vs_multiplier.csv", index=False)
print("\nsaved outputs/asa24_text_vs_multiplier.csv")