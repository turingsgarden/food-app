import struct
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx
import pandas as pd

SEED = 42
BASE = ("https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset/"
        "imagery/realsense_overhead/{}/rgb.png")
OUT = Path("data/nutrition5k/images")
OUT.mkdir(parents=True, exist_ok=True)

src = Path("outputs/nutrition5k_available.csv")
if not src.exists():
    raise SystemExit("outputs/nutrition5k_available.csv not found: run src/17_check_n5k_images.py again")

avail = pd.read_csv(src)
print("available pool:", len(avail))
sample = avail.sample(n=1000, random_state=SEED).sort_values("dish_id").reset_index(drop=True)
sample.to_csv("outputs/nutrition5k_sample.csv", index=False)
print("sampled:", len(sample), "| seed:", SEED)
print(sample["cafe"].value_counts().to_string())

client = httpx.Client(timeout=60, follow_redirects=True)


def fetch(dish_id):
    path = OUT / f"{dish_id}.png"
    if path.exists() and path.stat().st_size > 0:
        return dish_id, "cached"
    try:
        r = client.get(BASE.format(dish_id))
        if r.status_code != 200:
            return dish_id, f"http {r.status_code}"
        path.write_bytes(r.content)
        return dish_id, "ok"
    except Exception as e:
        return dish_id, type(e).__name__


with ThreadPoolExecutor(max_workers=8) as ex:
    res = list(ex.map(fetch, sample["dish_id"]))
print("\ndownload status:", dict(Counter(s for _, s in res)))

sizes, bad, total = [], [], 0
for d in sample["dish_id"]:
    p = OUT / f"{d}.png"
    if not p.exists():
        bad.append((d, "missing"))
        continue
    b = p.read_bytes()
    total += len(b)
    if b[:8] != b"\x89PNG\r\n\x1a\n":
        bad.append((d, "not a png"))
        continue
    sizes.append(struct.unpack(">II", b[16:24]))

print("valid png files:", len(sizes), "| problems:", len(bad), bad[:5])
print(f"total size: {total / 1e6:.0f} MB")
print("image sizes (width, height):", Counter(sizes).most_common(4))

print("\nmean per dish in our sample:")
for c in ["total_mass", "total_calories", "total_fat", "total_carbs", "total_protein"]:
    print(f"{c:15s} {sample[c].mean():8.2f}")