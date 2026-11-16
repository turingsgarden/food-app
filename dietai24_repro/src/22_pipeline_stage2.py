import importlib.util
import os
import re

import chromadb
import pandas as pd

# 复用第一阶段脚本里的函数（看图、聊天、embedding、提示词、用量统计）
spec = importlib.util.spec_from_file_location("stage1", "src/21_pipeline_stage1.py")
s1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s1)

NUT_COLS = {"energy_kcal": "Energy (kcal)", "fat_g": "Total Fat (g)",
            "carb_g": "Carbohydrate (g)", "protein_g": "Protein (g)"}

P_CODE = ("The image shows a food that can be described as: {desc}\n"
          "Please identify and provide the eight-digit food code that best matches the food "
          "in the image, considering only the context provided: {context}\n"
          "Respond with only the eight-digit food code.")

P_PORTION = ("The image displays the food described as {desc}. Please assess the portion size shown "
             "in the image and choose the option that most accurately represents it from the "
             "following choices: {options}. Respond with only the selected portion size.")


def norm(s):
    return " ".join(str(s).lower().split())


def retrieve(col, queries):
    embs = s1.embed(queries)
    res = col.query(query_embeddings=embs, n_results=s1.TOP_K, include=["distances"])
    best = {}
    for ids, dists in zip(res["ids"], res["distances"]):
        for code, d in zip(ids, dists):
            if code not in best or d < best[code]:
                best[code] = d
    return sorted(best, key=best.get)


def parse_code(text, allowed):
    found = re.findall(r"\d{8}", text)
    if not found:
        return None, "no 8-digit code in the answer"
    if found[0] in allowed:
        return found[0], "ok (in candidates)"
    return found[0], "code is NOT among the candidates"


def match_option(text, options):
    r = norm(text)
    for o in options:
        if norm(o) == r:
            return o
    hits = [o for o in options if norm(o) in r]
    return max(hits, key=len) if hits else None


def run_portion(label, code, fdesc, por, nut, b64, row):
    print(f"\n--- {label}: food code {code} ---")
    p = por[(por["Food code"] == code) & (por["Portion weight (g)"] > 0)]
    p = p.drop_duplicates("Portion description")
    options = dict(zip(p["Portion description"], p["Portion weight (g)"]))
    print(f"FNDDS portion options ({len(options)}, zero-gram options removed):")
    for k, v in options.items():
        print(f"    {k}  ->  {v} g")
    if not options:
        print("  no usable portion option, skip")
        return
    ans = s1.chat([{"type": "text", "text": P_PORTION.format(desc=fdesc[code], options="; ".join(options))},
                   {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}])
    print("model answer:", ans)
    opt = match_option(ans, list(options))
    if opt is None:
        print("could not match the answer to any option -> UNPARSED")
        return
    grams = float(options[opt])
    print(f"matched option: {opt}  ->  {grams} g")
    print(f"{'':10s} {'pred':>9s} {'truth':>9s} {'abs err':>9s}")
    print(f"{'grams':10s} {grams:9.2f} {row['grams']:9.2f} {abs(grams - row['grams']):9.2f}")
    for key, colname in NUT_COLS.items():
        pred = float(nut.loc[code, colname]) * grams / 100
        print(f"{key:10s} {pred:9.2f} {row[key]:9.2f} {abs(pred - row[key]):9.2f}")


def main():
    gt = pd.read_csv("outputs/asa24_ground_truth.csv", dtype={"food_code": str})
    pick = gt.drop_duplicates("food_code").sample(s1.N_IMAGES, random_state=0)

    foods = pd.read_csv("outputs/kb/foods.csv")
    foods["Food code"] = foods["Food code"].astype(int).astype(str)
    fdesc = dict(zip(foods["Food code"], foods["description"]))
    nut = pd.read_csv("outputs/kb/nutrients.csv")
    nut["Food code"] = nut["Food code"].astype(int).astype(str)
    nut = nut.set_index("Food code")
    por = pd.read_csv("outputs/kb/portions.csv")
    por["Food code"] = por["Food code"].astype(int).astype(str)
    col = chromadb.PersistentClient(path="outputs/chroma_db").get_collection("fndds")

    for _, row in pick.iterrows():
        print("\n" + "=" * 70)
        print(f"image: {row['image']} | size: {row['size']} | label portion: {row['portion_text']}")
        print(f"TRUE food code: {row['food_code']} | {row['description']}")
        print(f"TRUE grams: {row['grams']:.1f} | energy {row['energy_kcal']:.1f} kcal | "
              f"fat {row['fat_g']:.2f} | carb {row['carb_g']:.2f} | protein {row['protein_g']:.2f}")

        b64 = s1.img_b64(os.path.join(s1.IMG_DIR, row["image"]))
        desc = s1.chat([{"type": "text", "text": s1.P_DESCRIBE},
                        {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}])
        print("\n[step 1] vision description:\n" + desc)

        rewrites = s1.chat(s1.P_REWRITE.format(desc=desc))
        queries = [q.strip() for q in rewrites.split("\n") if q.strip()][:5]
        print(f"\n[step 2] {len(queries)} rewritten queries (omitted here, same as stage 1 format)")

        cands = retrieve(col, queries)
        print(f"\n[step 3] merged candidates ({len(cands)}), nearest first:")
        for c in cands:
            print(f"    {c}  {fdesc.get(c, '?')[:90]}")
        print("  TRUE CODE IN CANDIDATES:", row["food_code"] in cands)

        context = "\n".join(f"Food code: {c}\nFood description: {fdesc[c]}" for c in cands if c in fdesc)
        ans = s1.chat([{"type": "text", "text": P_CODE.format(desc=desc, context=context)},
                       {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}])
        code, status = parse_code(ans, set(cands))
        print(f"\n[step 4] food-code answer: {ans!r} -> parsed {code} ({status})")
        print("  matches true code:", code == row["food_code"])

        # 变体 A：真实食物 + 模型选份量；变体 B：模型选的食物 + 模型选份量（论文的端到端流程）
        run_portion("[step 5] variant A (true food + predicted portion)",
                    row["food_code"], fdesc, por, nut, b64, row)
        if code is not None and code in fdesc and code != row["food_code"]:
            run_portion("[step 5] variant B (predicted food + predicted portion)",
                        code, fdesc, por, nut, b64, row)
        elif code == row["food_code"]:
            print("\n--- variant B is identical to variant A here (code is correct) ---")
        else:
            print("\n--- variant B skipped: no valid predicted code ---")

    print("\n" + "=" * 70)
    print("tokens used -> chat in:", s1.usage["in"], "| chat out:", s1.usage["out"],
          "| embedding:", s1.usage["emb"])


if __name__ == "__main__":
    main()