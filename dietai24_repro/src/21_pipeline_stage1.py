import base64
import io
import os

import chromadb
import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI
from PIL import Image

load_dotenv()
client = OpenAI()

MODEL = "gpt-4o-2024-11-20"
EMB_MODEL = "text-embedding-3-large"
N_IMAGES = 3
TOP_K = 5          # 每个查询取前 5 个候选（论文没写 top-k，这是我们暂定的）
IMG_DIR = "data/asa24/Asa24PortionImages"
usage = {"in": 0, "out": 0, "emb": 0}

P_DESCRIBE = ("Could you name the food shown in the image? If feasible, specify its "
              "variety based on ingredients and preparation methods.")
P_REWRITE = ("Generate five different versions of the following food description, focusing on "
             "qualitative aspects such as category, flavor, ingredients and preparation. "
             "Return one version per line, without numbering or extra text.\n\n"
             "Food description: {desc}")


def img_b64(path):
    im = Image.open(path).convert("RGB").resize((256, 256))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def chat(content):
    r = client.chat.completions.create(
        model=MODEL, temperature=0,
        messages=[{"role": "user", "content": content}])
    usage["in"] += r.usage.prompt_tokens
    usage["out"] += r.usage.completion_tokens
    return r.choices[0].message.content.strip()


def embed(texts):
    r = client.embeddings.create(model=EMB_MODEL, input=texts)
    usage["emb"] += r.usage.total_tokens
    return [d.embedding for d in r.data]


def main():
    gt = pd.read_csv("outputs/asa24_ground_truth.csv", dtype={"food_code": str})
    pick = gt.drop_duplicates("food_code").sample(N_IMAGES, random_state=0)
    col = chromadb.PersistentClient(path="outputs/chroma_db").get_collection("fndds")

    for _, row in pick.iterrows():
        print("\n" + "=" * 70)
        print("image:", row["image"], "| true food code:", row["food_code"], "|", row["description"])

        b64 = img_b64(os.path.join(IMG_DIR, row["image"]))
        desc = chat([{"type": "text", "text": P_DESCRIBE},
                     {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}])
        print("\n[step 1] vision description:\n" + desc)

        rewrites = chat(P_REWRITE.format(desc=desc))
        queries = [q.strip() for q in rewrites.split("\n") if q.strip()][:5]
        print(f"\n[step 2] {len(queries)} rewritten queries:")
        for i, q in enumerate(queries, 1):
            print(f"  {i}. {q}")

        embs = embed(queries)
        res = col.query(query_embeddings=embs, n_results=TOP_K,
                        include=["metadatas", "distances"])
        print(f"\n[step 3] Chroma retrieval (top {TOP_K} per query, cosine distance):")
        best = {}
        for qi in range(len(queries)):
            print(f"  query {qi + 1}:")
            for code, meta, dist in zip(res["ids"][qi], res["metadatas"][qi], res["distances"][qi]):
                print(f"    {dist:.3f}  {code}  {meta['main_description']}")
                if code not in best or dist < best[code][0]:
                    best[code] = (dist, meta["main_description"])
        print(f"  unique candidates after merging: {len(best)}")
        hit = row["food_code"] in best
        print("  TRUE CODE IN CANDIDATES:", hit)

    print("\n" + "=" * 70)
    print("tokens used -> chat in:", usage["in"], "| chat out:", usage["out"], "| embedding:", usage["emb"])


if __name__ == "__main__":
    main()