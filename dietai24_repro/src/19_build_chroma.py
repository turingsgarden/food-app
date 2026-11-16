from pathlib import Path

import chromadb
import numpy as np
import pandas as pd
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
MODEL = "text-embedding-3-large"
BATCH = 200
MAX_TOKENS = 1_000_000
DB_DIR = "outputs/chroma_db"

foods = pd.read_csv("outputs/kb/foods.csv")
foods["code"] = foods["Food code"].astype(int).astype(str)
foods["text"] = "Food code: " + foods["code"] + "\nFood description: " + foods["description"]
print("foods to index:", len(foods))
print("example document:\n" + foods["text"].iloc[1])

client = OpenAI()
db = chromadb.PersistentClient(path=DB_DIR)
col = db.get_or_create_collection(name="fndds", metadata={"hnsw:space": "cosine"}, embedding_function=None)
print("\ncollection metadata:", col.metadata, "| items already in it:", col.count())

done = set(col.get(include=[])["ids"])
todo = foods[~foods["code"].isin(done)]
print("still to embed:", len(todo))

total_tokens = 0
for start in range(0, len(todo), BATCH):
    chunk = todo.iloc[start:start + BATCH]
    r = client.embeddings.create(model=MODEL, input=chunk["text"].tolist())
    total_tokens += r.usage.total_tokens
    col.add(
        ids=chunk["code"].tolist(),
        embeddings=[d.embedding for d in sorted(r.data, key=lambda d: d.index)],
        documents=chunk["text"].tolist(),
        metadatas=[{"food_code": c, "main_description": str(m)}
                   for c, m in zip(chunk["code"], chunk["Main food description"])],
    )
    print(f"  batch {start // BATCH + 1}: +{len(chunk)} docs | tokens so far: {total_tokens}")
    if total_tokens > MAX_TOKENS:
        raise SystemExit("token safety limit reached, stopped")
print("embedding tokens used in this run:", total_tokens)

Path("logs").mkdir(exist_ok=True)
with open("logs/embedding_build.txt", "a") as f:
    f.write(f"model={MODEL} docs_added={len(todo)} tokens={total_tokens}\n")

print("\n[check 1] items in collection:", col.count(), "(expected 5624)")
sample = col.get(ids=foods["code"].iloc[:50].tolist(), include=["embeddings"])
emb = np.array(sample["embeddings"])
norms = np.linalg.norm(emb, axis=1)
print("[check 2] embedding dimension:", emb.shape[1], "| vector length min/max:",
      round(float(norms.min()), 4), round(float(norms.max()), 4))

tests = [
    ("Croissant", "51166000"),
    ("Mexican sweet bread (pan dulce)", "51161270"),
    ("Home-fried potatoes", "71403000"),
    ("Meat lasagna", "58130011"),
    ("Fruit yogurt", "11431000"),
    ("Plain chocolate candies (M&M's)", "91746100"),
    ("Deep-fried pork rinds", "22709010"),
    ("Mixed nuts with dried fruit", "42501000"),
]
print("\n[check 3] retrieval test with the paper's Fig. 3 examples (expected code -> rank in top 10)")
qs = client.embeddings.create(model=MODEL, input=[q for q, _ in tests])
for (q, code), item in zip(tests, sorted(qs.data, key=lambda d: d.index)):
    res = col.query(query_embeddings=[item.embedding], n_results=10)
    ids = res["ids"][0]
    rank = ids.index(code) + 1 if code in ids else None
    top1 = res["metadatas"][0][0]["main_description"]
    print(f"{q:34s} expected {code} -> rank {rank} | top1: {top1}")