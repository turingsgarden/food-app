import os
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
key = os.getenv("OPENAI_API_KEY")
if not key:
    raise SystemExit("OPENAI_API_KEY not found: check that .env is in the project folder and the line is OPENAI_API_KEY=...")

print("key found | length:", len(key), "| starts with sk-:", key.startswith("sk-"),
      "| has spaces:", key != key.strip() or " " in key,
      "| has quotes:", '"' in key or "'" in key)

client = OpenAI()
r = client.embeddings.create(model="text-embedding-3-large", input=["croissant"])
print("embedding dim:", len(r.data[0].embedding))
print("tokens used:", r.usage.total_tokens)
