"""DietAI24 reproduction on ASA24: full pipeline, two selectable prompt sets.

PROMPT_SET=paper  (default)  prompts exactly as printed in the paper's Supplementary Figs. 4-5, no system prompt.
PROMPT_SET=author            prompts from the authors' public code (github DietAI24): system prompt, brevity
                             instruction, "I can't help to analyze this image." escape clause, closest-match rule
                             (rag_food_code.py, rag_portion_size.py). Whitespace collapsed, typos kept.
Results are written to outputs/asa24_run_<PROMPT_SET>/ so the two sets never mix.

Deliberate deviations from the paper (decided with the user, to be listed in the report):
  * temperature 0 everywhere (authors: 0.01 / 0.1 / 0.3)
  * five rewritten queries (the paper's Fig. 4 says five); the authors' code adds the original as a sixth
  * the image itself is passed in the food-code step (authors' code passes only the image URL as text)
  * every image processed once, no answer-level retries, no chat history carried between images
  * portion options come from the FNDDS 2019-2020 portion table (authors: the ASA24 image portions)
  * gpt-4o-2024-11-20 instead of gpt-4-turbo; images resized to 256x256; top-k 4 per query (LangChain default)
"""
import base64
import io
import json
import os
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from fractions import Fraction

import chromadb
import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI
from PIL import Image

load_dotenv()
client = OpenAI(max_retries=6)   # retries only network / rate-limit errors, never re-asks the model

MODEL = "gpt-4o-2024-11-20"
EMB_MODEL = "text-embedding-3-large"
TOP_K = 4                        # per query; LangChain's default for as_retriever() (not verified by us)
PROMPT_SET = os.environ.get("PROMPT_SET", "paper")
assert PROMPT_SET in ("paper", "author"), "PROMPT_SET must be paper or author"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 1497
WORKERS = 8
IMG_DIR = "data/asa24/Asa24PortionImages"
OUT_DIR = f"outputs/asa24_run_{PROMPT_SET}"
os.makedirs(OUT_DIR, exist_ok=True)
NUT = {"energy_kcal": "Energy (kcal)", "fat_g": "Total Fat (g)",
       "carb_g": "Carbohydrate (g)", "protein_g": "Protein (g)"}
MEASURES = ["grams"] + list(NUT)
CANT = "I can't help to analyze this image."

if PROMPT_SET == "paper":
    # Supplementary Figures 4 and 5 of the paper, verbatim
    SYSTEM = None
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
    P_PORTION = ("Could you assess the portion size shown in the image and choose the option that most accurately "
                 "represents it from the following choices: {options}.")
    P_AMOUNT = ("Please evaluate the portion size presented and specify the quantity: how many {unit} of the "
                "{desc} are visible in the image? Please respond only with the numerical value.")
else:
    # the authors' public code
    SYSTEM = ("You are an expert at analyzing images with computer vision. I will present you with a picture of "
              "food, which might be placed on a plate, inside a spoon, or contained within different vessels. "
              "Your job is to accurately identify the food depicted in the image.")
    P_DESCRIBE = ("Could you name the food shown in the image? If feasible, specify its variety based on "
                  "ingredients and preparation methods. Ensure your response is brief and avoid speculating on "
                  "uncertain details. If you can't provide assistance with this image, simply respond with 'I "
                  "can't help to analyze this image.' and provide the reason on a new line.")
    P_REWRITE = ("You are an AI language model assistant. Your task is to generate five different versions of the "
                 "given food descriptions to retrieve relevant food information from a vector database. These "
                 "decriptions should docus purely on the qualitative asepcts of the food, including its broader "
                 "category, specific flavor profiles, ingredients, and methods of preparation. By generating "
                 "multiple perspectives on the food description, your goal is to help the user overcome some of "
                 "the limitations of the distance-based similarity search. Please provide these alternate food "
                 "descriptions. Ensure each of the five descriptions is separated by a newline. "
                 "Original food description: {desc}")
    P_CODE = ("Could you identify and provide the eight-digit food code corresponding to the given food image, "
              "considering only the context provided: {context}? Please provide only the eight-digit codes "
              "without any extra information. If an exact match for the food description is not available, "
              "please identify the closest equivalent. Should there be no relevant food codes based on the "
              "context provided, simply reply with 'No appropriate food codes found from the context "
              "information.'")
    P_PORTION = ("The image displays the food described as {desc}. Please assess the portion size shown in the "
                 "image and choose the option that most accurately represents it from the following choices: "
                 "{options}. Respond with only the selected portion size. If you cannot analyze the image, reply "
                 "with \"I can't help to analyze this image.\" and specify the reason on a new line.")
    P_AMOUNT = ("The image displays the food described as {desc}. Please evaluate the portion size presented and "
                "specify the quantity: how many {unit} of the food are visible in the image? Please respond only "
                "with the numerical value. If you cannot analyze the image, reply with \"I can't help to analyze "
                "this image.\" and specify the reason on a new line.")

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


def chat(content, system=False, max_tokens=None):
    msgs = [{"role": "system", "content": SYSTEM}] if (system and SYSTEM) else []
    msgs.append({"role": "user", "content": content})
    r = client.chat.completions.create(model=MODEL, temperature=0, messages=msgs, max_tokens=max_tokens)
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
    """Like LangChain MultiQueryRetriever: top-k per query, unique union in first-seen order."""
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


def match_option(text, options):
    r = norm(text)
    for o in options:
        if norm(o) == r:
            return o
    hits = [o for o in options if norm(o) in r]
    return max(hits, key=len) if hits else None


QTY = re.compile(r"^\s*(\d+(?:\.\d+)?(?:[ -]\d+/\d+)?|\d+/\d+)\s+(.*)$")


def split_qty(desc):
    m = QTY.match(str(desc))
    if not m:
        return None, str(desc)
    return float(sum(Fraction(t) for t in re.split(r"[ -]", m.group(1)))), m.group(2)


def singular(w):
    return w[:-1] if w.endswith("s") and not w.endswith("ss") else w


def label_unit(portion_text):
    _, rest = split_qty(portion_text)
    u = norm(rest).split(",")[0].strip()
    return singular(u) if u else None


def unit_weight(options, unit):
    for d, w in options.items():
        q, rest = split_qty(d)
        if q and q > 0 and singular(norm(rest).split(",")[0].strip()) == unit:
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
    p = p[~p["Portion description"].map(norm).eq("quantity not specified")]
    p = p[p["Portion weight (g)"] > 0].drop_duplicates("Portion description")
    return dict(zip(p["Portion description"], p["Portion weight (g)"].astype(float)))


def estimate(code, ctx, img, row, log, tag):
    name, por, nut = ctx["name"][code], ctx["por"], ctx["nut"]
    options = options_for(por, code)
    res = {"code": code, "shot": None, "amount": None}
    log.append(f"--- {tag}: {code} {name[:50]} | {len(options)} options")
    if options:
        ans = chat([{"type": "text", "text": P_PORTION.format(desc=name, options="; ".join(options))}, img],
                   system=True, max_tokens=600)
        opt = None if ans.startswith(CANT) else match_option(ans, list(options))
        res["shot"] = {"answer": ans, "matched": opt, "grams": float(options[opt]) if opt else None}
        log.append(f"  [shot]   {ans[:80]!r} -> {opt} -> {res['shot']['grams']} g")
    unit = label_unit(row["portion_text"])
    uw = unit_weight(options, unit) if unit else None
    if uw:
        ans = chat([{"type": "text", "text": P_AMOUNT.format(desc=name, unit=unit)}, img], system=True, max_tokens=600)
        amt = None if ans.startswith(CANT) else parse_number(ans)
        res["amount"] = {"unit": unit, "unit_g": uw, "answer": ans, "amount": amt,
                         "grams": amt * uw if amt is not None else None}
        log.append(f"  [amount] unit '{unit}' ({uw:.1f} g): {ans[:60]!r} -> {amt} -> {res['amount']['grams']} g")
    else:
        log.append(f"  [amount] skipped: unit {unit!r} not in this food's FNDDS portion options")
    for k in ("shot", "amount"):
        if res[k] and res[k]["grams"] is not None:
            g = res[k]["grams"]
            res[k]["nutrients"] = {n: float(nut.loc[code, c]) * g / 100 for n, c in NUT.items()}
    return res


def process(row, ctx):
    path = os.path.join(OUT_DIR, f"{row['image']}_{row['food_code']}.json")
    if os.path.exists(path):
        return json.load(open(path))
    log = ["=" * 70,
           f"{row['image']} | {row['size']} | label {row['portion_text']} | TRUE {row['food_code']} {row['description'][:50]}",
           f"TRUE grams {row['grams']:.1f} | kcal {row['energy_kcal']:.1f} | fat {row['fat_g']:.2f} | "
           f"carb {row['carb_g']:.2f} | protein {row['protein_g']:.2f}"]
    img = img_content(os.path.join(IMG_DIR, row["image"]))
    rec = {"image": row["image"], "true_code": row["food_code"], "size": row["size"],
           "truth": {m: float(row[m]) for m in MEASURES}, "failed": None, "B": None}

    desc = chat([{"type": "text", "text": P_DESCRIBE}, img], system=True, max_tokens=200)
    rec["desc"] = desc
    log.append("[1] description: " + desc.replace("\n", " ")[:300])
    if desc.startswith(CANT):
        rec.update(failed="vision refused", cand_hit=False, pred_code=None, code_ok=False, queries=[], cands=[])
        log.append("[1] vision refused -> no retrieval, no variant B")
    else:
        queries = [q.strip() for q in chat(P_REWRITE.format(desc=desc)).split("\n") if q.strip()]
        log.append(f"[2] {len(queries)} queries; first: {queries[0][:140] if queries else ''}")
        with chroma_lock:
            cands = retrieve(ctx["col"], queries)
        hit = row["food_code"] in cands
        log.append(f"[3] {len(cands)} candidates | true code in candidates: {hit}")
        context = "\n".join(f"Food code: {c}\nFood description: {ctx['text'][c]}" for c in cands if c in ctx["text"])
        ans = chat([{"type": "text", "text": P_CODE.format(context=context)}, img])
        code, status = parse_code(ans, set(cands))
        log.append(f"[4] code answer {ans[:60]!r} -> {code} ({status}) | correct: {code == row['food_code']}")
        rec.update(queries=queries, cands=cands, cand_hit=hit, code_answer=ans, pred_code=code,
                   code_ok=code == row["food_code"])
    rec["A"] = estimate(row["food_code"], ctx, img, row, log, "[5] A true food")
    code = rec["pred_code"]
    if code is not None and code in ctx["name"]:
        rec["B"] = rec["A"] if code == row["food_code"] else estimate(code, ctx, img, row, log, "[5] B predicted food")
    json.dump(rec, open(path, "w"), ensure_ascii=False, indent=1)
    with print_lock:
        print("\n".join(log), flush=True)
    return rec


def summarize(recs):
    print("\n" + "#" * 70)
    n = len(recs)
    print(f"SUMMARY over {n} images (prompt set: {PROMPT_SET}, model {MODEL})")
    print(f"vision refused / failed: {sum(1 for r in recs if r.get('failed'))}")
    for v, k in (("A", "shot"), ("A", "amount"), ("B", "shot"), ("B", "amount")):
        tot = sum(1 for r in recs if r.get(v) and r[v].get(k))
        bad = sum(1 for r in recs if r.get(v) and r[v].get(k) and r[v][k].get("grams") is None)
        print(f"  {v} {k}: {tot} calls, {bad} without a usable answer (refused / unparseable)")
    print(f"true code in candidates: {sum(r['cand_hit'] for r in recs)}/{n}")
    print(f"food code exactly right: {sum(r['code_ok'] for r in recs)}/{n}")
    print("\nper dish = mean |err|;  per unit = sum|err| / sum(truth)")
    print(f"{'variant/method':16s} {'n':>4s} " + " ".join(f"{m:>16s}" for m in MEASURES))
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
                print(f"{v + ' ' + k:16s} {0:4d}  (no data)")
                continue
            cells = [f"{sum(errs[m]) / cnt:7.2f}/{sum(errs[m]) / max(sum(tr[m]), 1e-9):6.3f}" for m in MEASURES]
            print(f"{v + ' ' + k:16s} {cnt:4d} " + " ".join(f"{c:>16s}" for c in cells))
    print("\ntokens -> chat in:", usage["in"], "| chat out:", usage["out"], "| embedding:", usage["emb"])


def main():
    gt = pd.read_csv("outputs/asa24_ground_truth.csv", dtype={"food_code": str})
    rows = [r for _, r in gt.sample(frac=1, random_state=1).head(N).iterrows()]   # fixed order: a pilot is a prefix of the full run
    foods = pd.read_csv("outputs/kb/foods.csv")
    foods["Food code"] = foods["Food code"].astype(int).astype(str)
    nut = pd.read_csv("outputs/kb/nutrients.csv")
    nut["Food code"] = nut["Food code"].astype(int).astype(str)
    por = pd.read_csv("outputs/kb/portions.csv")
    por["Food code"] = por["Food code"].astype(int).astype(str)
    ctx = {"text": dict(zip(foods["Food code"], foods["description"])),       # text that was embedded in the DB
           "name": dict(zip(foods["Food code"], foods["Main food description"])),  # FNDDS name (authors' FC_Description)
           "nut": nut.set_index("Food code"), "por": por,
           "col": chromadb.PersistentClient(path="outputs/chroma_db").get_collection("fndds")}
    with ThreadPoolExecutor(WORKERS) as ex:
        recs = list(ex.map(lambda r: process(r, ctx), rows))
    summarize(recs)


if __name__ == "__main__":
    main()