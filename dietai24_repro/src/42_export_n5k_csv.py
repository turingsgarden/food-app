import csv
import glob
import json
import sys

folder = sys.argv[1] if len(sys.argv) > 1 else "outputs/nutrition5k_run"
OUT_SUMMARY = "outputs/n5k_results_vs_paper.csv"
OUT_DISHES = "outputs/n5k_per_dish_results.csv"

recs = [json.load(open(p)) for p in sorted(glob.glob(folder + "/*.json"))]
MEASURES = ["energy_kcal", "fat_g", "carb_g", "protein_g", "grams"]
LABEL = {"energy_kcal": "Energy (kcal)", "fat_g": "Fat (g)", "carb_g": "Carbohydrate (g)",
         "protein_g": "Protein (g)", "grams": "Weight (g)"}
# paper Table 2, DietAI24: (per dish, per unit)
PAPER = {"energy_kcal": (68.2, 0.197), "fat_g": (4.01, 0.226), "carb_g": (5.98, 0.212),
         "protein_g": (3.88, 0.188), "grams": (45.1, 0.156)}

ok = [r for r in recs if r.get("grams")]
errs = {m: [abs(r["grams"]["pred"][m] - r["truth"][m]) for r in ok] for m in MEASURES}
tr = {m: [r["truth"][m] for r in ok] for m in MEASURES}
n = len(ok)

with open(OUT_SUMMARY, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["measure", "paper_DietAI24_per_dish", "paper_DietAI24_per_unit", "ours_per_dish", "ours_per_unit"])
    for m in MEASURES:
        d = sum(errs[m]) / n if n else None
        u = sum(errs[m]) / sum(tr[m]) if n and sum(tr[m]) else None
        w.writerow([LABEL[m], PAPER[m][0], PAPER[m][1], None if d is None else round(d, 3), None if u is None else round(u, 3)])
    w.writerow(["n dishes with a usable answer", 1000, 1000, n, n])
    w.writerow([])
    w.writerow(["notes"])
    w.writerow(["per dish = mean absolute error; per unit = sum|err| / sum(truth)"])
    w.writerow(["Nutrition5k, model recognises the foods itself (end-to-end); weights asked directly in grams for all items of a dish in one call"])
    w.writerow([f"ours: {len(recs)} dishes run, {n} with a usable answer; gpt-4o-2024-11-20, temperature 0, top-k 4, paper (supplement) prompts for description/rewrite/code; paper: 1000 dishes"])
    w.writerow(["the splitting of a dish into food items and the joint weight prompt are ours (the authors' mixed-dish prompts are not public)"])
    w.writerow([f"{sum(1 for r in recs if r.get('weights_retry'))} dishes had their first weight answer refused and were asked once more with 'give your best estimate'"])

cols = ["dish_id", "true_ingredients", "n_items", "items_and_codes", "weights_retry"]
cols += [f"truth_{m}" for m in MEASURES] + [f"pred_{m}" for m in MEASURES]
with open(OUT_DISHES, "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(cols)
    for r in recs:
        items = "; ".join(f"{i['item']} [{i['pred_code']}]" for i in r["items"])
        line = [r["dish_id"], r["true_ingredients"], len(r["items"]), items, bool(r.get("weights_retry"))]
        line += [round(r["truth"][m], 3) for m in MEASURES]
        line += [round(r["grams"]["pred"][m], 3) if r.get("grams") else None for m in MEASURES]
        w.writerow(line)

print(f"dishes read: {len(recs)} | with a usable answer: {n}")
print(f"wrote {OUT_SUMMARY}")
print(f"wrote {OUT_DISHES}  ({len(recs)} rows)")
print()
with open(OUT_SUMMARY, encoding="utf-8-sig") as f:
    for line in list(f)[:7]:
        print(line.rstrip())