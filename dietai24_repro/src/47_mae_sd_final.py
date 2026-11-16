import glob, json
import numpy as np
import pandas as pd

MEAS = [("energy_kcal", "Energy (kcal)"), ("fat_g", "Fat (g)"), ("carb_g", "Carbohydrate (g)"),
        ("protein_g", "Protein (g)"), ("grams", "Weight (g)")]
PAPER = {"ASA24": [47.7, 1.8, 6.95, 1.38, 49.4], "Nutrition5k": [68.2, 4.01, 5.98, 3.88, 45.1]}
rows = []


def add(dataset, label, errs, paper):
    e = np.asarray(errs, dtype=float)
    e = e[~np.isnan(e)]
    rows.append({"dataset": dataset, "measure": label, "n": len(e),
                 "our_MAE": round(e.mean(), 2), "our_SD": round(e.std(ddof=1), 2),
                 "our_MAE_pm_SD": f"{e.mean():.2f} +/- {e.std(ddof=1):.2f}", "paper_MAE": paper})


df = pd.read_csv("outputs/asa24_per_image_results.csv")
for (k, label), pap in zip(MEAS, PAPER["ASA24"]):
    add("ASA24", label, (df[f"B_shot_{k}"] - df[f"truth_{k}"]).abs(), pap)

errs = {k: [] for k, _ in MEAS}
for f in glob.glob("outputs/nutrition5k_run_paperflow/*.json"):
    r = json.load(open(f))
    if r.get("grams"):
        for k, _ in MEAS:
            errs[k].append(abs(r["grams"]["pred"][k] - r["truth"][k]))
for (k, label), pap in zip(MEAS, PAPER["Nutrition5k"]):
    add("Nutrition5k", label, errs[k], pap)

out = pd.DataFrame(rows)
out.to_csv("outputs/mae_sd_vs_paper.csv", index=False)
print(out.to_string(index=False))
print("\nsaved: outputs/mae_sd_vs_paper.csv")