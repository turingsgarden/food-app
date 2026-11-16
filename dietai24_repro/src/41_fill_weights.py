"""Second pass for Nutrition5k dishes whose first weight answer was a refusal ("I'm sorry, I cannot accurately estimate ...").

Only the weight step is asked again, for dishes that have at least one coded item but no usable weight, with the same
prompt plus one sentence asking for a best estimate. Items, codes and everything else are kept. The first answer is
kept in the JSON ("weights_answer_first"). This is a documented exception to the one-pass rule.
Usage: python src/41_fill_weights.py
"""
import glob
import importlib.util
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import pandas as pd

sys.argv = [sys.argv[0], "1000"]
spec = importlib.util.spec_from_file_location("n5k", os.path.join(os.path.dirname(os.path.abspath(__file__)), "40_run_nutrition5k.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

SUFFIX = " If you are unsure, still give your best estimate for every item."

nut = pd.read_csv("outputs/kb/nutrients.csv")
nut["Food code"] = nut["Food code"].astype(int).astype(str)
nut = nut.set_index("Food code")

paths = sorted(glob.glob(m.OUT_DIR + "/*.json"))
recs = {p: json.load(open(p)) for p in paths}
todo = [p for p, r in recs.items() if not r["grams"] and any(i["pred_code"] for i in r["items"])]
print(f"dishes: {len(recs)} | to ask again: {len(todo)}")


def redo(p):
    r = recs[p]
    coded = [it for it in r["items"] if it["pred_code"]]
    img = m.img_content(os.path.join(m.IMG_DIR, r["dish_id"] + ".png"))
    ans = m.chat([{"type": "text", "text": m.P_WEIGHTS.format(items=", ".join(it["item"] for it in coded)) + SUFFIX}, img],
                 max_tokens=600)
    r["weights_answer_first"] = r.get("weights_answer")
    r["weights_answer"] = ans
    r["weights_retry"] = True
    for it, g in zip(coded, m.parse_weights(ans, [it["item"] for it in coded])):
        it["grams"] = {"grams": g}
        if g is not None:
            it["grams"]["nutrients"] = {n: float(nut.loc[it["pred_code"], c]) * g / 100 for n, c in m.NUT.items()}
    r["grams"] = m.dish_sum(r["items"], "grams")
    json.dump(r, open(p, "w"), ensure_ascii=False, indent=1)
    return r["dish_id"], r["grams"] is not None, ans


with ThreadPoolExecutor(m.WORKERS) as ex:
    out = list(ex.map(redo, todo))
for did, ok, ans in out[:3]:
    print(f"  example {did}: usable={ok} | {ans[:120]!r}")
print(f"asked again: {len(out)} | now usable: {sum(1 for _, ok, _ in out if ok)} | still refused/unparsed: {sum(1 for _, ok, _ in out if not ok)}")
m.summarize(list(recs.values()))