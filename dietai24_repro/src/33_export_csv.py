import csv
import glob
import json
import sys

folder = sys.argv[1] if len(sys.argv) > 1 else "outputs/asa24_run_paper"
OUT_SUMMARY = "outputs/asa24_results_vs_paper.csv"
OUT_IMAGES = "outputs/asa24_per_image_results.csv"

recs = [json.load(open(p)) for p in sorted(glob.glob(folder + "/*.json"))]
MEASURES = ["energy_kcal", "fat_g", "carb_g", "protein_g", "grams"]
LABEL = {"energy_kcal": "Energy (kcal)", "fat_g": "Fat (g)", "carb_g": "Carbohydrate (g)",
         "protein_g": "Protein (g)", "grams": "Weight (g)"}
# 论文 Table 1, DietAI24 列: (per dish, per unit)
PAPER = {"energy_kcal": (47.7, 0.196), "fat_g": (1.8, 0.174), "carb_g": (6.95, 0.208),
         "protein_g": (1.38, 0.233), "grams": (49.4, 0.348)}
METHODS = [("B", "shot"), ("B", "amount")]


def pred_of(r, v, k):
    e = r.get(v) and r[v].get(k)
    if not e or e.get("grams") is None:
        return None
    return {"grams": e["grams"], **e["nutrients"]}


# ---------- 1) 汇总表: 论文 vs 我们 ----------
stats = {}
for v, k in METHODS:
    errs = {m: [] for m in MEASURES}
    tr = {m: [] for m in MEASURES}
    for r in recs:
        p = pred_of(r, v, k)
        if p is None:
            continue
        for m in MEASURES:
            errs[m].append(abs(p[m] - r["truth"][m]))
            tr[m].append(r["truth"][m])
    n = len(errs["grams"])
    stats[(v, k)] = {"n": n, **{m: (sum(errs[m]) / n, sum(errs[m]) / sum(tr[m])) if n else (None, None) for m in MEASURES}}

head = ["measure", "paper_DietAI24_per_dish", "paper_DietAI24_per_unit"]
for v, k in METHODS:
    head += [f"ours_{v}_{k}_per_dish", f"ours_{v}_{k}_per_unit"]
rows = []
for m in MEASURES:
    row = [LABEL[m], PAPER[m][0], PAPER[m][1]]
    for key in METHODS:
        d, u = stats[key][m]
        row += [None if d is None else round(d, 3), None if u is None else round(u, 3)]
    rows.append(row)
n_row = ["n images with a usable answer", 3000, 3000]
for key in METHODS:
    n_row += [stats[key]["n"], stats[key]["n"]]
rows.append(n_row)

with open(OUT_SUMMARY, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(head)
    w.writerows(rows)
    w.writerow([])
    w.writerow(["notes"])
    w.writerow(["B = model recognises the food itself (end-to-end, main result)"])
    w.writerow(["shot = choose a portion option; amount = number of units (unit taken from the ASA24 label)"])
    w.writerow(["per dish = mean absolute error; per unit = sum|err| / sum(truth)"])
    w.writerow([f"ours: {len(recs)} ASA24 images, gpt-4o-2024-11-20, temperature 0, top-k 4, paper (supplement) prompts; paper: 3000 images"])

# ---------- 2) 逐图明细 ----------
cols = ["image", "size", "true_code", "pred_code", "true_code_in_candidates", "code_exact"]
cols += [f"truth_{m}" for m in MEASURES]
for v, k in METHODS:
    cols += [f"{v}_{k}_{m}" for m in MEASURES]
with open(OUT_IMAGES, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(cols)
    for r in recs:
        line = [r["image"], r["size"], r["true_code"], r.get("pred_code"), r.get("cand_hit"), r.get("code_ok")]
        line += [round(r["truth"][m], 3) for m in MEASURES]
        for v, k in METHODS:
            p = pred_of(r, v, k)
            line += [None if p is None else round(p[m], 3) for m in MEASURES]
        w.writerow(line)

print(f"images read: {len(recs)}")
print(f"wrote {OUT_SUMMARY}  (paper vs ours, {len(rows)} rows)")
print(f"wrote {OUT_IMAGES}  ({len(recs)} rows)")
print()
print(" | ".join(head))
for r in rows:
    print(" | ".join("" if x is None else str(x) for x in r))