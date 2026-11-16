"""Nutrition5k, portion step as in the paper: choose a FNDDS portion option, then ask how many of its unit are visible.

Re-uses the description, item split, retrieval and food codes already stored in outputs/nutrition5k_run/ (no repeat of those
steps). For every coded item:
  shot   : the paper's portion prompt (verbatim) + one sentence naming the item (our adaptation for mixed dishes)
  amount : the paper's amount prompt (verbatim), unit = the unit of the option chosen in the shot step
  grams  = amount x (weight of the chosen option / its quantity)         e.g. "3 cups" -> 3 x weight of 1 cup
nutrients = per-100 g nutrients of the food code x grams / 100; dish = sum over items.
Results go to outputs/nutrition5k_run_portion/ (one JSON per dish). Usage: python src/43_n5k_portion.py N
"""
import importlib.util
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from fractions import Fraction

import pandas as pd

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
sys.argv = [sys.argv[0], "1000"]
spec = importlib.util.spec_from_file_location("n5k", os.path.join(os.path.dirname(os.path.abspath(__file__)), "40_run_nutrition5k.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

SRC_DIR = m.OUT_DIR
OUT_DIR = "outputs/nutrition5k_run_portion"
os.makedirs(OUT_DIR, exist_ok=True)
m.OUT_DIR = OUT_DIR

# Supplementary Figure 5, verbatim
P_PORTION = ("Could you assess the portion size shown in the image and choose the option that most accurately "
             "represents it from the following choices: {options}.")
P_AMOUNT = ("Please evaluate the portion size presented and specify the quantity: how many {unit} of the "
            "{desc} are visible in the image? Please respond only with the numerical value.")
CANT = m.CANT
norm = m.norm
QTY = re.compile(r"^\s*(\d+(?:\.\d+)?(?:[ -]\d+/\d+)?|\d+/\d+)\s+(.*)$")


def split_qty(desc):
    mt = QTY.match(str(desc))
    if not mt:
        return None, str(desc)
    return float(sum(Fraction(t) for t in re.split(r"[ -]", mt.group(1)))), mt.group(2)


def singular(w):
    return w[:-1] if w.endswith("s") and not w.endswith("ss") else w


def unit_of(option):
    _, rest = split_qty(option)
    u = norm(rest).split(",")[0].strip()
    return singular(u) if u else None


def options_for(por, code):
    p = por[por["Food code"] == code]
    p = p[~p["Portion description"].map(norm).eq("quantity not specified")]
    p = p[p["Portion weight (g)"] > 0].drop_duplicates("Portion description")
    return dict(zip(p["Portion description"], p["Portion weight (g)"].astype(float)))


ART = re.compile(r"\b(a|an|the)\b")


def canon(t):
    t = ART.sub(" ", str(t).lower().replace("**", " "))
    return " ".join(re.sub(r"[^a-z0-9/.() ,\-]", " ", t).split())


def match_option(text, options):
    """Find which FNDDS option a free-text answer names. Parsing only, the prompt is untouched."""
    r = canon(text)
    cands = {canon(o): o for o in options}
    if r in cands:
        return cands[r]
    hits = [o for k, o in cands.items() if k and re.search(r"(?<![a-z0-9])" + re.escape(k) + r"(?![a-z0-9])", r)]
    if hits:
        return max(hits, key=len)
    for bold in re.findall(r"\*\*(.+?)\*\*", str(text)):
        words = set(canon(bold).split())
        uniq = [o for k, o in cands.items() if words and words <= set(re.findall(r"[a-z0-9/.]+", k))]
        if len(uniq) == 1:
            return uniq[0]
    return None


def do_item(it, ctx, img):
    out = {"item": it["item"], "pred_code": it["pred_code"], "name": ctx["name"][it["pred_code"]],
           "shot": None, "amount": None, "grams": {"grams": None}}
    options = options_for(ctx["por"], it["pred_code"])
    if not options:
        return out
    ans = m.chat([{"type": "text", "text": m.P_FOCUS.format(item=it["item"]) +
                   P_PORTION.format(options="; ".join(options))}, img], max_tokens=600)
    opt = None if ans.startswith(CANT) else match_option(ans, list(options))
    out["shot"] = {"answer": ans, "matched": opt}
    if not opt:
        return out
    q, unit = split_qty(opt)[0], unit_of(opt)
    if q is None:
        # the option has no leading quantity (e.g. "Guideline amount in salad"): the option itself is one portion
        g = options[opt]
        out["amount"] = {"unit": None, "unit_g": g, "amount": 1.0,
                         "answer": "(option has no quantity: its weight is used as one portion)"}
        out["grams"] = {"grams": g, "nutrients": {n: float(ctx["nut"].loc[it["pred_code"], c]) * g / 100
                                                  for n, c in m.NUT.items()}}
        return out
    if not q or not unit:
        return out
    per_unit_g = options[opt] / q
    ans = m.chat([{"type": "text", "text": P_AMOUNT.format(unit=unit, desc=out["name"])}, img], max_tokens=600)
    amt = None if ans.startswith(CANT) else m.parse_number(ans)
    out["amount"] = {"unit": unit, "unit_g": per_unit_g, "answer": ans, "amount": amt}
    if amt is not None:
        g = amt * per_unit_g
        out["grams"] = {"grams": g, "nutrients": {n: float(ctx["nut"].loc[it["pred_code"], c]) * g / 100
                                                  for n, c in m.NUT.items()}}
    return out


def process(dish_id, ctx):
    path = os.path.join(OUT_DIR, dish_id + ".json")
    if os.path.exists(path):
        return json.load(open(path))
    src = json.load(open(os.path.join(SRC_DIR, dish_id + ".json")))
    rec = {"dish_id": dish_id, "true_ingredients": src["true_ingredients"], "truth": src["truth"],
           "failed": src.get("failed"), "items": [], "grams": None}
    img = m.img_content(os.path.join(m.IMG_DIR, dish_id + ".png"))
    log = [f"{dish_id} | TRUE {src['truth']['grams']:.0f} g | " + ", ".join(i["item"] for i in src["items"] if i["pred_code"])]
    for it in src["items"]:
        if not it["pred_code"]:
            continue
        r = do_item(it, ctx, img)
        rec["items"].append(r)
        a = r["amount"]
        log.append(f"   {it['item'][:30]:30s} | {str(r['shot'] and r['shot']['matched'])[:28]:28s} | "
                   f"{(str(a['amount']) + ' ' + (a['unit'] or 'portion')) if a else '-':14s} | {r['grams']['grams']} g")
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
    ctx = {"name": dict(zip(foods["Food code"], foods["Main food description"])), "nut": nut.set_index("Food code"), "por": por}
    with ThreadPoolExecutor(m.WORKERS) as ex:
        recs = list(ex.map(lambda d: process(d, ctx), ids))
    m.summarize(recs)


if __name__ == "__main__":
    main()