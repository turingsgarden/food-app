# build_images_csv.py
import os
import csv
import uuid
import time
import pandas as pd
from pathlib import Path
import argparse

from analysis import (
    analyze_image_gemini_1,
    analyze_image_gemini_2,
    analyze_image_gemini_3,
    analyze_image_gemini_4,
)

# MODIFY: set this to your dataset root (or pass via CLI if you prefer)
DATASET_ROOT = "/home/sheru/datasets/uecfood256-small-random"


OUT_INDEX = "images_index.csv"
OUT_RESULTS = "analysis_results.csv"

def find_image_files(root):
    exts = (".png", ".jpg", ".jpeg")
    out = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith(exts):
                full = os.path.join(dirpath, fn)
                out.append(full)
    return sorted(out)

def build_index(dataset_root=None):
    root = dataset_root or DATASET_ROOT
    images = find_image_files(root)
    rows = []
    for p in images:
        rel = os.path.relpath(p, root)
        image_name = os.path.basename(p)
        parent = Path(p).parent.name
        rows.append({
            "image_id": str(uuid.uuid4()),
            "image_path": p,
            "image_name": image_name,
            "rel_path": rel,
            "inferred_label": parent
        })
    df = pd.DataFrame(rows)
    df.to_csv(OUT_INDEX, index=False)
    print(f"Wrote index with {len(df)} rows -> {OUT_INDEX}")
    return df

def run_batch_process(dataset_root=None, resume=True, skip_existing=True, batch_sleep=0.1, stop_on_error=False):
    root = dataset_root or DATASET_ROOT
    if not os.path.exists(OUT_INDEX):
        print("Index missing, building index first...")
        build_index(root)
    df = pd.read_csv(OUT_INDEX)

    existing = set()
    if resume and os.path.exists(OUT_RESULTS):
        try:
            rdf = pd.read_csv(OUT_RESULTS)
            existing = set(rdf["image_path"].tolist())
            print(f"Resuming: found {len(existing)} already-processed model-image rows.")
        except Exception as e:
            print("Could not read existing results CSV:", e)

    first_write = not os.path.exists(OUT_RESULTS)
    with open(OUT_RESULTS, "a", newline="", encoding="utf-8") as fout:
        writer = csv.writer(fout)
        if first_write:
            writer.writerow([
                "image_path", "image_name",
                "model", "calories_estimate", "time_s", "timestamp"
            ])

        for _, row in df.iterrows():
            img_path = row["image_path"]
            if skip_existing and img_path in existing:
                # Skip if any row for this image exists (coarse but safe)
                continue

            t0 = time.time()
            try:
                r1 = analyze_image_gemini_1(img_path)
                t1 = time.time() - t0
                writer.writerow([img_path, row["image_name"], r1.get("model",""), r1.get("calories_estimate",""), t1, time.time()])
                fout.flush()

                r2 = analyze_image_gemini_2(img_path)
                t2 = time.time() - t0
                writer.writerow([img_path, row["image_name"], r2.get("model",""), r2.get("calories_estimate",""), t2, time.time()])
                fout.flush()

                r3 = analyze_image_gemini_3(img_path)
                t3 = time.time() - t0
                writer.writerow([img_path, row["image_name"], r3.get("model",""), r3.get("calories_estimate",""), t3, time.time()])
                fout.flush()

                r4 = analyze_image_gemini_4(img_path)
                t4 = time.time() - t0
                writer.writerow([img_path, row["image_name"], r4.get("model",""), r4.get("calories_estimate",""), t4, time.time()])
                fout.flush()

                time.sleep(batch_sleep)
            except Exception as ex:
                print(f"Error processing {img_path}: {ex}")
                writer.writerow([img_path, row["image_name"], "ERROR", str(ex), time.time()-t0, time.time()])
                fout.flush()
                if stop_on_error:
                    raise

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--index-only", action="store_true", help="Only build images_index.csv and exit")
    parser.add_argument("--root", type=str, default=None, help="Dataset root override")
    parser.add_argument("--batch-sleep", type=float, default=0.2, help="Sleep between images")
    parser.add_argument("--no-resume", action="store_true", help="Don't resume from existing results")
    args = parser.parse_args()

    dataset_root = args.root or DATASET_ROOT
    if args.index_only:
        build_index(dataset_root)
    else:
        run_batch_process(dataset_root=dataset_root, resume=not args.no_resume, skip_existing=True, batch_sleep=args.batch_sleep)