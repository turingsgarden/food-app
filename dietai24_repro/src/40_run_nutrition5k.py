"""DietAI24 reproduction on Nutrition5k (mixed dishes), supplement prompts, variant B only (no food-code truth exists).

Per dish:
  1. describe the dish with the paper's prompt (verbatim)
  2. split the description into the separate food items that are visible, one per line   (our adaptation)
  3. for EACH item: five rewritten queries -> Chroma top-k per query -> unique union -> food code from the candidates
  4. ONE call per dish: estimate the weight in grams of every item ("name: grams" per line, the format the authors'
     nutrient_estimate_mix.py parses)
  5. item nutrients = per-100 g nutrients of the chosen code x grams / 100; dish = sum over items; compare with the dish totals.

Deliberate deviations (to be listed in the report), besides those of 30_run_asa24.py:
  * the authors' mixed-dish prompts are not in their public repo, so step 2, the per-item wording and the joint weight prompt are ours
  * item focus is added to the code prompt ("We are looking at one food item in the image: X.")
  * the authors average the nutrients of several codes per item; we use one code per item
  * weights are asked directly in grams (as the authors' mixed-dish code reads them), not chosen from FNDDS portion options
Usage: python src/40_run_nutrition5k.py N     (resumable; one JSON per dish in outputs/nutrition5k_run/)
"""
import base64
import io
import json
import os
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

import chromadb
import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI
from PIL import Image

load_dotenv()
client = OpenAI(max_retries=6)

MODEL = "gpt-4o-2024-11-20"
EMB_MODEL = "text-embedding-3-large"
TOP_K = 4
MAX_ITEMS = 10
N = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
WORKERS = 8
IMG_DIR = "data/nutrition5k/images"
OUT_DIR = "outputs/nutrition5k_run"
os.makedirs(OUT_DIR, exist_ok=True)
NUT = {"energy_kcal": "Energy (kcal)", "fat_g": "Total Fat (g)",
       "carb_g": "Carbohydrate (g)", "protein_g": "Protein (g)"}
MEASURES = ["grams"] + list(NUT)
TRUTH_COL = {"grams": "total_mass", "energy_kcal": "total_calories", "fat_g": "total_fat",
             "carb_g": "total_carbs", "protein_g": "total_protein"}
CANT = "I can't help to analyze this image."
# paper Table 2, DietAI24 (per dish, per unit)
PAPER = {"energy_kcal": (68.2, 0.197), "fat_g": (4.01, 0.226), "carb_g": (5.98, 0.212),
         "protein_g": (3.88, 0.188), "grams": (45.1, 0.156)}

# Supplementary Figures 4 and 5 of the paper, verbatim
P_DESCRIBE = ("Could you name the food shown in the image? If feasible, specify its variety based on "
              "ingredients and preparation methods.")
P_REWRITE = ("Your task is to generate five different versions of the given food descriptions to retrieve "
             "relevant food information from a vector database. These descriptions should focus purely on the "
             "qualitative aspects of the food, including its broader category, specific flavor profiles, "
             "ingredients, and methods of preparation. By generating multiple perspectives on the food "
             "description, your goal is to help the user overcome some of the limitations of the "
             "distance-based similarity search. Original food description: {desc}")
P_CODE = ("Could you identify and provide the eight-digit food code corresponding to the food shown in the "
          "image, considering only the context provided: {context}")
# our adaptations for mixed dishes
P_SPLIT = ("Below is a description of a dish. List only the food items that are actually visible in the dish, one "
           "item per line, as short food names with the preparation method (for example: grilled chicken breast). "
           "Merge alternatives and guesses into the single most likely item, ignore anything described as possible, "
           "optional or something that could be added, and ignore seasonings and sauces that are not clearly "
           "visible. Do not add numbering, bullets or any other text. Description: {desc}")
P_FOCUS = "We are looking at one food item in the image: {item}. "
P_WEIGHTS = ("The dish in the image contains the following food items: {items}. Please estimate the weight in grams "
             "of each of these items as shown in the image. Respond with one line per item in the format "
             "'item name: grams', using only a number for the grams.")

usage = {"in": 0, "out": 0, "emb": 0}
lock = threading.Lock()
chroma_lock = threading.Lock()
print_lock = threading.Lock()


def img_content(path):
    im = Image.open(path).convert("RGB").resize((256, 256))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode()
    return {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}


def chat(content, max_tokens=None):
    r = client.chat.completions.create(model=MODEL, temperature=0, max_tokens=max_tokens,
                                       messages=[{"role": "user", "content": content}])
    with lock:
        usage["in"] += r.usage.prompt_tokens
        usage["out"] += r.usage.completion_tokens
    return (r.choices[0].message.content or "").strip()


def embed(texts):
    r = client.embeddings.create(model=EMB_MODEL, input=texts)
    with lock:
        usage["emb"] += r.usage.total_tokens
    return [d.embedding for d in sorted(r.data, key=lambda d: d.index)]


def norm(s):
    return " ".join(str(s).lower().split())


def retrieve(col, queries):
    embs = embed(queries)
    res = col.query(query_embeddings=embs, n_results=TOP_K)
    seen, out = set(), []
    for ids in res["ids"]:
        for c in ids:
            if c not in seen:
                seen.add(c)
                out.append(c)
    return out


def parse_code(text, allowed):
    found = re.findall(r"\d{8}", text)
    if not found:
        return None, "no 8-digit code"
    return found[0], ("in candidates" if found[0] in allowed else "NOT in candidates")


def parse_number(text):
    m = re.search(r"(\d+)\s+(\d+)/(\d+)", text)
    if m:
        return int(m.group(1)) + int(m.group(2)) / int(m.group(3))
    m = re.search(r"(\d+)\s*/\s*(\d+)", text)
    if m:
        return int(m.group(1)) / int(m.group(2))
    m = re.search(r"\d+(?:\.\d+)?", text)
    return float(m.group(0)) if m else None


def parse_items(text):
    items, seen = [], set()
    for line in text.split("\n"):
        s = re.sub(r"^[\s\-\*•\d\.\)]+", "", line).replace("**", "").strip()
        if not s or s.endswith(":") or norm(s) in seen:
            continue
        seen.add(norm(s))
        items.append(s)
    return items[:MAX_ITEMS]


def do_item(item, ctx, img, log):
    rec = {"item": item, "queries": [], "cands": [], "pred_code": None, "grams": None}
    queries = [q.strip() for q in chat(P_REWRITE.format(desc=item)).split("\n") if q.strip()]
    with chroma_lock:
        cands = retrieve(ctx["col"], queries)
    context = "\n".join(f"Food code: {c}\nFood description: {ctx['text'][c]}" for c in cands if c in ctx["text"])
    ans = chat([{"type": "text", "text": P_FOCUS.format(item=item) + P_CODE.format(context=context)}, img])
    code, status = parse_code(ans, set(cands))
    rec.update(queries=queries, cands=cands, code_answer=ans, pred_code=code)
    if code is not None and code in ctx["name"]:
        rec["name"] = ctx["name"][code]
    else:
        rec["pred_code"] = None
    log.append(f"  item: {item[:60]} | {len(queries)} queries, {len(cands)} cands | code {rec['pred_code']} "
               f"({status}) {rec.get('name', '')[:40]}")
    return rec


def parse_weights(text, items):
    """Map 'name: grams' lines back to the items (by name first, then by position)."""
    lines = []
    for line in text.split("\n"):
        line = line.replace("**", "").strip().lstrip("-*\u2022 ").strip()
        if ":" not in line:
            continue
        name, val = line.rsplit(":", 1)
        lines.append((norm(re.sub(r"^\d+[\.\)]\s*", "", name)), None if "none" in val.lower() else parse_number(val)))
    out = []
    for i, it in enumerate(items):
        n = norm(it)
        g = next((v for k, v in lines if k == n), None)
        if g is None:
            g = next((v for k, v in lines if k and (k in n or n in k)), None)
        if g is None and len(lines) == len(items):
            g = lines[i][1]
        out.append(g)
    return out


def dish_sum(items, k):
    used = [it for it in items if it.get(k) and it[k].get("grams") is not None and it[k].get("nutrients")]
    if not used:
        return None
    tot = {"grams": sum(it[k]["grams"] for it in used)}
    for n in NUT:
        tot[n] = sum(it[k]["nutrients"][n] for it in used)
    return {"n_items_used": len(used), "pred": tot}


def process(row, ctx):
    path = os.path.join(OUT_DIR, f"{row['dish_id']}.json")
    if os.path.exists(path):
        return json.load(open(path))
    truth = {m: float(row[TRUTH_COL[m]]) for m in MEASURES}
    log = ["=" * 70, f"{row['dish_id']} | TRUE ingredients: {row['sorted_ingredients']}",
           "TRUE " + " | ".join(f"{m} {truth[m]:.1f}" for m in MEASURES)]
    img = img_content(os.path.join(IMG_DIR, row["dish_id"] + ".png"))
    rec = {"dish_id": row["dish_id"], "true_ingredients": row["sorted_ingredients"], "truth": truth,
           "failed": None, "items": [], "grams": None}
    desc = chat([{"type": "text", "text": P_DESCRIBE}, img], max_tokens=400)
    rec["desc"] = desc
    log.append("[1] description: " + desc.replace("\n", " ")[:300])
    if desc.startswith(CANT):
        rec["failed"] = "vision refused"
    else:
        items = parse_items(chat(P_SPLIT.format(desc=desc), max_tokens=300))
        log.append(f"[2] {len(items)} items: " + " | ".join(i[:40] for i in items))
        for it in items:
            rec["items"].append(do_item(it, ctx, img, log))
        coded = [it for it in rec["items"] if it["pred_code"]]
        if coded:
            ans = chat([{"type": "text", "text": P_WEIGHTS.format(items=", ".join(it["item"] for it in coded))}, img],
                       max_tokens=600)
            rec["weights_answer"] = ans
            for it, g in zip(coded, parse_weights(ans, [it["item"] for it in coded])):
                it["grams"] = {"grams": g}
                if g is not None:
                    it["grams"]["nutrients"] = {n: float(ctx["nut"].loc[it["pred_code"], c]) * g / 100
                                                for n, c in NUT.items()}
            log.append("[4] weights: " + " | ".join(f"{it['item'][:25]} {it['grams']['grams']} g" for it in coded))
        rec["grams"] = dish_sum(rec["items"], "grams")
        if rec["grams"]:
            log.append("[5] dish: " + " | ".join(f"{m} {rec['grams']['pred'][m]:.1f}" for m in MEASURES))
    json.dump(rec, open(path, "w"), ensure_ascii=False, indent=1)
    with print_lock:
        print("\n".join(log), flush=True)
    return rec


def summarize(recs):
    print("\n" + "#" * 70)
    print(f"SUMMARY over {len(recs)} dishes (model {MODEL})")
    print(f"vision refused / no items: {sum(1 for r in recs if r.get('failed') or not r['items'])}")
    ni = [len(r["items"]) for r in recs]
    print(f"items per dish: mean {sum(ni) / max(len(ni), 1):.2f}, max {max(ni, default=0)}")
    print(f"items with a food code: {sum(1 for r in recs for i in r['items'] if i['pred_code'])}/{sum(ni)}")
    print("\nper dish = mean |err|;  per unit = sum|err| / sum(truth)")
    print(f"{'method':8s} {'n':>5s}  " + " ".join(f"{m:>16s}" for m in MEASURES))
    print(f"{'paper':8s} {1000:5d}  " + " ".join(f"{PAPER[m][0]:7.2f}/{PAPER[m][1]:6.3f}" for m in MEASURES))
    for k in ("grams",):
        errs = {m: [] for m in MEASURES}
        tr = {m: [] for m in MEASURES}
        for r in recs:
            if not r.get(k):
                continue
            for m in MEASURES:
                errs[m].append(abs(r[k]["pred"][m] - r["truth"][m]))
                tr[m].append(r["truth"][m])
        n = len(errs["grams"])
        if n == 0:
            print(f"{k:8s} {0:5d}  (no data)")
            continue
        cells = [f"{sum(errs[m]) / n:7.2f}/{sum(errs[m]) / max(sum(tr[m]), 1e-9):6.3f}" for m in MEASURES]
        print(f"{k:8s} {n:5d}  " + " ".join(f"{c:>16s}" for c in cells))
    print("\ntokens -> chat in:", usage["in"], "| chat out:", usage["out"], "| embedding:", usage["emb"])


def main():
    df = pd.read_csv("outputs/nutrition5k_sample.csv")
    rows = [r for _, r in df.sample(frac=1, random_state=1).head(N).iterrows()]   # fixed order: a pilot is a prefix of the full run
    foods = pd.read_csv("outputs/kb/foods.csv")
    foods["Food code"] = foods["Food code"].astype(int).astype(str)
    nut = pd.read_csv("outputs/kb/nutrients.csv")
    nut["Food code"] = nut["Food code"].astype(int).astype(str)
    por = pd.read_csv("outputs/kb/portions.csv")
    por["Food code"] = por["Food code"].astype(int).astype(str)
    ctx = {"text": dict(zip(foods["Food code"], foods["description"])),
           "name": dict(zip(foods["Food code"], foods["Main food description"])),
           "nut": nut.set_index("Food code"), "por": por,
           "col": chromadb.PersistentClient(path="outputs/chroma_db").get_collection("fndds")}
    with ThreadPoolExecutor(WORKERS) as ex:
        recs = list(ex.map(lambda r: process(r, ctx), rows))
    summarize(recs)


if __name__ == "__main__":
    main()