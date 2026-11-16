import glob
import json
import sys

folder = sys.argv[1]
recs = [json.load(open(p)) for p in sorted(glob.glob(folder + "/*.json"))]

# 论文 Table 3, GPT-4 Turbo: (Exact, Close, Far, Mismatch), 单位 %; Close/Far 是累计的
PAPER = {"largest": (29.1, 77.3, 84.5, 14.5), "medium": (26.3, 68.3, 78.4, 21.6),
         "smallest": (22.1, 59.3, 71.9, 28.1)}
SIZE = {"largest": "largest", "median": "medium", "medium": "medium", "smallest": "smallest"}


def level(r):
    p, t = r.get("pred_code"), r["true_code"]
    if not p:
        return 3
    if p == t:
        return 0
    if p[:2] == t[:2]:
        return 1
    if p[0] == t[0]:
        return 2
    return 3


def show(rows, title):
    n = len(rows)
    print(f"\n{title}  (n = {n})")
    if n == 0:
        return
    lv = [level(r) for r in rows]
    print(f"  Exact match                      {100 * sum(1 for x in lv if x == 0) / n:6.1f} %")
    print(f"  Close  (first 2 digits, cumul.)  {100 * sum(1 for x in lv if x <= 1) / n:6.1f} %")
    print(f"  Far    (first digit,    cumul.)  {100 * sum(1 for x in lv if x <= 2) / n:6.1f} %")
    print(f"  Mismatch                         {100 * sum(1 for x in lv if x == 3) / n:6.1f} %")


print(f"folder: {folder} | images: {len(recs)}")
print("paper, GPT-4 Turbo (Table 3), Exact / Close / Far / Mismatch:")
for k, v in PAPER.items():
    print(f"  {k:9s} {v[0]:5.1f} / {v[1]:5.1f} / {v[2]:5.1f} / {v[3]:5.1f}")

detected = [r for r in recs if r.get("pred_code") and not r.get("failed")]
print(f"\nimages where the model returned a code (paper counts only these): {len(detected)}/{len(recs)}")
for name in ("largest", "medium", "smallest"):
    show([r for r in detected if SIZE.get(r["size"]) == name], f"ours, {name}, images with a code")
show(detected, "ours, all sizes, images with a code")
show(recs, "ours, all sizes, ALL images (no code counts as mismatch)")
print("\nrecall of the retrieval step (true code among the candidates):",
      f"{sum(1 for r in recs if r.get('cand_hit'))}/{len(recs)}")