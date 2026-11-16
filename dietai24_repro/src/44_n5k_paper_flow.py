"""Nutrition5k, following the paper's flow for a whole image (Fig. 1 and "Estimating nutrient content"):
  1. description of the WHOLE dish (paper prompt; re-used from outputs/nutrition5k_run, same prompt, temperature 0)
  2. the description is expanded into five queries (paper prompt), each embedded and searched in the vector DB,
     candidates = unique union                                         -> ONE retrieval per dish, no splitting into items
  3. food code inference with the image + candidates: the model returns the SET of codes present in the image
  4. for each recognized code: choose a portion from the FNDDS options, then ask how many of its unit (paper prompts);
     grams = number x weight per unit; an option without a quantity counts as one portion
  5. nutrients = per-100 g values x grams / 100, summed over the codes of the dish.
Adaptations (not in the paper's text, to be listed in the report):
  * one sentence added to the code prompt asking for the code of EVERY food in the image, one per line
  * the portion prompt starts with the authors' sentence "The image displays the food described as X."
Results: outputs/nutrition5k_run_paperflow/ . Usage: python src/44_n5k_paper_flow.py N
"""
import importlib.util
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor

import pandas as pd

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
sys.argv = [sys.argv[0], str(N)]
here = os.path.dirname(os.path.abspath(__file__))


def load(name, fname):
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, fname))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


p = load("n5kportion", "43_n5k_portion.py")
m = p.m
SRC_DIR = "outputs/nutrition5k_run"
OUT_DIR = "outputs/nutrition5k_run_paperflow"
os.makedirs(OUT_DIR, exist_ok=True)
m.OUT_DIR = OUT_DIR

P_CODE_SET = (m.P_CODE + "\nThe image may show several foods. Give the eight-digit food code of every food that "
              "is present in the image, one code per line.")
P_FOOD = "The image displays the food described as {name}. "
MAX_CODES = 10


def portion_for(code, ctx, img):
    out = {"pred_code": code, "code": code, "name": ctx["name"][code], "shot": None, "amount": None,
           "grams": {"grams": None}}
    options = p.options_for(ctx["por"], code)
    if not options:
        return out
    ans = m.chat([{"type": "text", "text": P_FOOD.format(name=out["name"]) +
                   p.P_PORTION.format(options="; ".join(options))}, img], max_tokens=600)
    opt = None if ans.startswith(m.CANT) else p.match_option(ans, list(options))
    out["shot"] = {"answer": ans, "matched": opt}
    if not opt:
        return out
    q, unit = p.split_qty(opt)[0], p.unit_of(opt)
    if q is None:
        g = options[opt]
        out["amount"] = {"unit": None, "unit_g": g, "amount": 1.0,
                         "answer": "(option has no quantity: its weight is used as one portion)"}
    elif q and unit:
        per_unit_g = options[opt] / q
        ans = m.chat([{"type": "text", "text": p.P_AMOUNT.format(unit=unit, desc=out["name"])}, img], max_tokens=600)
        amt = None if ans.startswith(m.CANT) else m.parse_number(ans)
        out["amount"] = {"unit": unit, "unit_g": per_unit_g, "answer": ans, "amount": amt}
        if amt is None:
            return out
        g = amt * per_unit_g
    else:
        return out
    out["grams"] = {"grams": g, "nutrients": {n: float(ctx["nut"].loc[code, c]) * g / 100 for n, c in m.NUT.items()}}
    return out


def process(dish_id, ctx):
    path = os.path.join(OUT_DIR, dish_id + ".json")
    if os.path.exists(path):
        return json.load(open(path))
    src = json.load(open(os.path.join(SRC_DIR, dish_id + ".json")))
    rec = {"dish_id": dish_id, "true_ingredients": src["true_ingredients"], "truth": src["truth"],
           "failed": src.get("failed"), "desc": src.get("desc"), "items": [], "grams": None}
    log = [f"{dish_id} | TRUE {src['truth']['grams']:.0f} g | {src['true_ingredients'][:80]}",
           "[1] description: " + str(src.get("desc")).replace("\n", " ")[:200]]
    if not src.get("desc") or src.get("failed"):
        rec["failed"] = rec["failed"] or "no description"
    else:
        img = m.img_content(os.path.join(m.IMG_DIR, dish_id + ".png"))
        queries = [q.strip() for q in m.chat(m.P_REWRITE.format(desc=src["desc"])).split("\n") if q.strip()]
        with m.chroma_lock:
            cands = m.retrieve(ctx["col"], queries)
        context = "\n".join(f"Food code: {c}\nFood description: {ctx['text'][c]}" for c in cands if c in ctx["text"])
        ans = m.chat([{"type": "text", "text": P_CODE_SET.format(context=context)}, img])
        codes = []
        for c in re.findall(r"\d{8}", ans):
            if c in cands and c in ctx["name"] and c not in codes:
                codes.append(c)
        codes = codes[:MAX_CODES]
        rec.update(queries=queries, cands=cands, code_answer=ans)
        log.append(f"[2] {len(queries)} queries -> {len(cands)} candidates")
        log.append("[3] codes: " + " | ".join(f"{c} {ctx['name'][c][:30]}" for c in codes))
        for c in codes:
            r = portion_for(c, ctx, img)
            rec["items"].append(r)
            a = r["amount"]
            log.append(f"   {r['name'][:34]:34s} | {str(r['shot'] and r['shot']['matched'])[:24]:24s} | "
                       f"{(str(a['amount']) + ' ' + (a['unit'] or 'portion')) if a else '-':16s} | {r['grams']['grams']} g")
        rec["grams"] = m.dish_sum(rec["items"], "grams")
    json.dump(rec, open(path, "w"), ensure_ascii=False, indent=1)
    with m.print_lock:
        print("\n".join(log), flush=True)
    return rec


def main():
    df = pd.read_csv("outputs/nutrition5k_sample.csv")
    ids = list(df.sample(frac=1, random_state=1).head(N)["dish_id"])
    foods = pd.read_csv("outputs/kb/foods.csv")
    foods["Food code"] = foods["Food code"].astype(int).astype(str)
    nut = pd.read_csv("outputs/kb/nutrients.csv")
    nut["Food code"] = nut["Food code"].astype(int).astype(str)
    por = pd.read_csv("outputs/kb/portions.csv")
    por["Food code"] = por["Food code"].astype(int).astype(str)
    ctx = {"text": dict(zip(foods["Food code"], foods["description"])),
           "name": dict(zip(foods["Food code"], foods["Main food description"])),
           "nut": nut.set_index("Food code"), "por": por,
           "col": m.chromadb.PersistentClient(path="outputs/chroma_db").get_collection("fndds")}
    with ThreadPoolExecutor(m.WORKERS) as ex:
        recs = list(ex.map(lambda d: process(d, ctx), ids))
    m.summarize(recs)


if __name__ == "__main__":
    main()