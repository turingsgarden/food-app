"""Runs the authors' public DietAI24 retrieval code (code/rag_food_code.py) on our ASA24 images.
The logic of the authors' file is kept: CSVLoader + Chroma.from_documents, the authors' retrieval prompt (five
versions + the original description as sixth entry), MultiQueryRetriever with vectordb.as_retriever() (default k=4),
their image prompt and code prompt, temperatures 0.1 (vision) / 0.3, max_tokens 200 for vision, up to 5 passes that
retry the failed images, results as str(list of lines) in GPTFoodCode.
Changes (to be listed in the report):
  1. AzureChatOpenAI / AzureOpenAIEmbeddings -> ChatOpenAI / OpenAIEmbeddings with our key; both models =
     gpt-4o-2024-11-20 (authors: gpt-4-turbo and a vision deployment 'gptv')
  2. images are local files, sent as 256x256 PNG data URLs; in the code step the authors pass the image URL only as
     text ({url_str}), here the file name takes that place (the model does not see the image in that step, as in the code)
  3. no requests.head() URL check
  4. the chain routes the two input fields explicitly (the published chain passes the whole input dict to the
     retriever and does not supply {url_str} to the prompt)
  5. a tap records the retrieved candidates (no change in behaviour); the vector DB is built from our FNDDS csv
     outputs/kb/foods.csv instead of the authors' own csv
Usage (from the project root): python src/50_author_code_asa24.py N      (first N images of a fixed shuffled order; resumable)
"""
import logging
import os
import re
import sys
import time
import warnings
import base64
import io
from operator import itemgetter

import numpy as np
import pandas as pd
from dotenv import load_dotenv
from PIL import Image
from langchain_community.document_loaders import CSVLoader
from langchain_core.prompts import PromptTemplate, ChatPromptTemplate
from langchain_core.runnables import RunnablePassthrough, RunnableLambda
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_community.vectorstores import Chroma
from langchain.retrievers.multi_query import MultiQueryRetriever
from langchain_core.output_parsers import StrOutputParser

load_dotenv()
warnings.filterwarnings("ignore")
MODEL = "gpt-4o-2024-11-20"
EMB_MODEL = "text-embedding-3-large"
IMG_DIR = "data/asa24/Asa24PortionImages"
OUT_DIR = "outputs/asa24_run_author_code"
RESULTS = os.path.join(OUT_DIR, "results.csv")
CHECKPOINT = os.path.join(OUT_DIR, "checkpoint.txt")
LOG = os.path.join(OUT_DIR, "process_images.log")
N = int(sys.argv[1]) if len(sys.argv) > 1 else 20
LAST = {"docs": []}
os.makedirs(OUT_DIR, exist_ok=True)


def setup_logging(log_path):
    logging.basicConfig(filename=log_path, level=logging.INFO, format="%(asctime)s:%(levelname)s:%(message)s")
    logging.getLogger("langchain.retrievers.multi_query").setLevel(logging.INFO)


def initialize_clients():
    llm = ChatOpenAI(model=MODEL, temperature=0.3)
    llm_vision = ChatOpenAI(model=MODEL, temperature=0.1, max_tokens=200)
    embedding = OpenAIEmbeddings(model=EMB_MODEL)
    return llm, llm_vision, embedding


def load_data(file_path):
    return CSVLoader(file_path=file_path).load()


def setup_vector_database(data, embedding):
    return Chroma.from_documents(documents=data, embedding=embedding, collection_name="openai_embed")


def data_url(path):
    im = Image.open(path).convert("RGB").resize((256, 256))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def get_messages(image_path):
    return [
        SystemMessage(
            content="You are an expert at analyzing images with computer vision. "
                    "I will present you with a picture of food, which might be placed on a plate, inside a spoon, "
                    "or contained within different vessels. Your job is to accurately identify the food depicted in the image."
        ),
        HumanMessage(
            content=[
                {"type": "text", "text": """Could you name the food shown in the image? If feasible, specify its variety
                 based on ingredients and preparation methods. Ensure your response is brief and avoid
                 speculating on uncertain details. If you can't provide assistance with this image, simply respond 
                 with 'I can't help to analyze this image.' and provide the reason on a new line."""},
                {"type": "image_url", "image_url": {"url": data_url(image_path)}},
            ]
        ),
    ]


def setup_retrieval_prompt():
    return PromptTemplate(
        input_variables=["question"],
        template="""You are an AI language model assistant. Your task is to generate five 
        different versions of the given food descriptions to retrieve relevant food information from a vector 
        database. These decriptions should docus purely on the qualitative asepcts of the food, including its broader category, specific flavor profiles, ingredients, and methods of preparation. 
        By generating multiple perspectives on the food description, your goal is to help
        the user overcome some of the limitations of the distance-based similarity search. 
        Please provide these alternate food descriptions, adding the original description as the sixth entry without mentioning that it is the original description. 
        Ensure each of the six descriptions is separated by a newline.
        Original food description: {question}""",
    )


def configure_retrievers(llm, vectordb, prompt):
    return MultiQueryRetriever.from_llm(retriever=vectordb.as_retriever(), llm=llm, prompt=prompt)


def tap(docs):
    LAST["docs"] = [d.page_content for d in docs]
    return docs


def setup_code_prompt_chain(retriever_from_llm, llm):
    template = """Could you identify and provide the eight-digit food code corresponding to the given food image: {url_str}, 
    considering only the context provided: {context}?

    Please provide only the eight-digit codes without any extra information. If an exact match for the food description is not available, please identify the closest equivalent. 
    Should there be no relevant food codes based on the context provided, simply reply with 'No appropriate food codes found from the context information.
    """
    CODE_PROMPT = ChatPromptTemplate.from_template(template)
    return (
        {"context": itemgetter("question") | retriever_from_llm | RunnableLambda(tap),
         "url_str": itemgetter("url_str")}
        | CODE_PROMPT
        | llm
        | StrOutputParser()
    )


def is_integer(s):
    try:
        int(s)
        return True
    except ValueError:
        return False


def process_image(index, image, llm_vision, df, food_code_chain, results_path):
    logging.info(f"Processing index {index}: {image}")
    try:
        IMAGE_PROMPT = get_messages(os.path.join(IMG_DIR, image))
        attempts = 0
        max_attempts = 5
        while True:
            try:
                image_response = llm_vision.invoke(IMAGE_PROMPT)
                food_description = image_response.content
                splits = food_description.split("\n")
                if splits[0] == "I can't help to analyze this image.":
                    raise Exception(splits[-1])
                break
            except Exception as e:
                if "429" in str(e) or "rate limit" in str(e).lower():
                    if attempts < max_attempts - 1:
                        time.sleep(2 ** attempts * 30)
                        attempts += 1
                        continue
                    raise
                raise
        LAST["docs"] = []
        food_code_response = food_code_chain.invoke({"question": food_description, "url_str": image})
        codes = []
        for d in LAST["docs"]:
            m = re.search(r"Food code:\s*(\d+)", d)
            if m and m.group(1) not in codes:
                codes.append(m.group(1))
        df.loc[index, "retrieved"] = " ".join(codes)
        if food_code_response == "No appropriate food codes found from the context information.":
            raise Exception(food_code_response)
        df.loc[index, "GPTFoodDescription"] = food_description
        df.loc[index, "GPTFoodCode"] = str(food_code_response.split("\n"))
    except Exception as e:
        df.loc[index, "GPTFoodDescription"] = str(e)
        df.loc[index, "GPTFoodCode"] = np.nan
    finally:
        df.to_csv(results_path, index=False)


def load_checkpoint(path):
    if os.path.exists(path):
        content = open(path).read()
        if content:
            num, index = content.split(",")
            return int(num), int(index)
    return 0, 0


def save_checkpoint(num, index, path):
    open(path, "w").write(f"{num},{index}")


def show(df, i):
    r = df.loc[i]
    code = r["GPTFoodCode"]
    pred = code[2:10] if isinstance(code, str) else None
    retrieved = str(r["retrieved"]).split() if isinstance(r["retrieved"], str) else []
    print(f"[{i + 1}/{N}] {r['image']} | {r['size']} | true {r['true_code']} | pred {pred} | "
          f"in candidates: {r['true_code'] in retrieved} ({len(retrieved)}) | exact: {pred == r['true_code']}", flush=True)
    print("     desc:", str(r["GPTFoodDescription"]).replace("\n", " ")[:140], flush=True)


def process_images(results_path, checkpoint_path, llm_vision, food_code_chain):
    num_iterations = 5
    df = pd.read_csv(results_path, dtype=str)
    last_num, last_index = load_checkpoint(checkpoint_path)
    total = min(N, len(df))
    for num in range(last_num, num_iterations):
        start = last_index if num == last_num else 0
        for i in range(start, total):
            code = df.loc[i, "GPTFoodCode"]
            if not pd.isna(code) and is_integer(code[2:10]):
                continue
            process_image(i, df.loc[i, "Link"], llm_vision, df, food_code_chain, results_path)
            save_checkpoint(num, i + 1, checkpoint_path)
            if num == 0:
                show(df, i)
        last_index = 0
    return df


def summary(df):
    d = df.head(N)
    ok = d[d["GPTFoodCode"].notna()]
    pred = ok["GPTFoodCode"].map(lambda c: c[2:10])
    inc = [(t in str(r).split()) for t, r in zip(d["true_code"], d["retrieved"])]
    print("\n" + "#" * 60)
    print(f"images {len(d)} | got a code {len(ok)} ({100 * len(ok) / len(d):.1f}%) | exact {100 * (pred == ok['true_code']).mean():.1f}% of coded "
          f"| true code in candidates {100 * np.mean(inc):.1f}%")


def main():
    setup_logging(LOG)
    llm, llm_vision, embedding = initialize_clients()
    if not os.path.exists(RESULTS):
        base = pd.read_csv("outputs/asa24_per_image_results.csv", dtype={"true_code": str})[["image", "size", "true_code"]]
        base = base.sample(frac=1, random_state=1).reset_index(drop=True)
        base["Link"] = base["image"]
        for c in ("GPTFoodDescription", "GPTFoodCode", "retrieved"):
            base[c] = np.nan
        base.to_csv(RESULTS, index=False)
    data = load_data("outputs/kb/foods.csv")
    vectordb = setup_vector_database(data, embedding)
    retriever = configure_retrievers(llm, vectordb, setup_retrieval_prompt())
    chain = setup_code_prompt_chain(retriever, llm)
    df = process_images(RESULTS, CHECKPOINT, llm_vision, chain)
    summary(df)


if __name__ == "__main__":
    main()