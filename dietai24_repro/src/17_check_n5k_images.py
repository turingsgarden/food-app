from collections import Counter
from concurrent.futures import ThreadPoolExecutor

import httpx
import pandas as pd

pd.set_option("display.width", 250)

BASE = ("https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset/"
        "imagery/realsense_overhead/{}/rgb.png")
df = pd.read_csv("outputs/nutrition5k_dedup.csv")
client = httpx.Client(timeout=30, follow_redirects=True)


def check(dish_id):
    try:
        r = client.get(BASE.format(dish_id), headers={"Range": "bytes=0-0"})
        return dish_id, r.status_code
    except Exception as e:
        return dish_id, type(e).__name__


with ThreadPoolExecutor(max_workers=16) as ex:
    res = list(ex.map(check, df["dish_id"]))

df["status"] = df["dish_id"].map(dict(res))
print("status codes:", dict(Counter(df["status"].astype(str))))

avail = df[df["status"].isin([200, 206])].copy()
print("\ndishes after dedup:", len(df), "| overhead rgb.png available:", len(avail))
print(avail["cafe"].value_counts().to_string())

paper = {"total_mass": ((150.1, 0.526), (45.1, 0.156)),
         "total_calories": ((168.5, 0.536), (68.2, 0.197)),
         "total_fat": ((8.24, 0.559), (4.01, 0.226)),
         "total_carbs": ((21.9, 0.711), (5.98, 0.212)),
         "total_protein": ((12.9, 0.766), (3.88, 0.188))}
print("\nmean per dish, available pool: ours vs implied by the paper's Table 2")
for c, (fv, da) in paper.items():
    print(f"{c:15s} ours = {avail[c].mean():8.2f} | implied (Foodvisor col) = {fv[0] / fv[1]:8.2f}"
          f" | implied (DietAI24 col) = {da[0] / da[1]:8.2f}")

avail.drop(columns=["status"]).to_csv("outputs/nutrition5k_available.csv", index=False)
print("\nsaved outputs/nutrition5k_available.csv")