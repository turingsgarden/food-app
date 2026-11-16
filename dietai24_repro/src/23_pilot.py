import importlib.util
import json
import os
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from fractions import Fraction

import chromadb
import pandas as pd

# 复用第二阶段（它又复用第一阶段）的函数，保证用同一份用量统计
spec = importlib.util.spec_from_file_location("stage2", "src/22_pipeline_stage2.py")
s2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s2)
s1 = s2.s1

N = int(sys.argv[1]) if len(sys.argv) > 1 else 20
WORKERS = 8
OUT_DIR = "outputs/pilot"
os.makedirs(OUT_DIR, exist_ok=True)
NUT = s2.NUT_COLS
MEASURES = ["grams"] + list(NUT)
print_lock = threading.Lock()
chroma_lock = threading.Lock()

P_AMOUNT = ("The image displays the food described as {desc}. Please evaluate the portion size "
            "presented and specify the quantity: how many {unit} of the food are visible in the "
            "image? Please respond only with the numerical value.")

QTY = re.compile(r"^\s*(\d+(?:\.\d+)?(?:[ -]\d+/\d+)?|\d+/\d+)\s+(.*)$")


def split_qty(desc):
    m = QTY.match(str(desc))
    if not m:
        return None, str(desc)
    q = sum(Fraction(t) for t in re.split(r"[ -]", m.group(1)))
    return float(q), m.group(2)


def singular(w):
    return w[:-1] if w.endswith("s") and not w.endswith("ss") else w


def label_unit(portion_text):
    _, rest = split_qty(portion_text)
    u = s2.norm(rest).split(",")[0].strip()
    return singular(u) if u else None


def unit_weight(options, unit):
    for d, w in options.items():
        q, rest = split_qty(d)
        if q and q > 0 and singular(s2.norm(rest).split(",")[0].strip()) == unit:
            return w / q
    return None


def parse_number(text):
    m = re.search(r"(\d+)\s+(\d+)/(\d+)", text)
    if m:
        return int(m.group(1)) + int(m.group(2)) / int(m.group(3))
    m = re.search(r"(\d+)\s*/\s*(\d+)", text)
    if m:
        return int(m.group(1)) / int(m.group(2))
    m = re.search(r"\d+(?:\.\d+)?", text)
    return float(m.group(0)) if m else None


def options_for(por, code):
    p = por[por["Food code"] == code]
    p = p[~p["Portion description"].map(s2.norm).eq("quantity not specified")]
    p = p[p["Portion weight (g)"] > 0].drop_duplicates("Portion description")
    return dict(zip(p["Portion description"], p["Portion weight (g)"].astype(float)))


def nutrients(nut, code, grams):
    return {k: float(nut.loc[code, c]) * grams / 100 for k, c in NUT.items()}


def estimate(code, ctx, b64, row, log, tag):
    fdesc, por, nut = ctx["fdesc"], ctx["por"], ctx["nut"]
    options = options_for(por, code)
    res = {"code": code, "shot": None, "amount": None}
    log.append(f"\n--- {tag}: food code {code} | {len(options)} portion options")
    img = {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}
    if options:
        ans = s1.chat([{"type": "text", "text": s2.P_PORTION.format(desc=fdesc[code], options="; ".join(options))}, img])
        opt = s2.match_option(ans, list(options))
        grams = float(options[opt]) if opt else None
        res["shot"] = {"answer": ans, "matched": opt, "grams": grams}
        log.append(f"  [shot]   answer: {ans!r} -> {opt} -> {grams} g")
    unit = label_unit(row["portion_text"])
    uw = unit_weight(options, unit) if unit else None
    if uw:
        ans = s1.chat([{"type": "text", "text": P_AMOUNT.format(desc=fdesc[code], unit=unit + "s")}, img])
        amt = parse_number(ans)
        grams = amt * uw if amt is not None else None
        res["amount"] = {"unit": unit, "unit_g": uw, "answer": ans, "amount": amt, "grams": grams}
        log.append(f"  [amount] unit '{unit}' ({uw:.1f} g each): answer {ans!r} -> {amt} -> {grams} g")
    else:
        log.append(f"  [amount] skipped: unit {unit!r} not found among this food's FNDDS portion options")
    for k in ("shot", "amount"):
        if res[k] and res[k]["grams"] is not None:
            res[k]["nutrients"] = nutrients(nut, code, res[k]["grams"])
    return res


def process(row, ctx):
    path = os.path.join(OUT_DIR, f"{row['image']}_{row['food_code']}.json")
    if os.path.exists(path):
        return json.load(open(path))
    log = ["\n" + "=" * 70,
           f"image {row['image']} | {row['size']} | label {row['portion_text']} | TRUE {row['food_code']} {row['description']}",
           f"TRUE grams {row['grams']:.1f} | kcal {row['energy_kcal']:.1f} | fat {row['fat_g']:.2f} | carb {row['carb_g']:.2f} | protein {row['protein_g']:.2f}"]
    b64 = s1.img_b64(os.path.join(s1.IMG_DIR, row["image"]))
    img = {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}
    desc = s1.chat([{"type": "text", "text": s1.P_DESCRIBE}, img])
    log.append("[1] description: " + desc.replace("\n", " ")[:400])
    queries = [q.strip() for q in s1.chat(s1.P_REWRITE.format(desc=desc)).split("\n") if q.strip()][:5]
    log.append(f"[2] {len(queries)} queries; first: {queries[0][:160] if queries else ''}")
    with chroma_lock:
        cands = s2.retrieve(ctx["col"], queries)
    hit = row["food_code"] in cands
    log.append(f"[3] {len(cands)} candidates | true code in candidates: {hit}")
    context = "\n".join(f"Food code: {c}\nFood description: {ctx['fdesc'][c]}" for c in cands if c in ctx["fdesc"])
    ans = s1.chat([{"type": "text", "text": s2.P_CODE.format(desc=desc, context=context)}, img])
    code, status = s2.parse_code(ans, set(cands))
    log.append(f"[4] code answer {ans!r} -> {code} ({status}) | correct: {code == row['food_code']}")
    rec = {"image": row["image"], "true_code": row["food_code"], "size": row["size"],
           "truth": {m: float(row[m]) for m in MEASURES}, "desc": desc, "n_cands": len(cands),
           "cand_hit": hit, "pred_code": code, "code_ok": code == row["food_code"]}
    rec["A"] = estimate(row["food_code"], ctx, b64, row, log, "[5] A: true food")
    if code is not None and code in ctx["fdesc"]:
        rec["B"] = rec["A"] if code == row["food_code"] else estimate(code, ctx, b64, row, log, "[5] B: predicted food")
    else:
        rec["B"] = None
    json.dump(rec, open(path, "w"), ensure_ascii=False, indent=1)
    with print_lock:
        print("\n".join(log), flush=True)
    return rec


def summarize(recs):
    print("\n" + "#" * 70)
    n = len(recs)
    print(f"SUMMARY over {n} images")
    print(f"true code in candidates: {sum(r['cand_hit'] for r in recs)}/{n}")
    print(f"food code exactly right: {sum(r['code_ok'] for r in recs)}/{n}")
    print("\nMAE per dish (abs error averaged over images); per-unit = sum|err| / sum(truth)")
    print(f"{'variant/method':16s} {'n':>3s} " + " ".join(f"{m:>16s}" for m in MEASURES))
    for v in ("A", "B"):
        for k in ("shot", "amount"):
            errs = {m: [] for m in MEASURES}
            tr = {m: [] for m in MEASURES}
            for r in recs:
                e = r.get(v) and r[v].get(k)
                if not e or e.get("grams") is None:
                    continue
                pred = {"grams": e["grams"], **e["nutrients"]}
                for m in MEASURES:
                    errs[m].append(abs(pred[m] - r["truth"][m]))
                    tr[m].append(r["truth"][m])
            cnt = len(errs["grams"])
            if cnt == 0:
                print(f"{v + ' ' + k:16s} {0:3d}  (no data)")
                continue
            cells = []
            for m in MEASURES:
                cells.append(f"{sum(errs[m]) / cnt:7.2f}/{sum(errs[m]) / max(sum(tr[m]), 1e-9):6.3f}")
            print(f"{v + ' ' + k:16s} {cnt:3d} " + " ".join(f"{c:>16s}" for c in cells))
    print("\ntokens -> chat in:", s1.usage["in"], "| chat out:", s1.usage["out"], "| embedding:", s1.usage["emb"])


def main():
    gt = pd.read_csv("outputs/asa24_ground_truth.csv", dtype={"food_code": str})
    pick = gt.sample(N, random_state=1)
    foods = pd.read_csv("outputs/kb/foods.csv")
    foods["Food code"] = foods["Food code"].astype(int).astype(str)
    nut = pd.read_csv("outputs/kb/nutrients.csv")
    nut["Food code"] = nut["Food code"].astype(int).astype(str)
    por = pd.read_csv("outputs/kb/portions.csv")
    por["Food code"] = por["Food code"].astype(int).astype(str)
    ctx = {"fdesc": dict(zip(foods["Food code"], foods["description"])), "nut": nut.set_index("Food code"),
           "por": por, "col": chromadb.PersistentClient(path="outputs/chroma_db").get_collection("fndds")}
    rows = [r for _, r in pick.iterrows()]
    with ThreadPoolExecutor(WORKERS) as ex:
        recs = list(ex.map(lambda r: process(r, ctx), rows))
    summarize(recs)


if __name__ == "__main__":
    main()