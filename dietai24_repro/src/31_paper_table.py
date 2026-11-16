import glob
import json
import sys

folder = sys.argv[1]
recs = [json.load(open(p)) for p in sorted(glob.glob(folder + "/*.json"))]
n = len(recs)

# 论文 Table 1（ASA24, DietAI24 一列）: (per dish, per unit)
PAPER = {"energy_kcal": (47.7, 0.196), "fat_g": (1.8, 0.174), "carb_g": (6.95, 0.208),
         "protein_g": (1.38, 0.233), "grams": (49.4, 0.348)}
ROWS = [("Energy (kcal)", "energy_kcal"), ("Fat (g)", "fat_g"), ("Carbohydrate (g)", "carb_g"),
        ("Protein (g)", "protein_g"), ("Weight (g)", "grams")]
COMBOS = [("A", "shot"), ("A", "amount"), ("B", "shot"), ("B", "amount")]


def stats(v, k, m):
    errs, truth = [], []
    for r in recs:
        e = r.get(v) and r[v].get(k)
        if not e or e.get("grams") is None:
            continue
        pred = e["grams"] if m == "grams" else e["nutrients"][m]
        errs.append(abs(pred - r["truth"][m]))
        truth.append(r["truth"][m])
    if not errs:
        return None
    return len(errs), sum(errs) / len(errs), sum(errs) / max(sum(truth), 1e-9)


print(f"folder: {folder} | images: {n}")
print(f"vision refused: {sum(1 for r in recs if r.get('failed'))}")
print(f"true code in candidates: {sum(1 for r in recs if r.get('cand_hit'))}/{n}")
print(f"food code exactly right: {sum(1 for r in recs if r.get('code_ok'))}/{n}")
print("\nmean ground truth in our test set:")
for name, m in ROWS:
    print(f"  {name:18s} {sum(r['truth'][m] for r in recs) / n:8.2f}   (paper-implied: {PAPER[m][0] / PAPER[m][1]:.1f})")

print("\nper dish / per unit   (per dish = mean |err|; per unit = sum|err| / sum(truth))")
head = f"{'':18s} {'PAPER':>14s} " + " ".join(f"{v + ' ' + k:>16s}" for v, k in COMBOS)
print(head)
ns = []
for v, k in COMBOS:
    s = stats(v, k, "grams")
    ns.append(s[0] if s else 0)
print(f"{'n usable':18s} {'3000':>14s} " + " ".join(f"{x:>16d}" for x in ns))
for name, m in ROWS:
    cells = []
    for v, k in COMBOS:
        s = stats(v, k, m)
        cells.append("n/a" if s is None else f"{s[1]:.2f} / {s[2]:.3f}")
    print(f"{name:18s} {PAPER[m][0]:>7.2f} /{PAPER[m][1]:>5.3f} " + " ".join(f"{c:>16s}" for c in cells))
EOF_MARKER = None