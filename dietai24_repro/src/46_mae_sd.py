"""MAE +/- 1 SD of our reproduced results next to the paper's MAE (per dish / per image).
SD = sample standard deviation (ddof=1) of the per-image absolute errors.
ASA24: from outputs/asa24_per_image_results.csv (B_shot = portion option only, B_amount = option x amount).
Nutrition5k: from outputs/nutrition5k_run_paperflow/*.json (paper-flow version).
Output: printed table + outputs/mae_with_sd_vs_paper.csv
"""
import glob
import json

import numpy as np
import pandas as pd

MEAS = [("energy_kcal", "Energy (kcal)"), ("fat_g", "Fat (g)"), ("carb_g", "Carbohydrate (g)"),
        ("protein_g", "Protein (g)"), ("grams", "Weight (g)")]
PAPER = {"ASA24": [47.7, 1.8, 6.95, 1.38, 49.4], "Nutrition5k": [68.2, 4.01, 5.98, 3.88, 45.1]}
rows = []


def add(dataset, method, key, errs, paper):
    e = np.asarray(errs, dtype=float)
    e = e[~np.isnan(e)]
    rows.append({"dataset": dataset, "method": method, "measure": key, "n": len(e),
                 "our_MAE": round(e.mean(), 2), "our_SD": round(e.std(ddof=1), 2), "paper_MAE": paper})


df = pd.read_csv("outputs/asa24_per_image_results.csv")
for method in ("B_shot", "B_amount"):
    for (k, label), pap in zip(MEAS, PAPER["ASA24"]):
        err = (df[f"{method}_{k}"] - df[f"truth_{k}"]).abs()
        add("ASA24", method, label, err, pap)

errs = {k: [] for k, _ in MEAS}
for f in glob.glob("outputs/nutrition5k_run_paperflow/*.json"):
    r = json.load(open(f))
    if not r.get("grams"):
        continue
    for k, _ in MEAS:
        errs[k].append(abs(r["grams"]["pred"][k] - r["truth"][k]))
for (k, label), pap in zip(MEAS, PAPER["Nutrition5k"]):
    add("Nutrition5k", "paper_flow", label, errs[k], pap)

out = pd.DataFrame(rows)
out["ours_mean_pm_sd"] = out.apply(lambda r: f"{r.our_MAE:.2f} +/- {r.our_SD:.2f}", axis=1)
out.to_csv("outputs/mae_with_sd_vs_paper.csv", index=False)
print(out[["dataset", "method", "measure", "n", "ours_mean_pm_sd", "paper_MAE"]].to_string(index=False))
EOF