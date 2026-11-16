import csv
import pandas as pd

pd.set_option("display.width", 250)

PATHS = {"cafe1": "Nutrition5k/metadata/dish_metadata_cafe1.csv",
         "cafe2": "Nutrition5k/metadata/dish_metadata_cafe2.csv"}


def parse_csv(path):
    rows, bad = [], 0
    with open(path, newline="") as f:
        for r in csv.reader(f):
            if len(r) < 6:
                bad += 1
                continue
            try:
                vals = [float(x) for x in r[1:6]]
            except ValueError:
                bad += 1
                continue
            ingr = [r[i + 1] for i in range(6, len(r) - 1) if r[i].startswith("ingr_")]
            rows.append({"dish_id": r[0], "total_calories": vals[0], "total_mass": vals[1],
                         "total_fat": vals[2], "total_carbs": vals[3], "total_protein": vals[4],
                         "n_ingr": len(ingr), "sorted_ingredients": ", ".join(sorted(ingr))})
    return pd.DataFrame(rows), bad


def author_style_ids(path):
    df = pd.read_csv(path, header=None, engine="python", on_bad_lines="skip")
    return set(df[0])


parts = []
for name, p in PATHS.items():
    d, bad = parse_csv(p)
    d["cafe"] = name
    n_lines = sum(1 for line in open(p) if line.strip())
    ids_pd = author_style_ids(p)
    lost = d[~d["dish_id"].isin(ids_pd)]
    print(f"{name}: lines={n_lines} | parsed with csv module={len(d)} (unparsable={bad}) | "
          f"kept by author-style pandas read={len(ids_pd)} | lost={len(lost)}")
    if len(lost):
        kept = d[d["dish_id"].isin(ids_pd)]
        print(f"   mean #ingredients: lost={lost['n_ingr'].mean():.1f} vs kept={kept['n_ingr'].mean():.1f}")
    parts.append(d)

df = pd.concat(parts, ignore_index=True)
print("\ntotal dishes:", len(df), "| distinct dish_id:", df["dish_id"].nunique())
print("dishes with >=1 ingredient:", int((df["n_ingr"] >= 1).sum()))
print("#ingredients per dish: mean", round(df["n_ingr"].mean(), 1), "| max", int(df["n_ingr"].max()))

df = df[df["n_ingr"] >= 1]
uniq = df.sort_values(["sorted_ingredients", "total_mass"], ascending=[True, False])
uniq = uniq.drop_duplicates("sorted_ingredients", keep="first").sort_values("dish_id")
print("\nafter dedup (same ingredient list -> keep heaviest):", len(uniq))
print(uniq["cafe"].value_counts().to_string())

# 论文 Table 2: 平均值 = MAE per dish / MAE per unit，分别用 Foodvisor 和 DietAI24 两列反推
paper = {"total_mass": ((150.1, 0.526), (45.1, 0.156)),
         "total_calories": ((168.5, 0.536), (68.2, 0.197)),
         "total_fat": ((8.24, 0.559), (4.01, 0.226)),
         "total_carbs": ((21.9, 0.711), (5.98, 0.212)),
         "total_protein": ((12.9, 0.766), (3.88, 0.188))}
print("\nmean per dish after dedup: ours vs implied by the paper's Table 2")
for c, (fv, da) in paper.items():
    print(f"{c:15s} ours = {uniq[c].mean():8.2f} | implied (Foodvisor col) = {fv[0] / fv[1]:8.2f}"
          f" | implied (DietAI24 col) = {da[0] / da[1]:8.2f}")

uniq.to_csv("outputs/nutrition5k_dedup.csv", index=False)
print("\nsaved outputs/nutrition5k_dedup.csv")