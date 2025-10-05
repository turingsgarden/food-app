# streamlit_app.py
import streamlit as st
import os
import time
import subprocess
import sys
from PIL import Image
import pandas as pd
import kagglehub

# import cached analyze wrappers if you still want them
from analysis import (
    analyze_image_gemini_1,
    analyze_image_gemini_2,
    analyze_image_gemini_3,
    analyze_image_gemini_4,
)

# constants for index/results and background process
INDEX_CSV = "images_index.csv"
RESULTS_CSV = "analysis_results.csv"
BG_PID_FILE = "build_bg.pid"
BG_LOG = "build_bg.log"
BG_ERR = "build_bg.err"
BUILD_SCRIPT = "build_images_csv.py"

# Ensure dataset is present (you said you already downloaded with kagglehub)
path = kagglehub.dataset_download("rkuo2000/uecfood256")
DATASET_ROOT = path
print("Using dataset root:", DATASET_ROOT)

st.set_page_config(page_title="🍔 Food Calorie Estimator Benchmark", layout="wide")
st.title("🍔 Food Calorie Estimator Benchmark")
st.write("Carousel: left = image, right = all model outputs for that image.")

# helper: find images if index missing
def find_image_files(root):
    exts = (".png", ".jpg", ".jpeg")
    out = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith(exts):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)

# prefer index CSV if available
if os.path.exists(INDEX_CSV):
    idx_df = pd.read_csv(INDEX_CSV)
    image_files = idx_df["image_path"].tolist()
else:
    image_files = find_image_files(DATASET_ROOT)

if not image_files:
    st.warning("No images found in dataset path.")
    st.stop()

# session index for carousel
if "idx" not in st.session_state:
    st.session_state.idx = 0

def prev_image():
    if st.session_state.idx > 0:
        st.session_state.idx -= 1

def next_image():
    if st.session_state.idx < len(image_files) - 1:
        st.session_state.idx += 1

# Top controls area (build index / start background / stop background)
control_col_1, control_col_2, control_col_3 = st.columns([1,1,2])
with control_col_1:
    if st.button("Build / Rebuild images_index.csv (fast)"):
        st.info("Building index... (scanning dataset)")
        try:
            # call build_index directly to keep it fast and non-blocking
            # import lazily to avoid circular when module changed
            from build_images_csv import build_index
            df = build_index(DATASET_ROOT)
            st.success(f"Built index with {len(df)} rows -> {INDEX_CSV}")
            # reload image_files from index
            image_files[:] = df["image_path"].tolist()
            st.experimental_rerun()
        except Exception as e:
            st.error(f"Failed to build index: {e}")

with control_col_2:
    start_disabled = os.path.exists(BG_PID_FILE)
    stop_disabled = not start_disabled
    if st.button("Start background batch (resume)", disabled=start_disabled):
        # launch the build_images_csv.py as detached process
        cmd = [sys.executable, BUILD_SCRIPT]
        # Launch with nohup-like detachment: write pid to file
        try:
            fout = open(BG_LOG, "a")
            ferr = open(BG_ERR, "a")
            # On Unix use preexec_fn=os.setpgrp so a killpg can stop all child processes
            p = subprocess.Popen(cmd, stdout=fout, stderr=ferr, preexec_fn=os.setpgrp)
            with open(BG_PID_FILE, "w") as pf:
                pf.write(str(p.pid))
            st.success(f"Started background batch (PID {p.pid}). Logs: {BG_LOG}, {BG_ERR}")
        except Exception as e:
            st.error(f"Failed to start background batch: {e}")

    if st.button("Stop background batch", disabled=stop_disabled):
        # stop based on PID file
        try:
            pid = int(open(BG_PID_FILE).read().strip())
            # kill process group
            import signal
            os.killpg(pid, signal.SIGTERM)
            os.remove(BG_PID_FILE)
            st.success(f"Sent SIGTERM to group of PID {pid}")
        except Exception as e:
            st.error(f"Failed to stop background job: {e}")

with control_col_3:
    # show quick progress
    if os.path.exists(RESULTS_CSV):
        try:
            rdf = pd.read_csv(RESULTS_CSV)
            processed_images = rdf["image_path"].nunique()
            total_images = len(image_files)
            st.metric("Images with at least one model row", f"{processed_images}/{total_images}")
            # show last few rows
            st.write("Last 5 results (most recent):")
            st.dataframe(rdf.tail(5))
        except Exception as e:
            st.write("Could not read results CSV:", e)
    else:
        st.info("No results CSV found. Start background batch to generate it, or run live analyses per-image.")

# Slider and nav
top_c1, top_c2, top_c3 = st.columns([1, 6, 1])
with top_c1:
    st.button("← Prev", on_click=prev_image, disabled=(st.session_state.idx == 0))
with top_c2:
    st.markdown(f"**Image {st.session_state.idx + 1}/{len(image_files)}**")
with top_c3:
    st.button("Next →", on_click=next_image, disabled=(st.session_state.idx == len(image_files) - 1))

new_idx = st.slider("Jump to image", 1, len(image_files), st.session_state.idx + 1) - 1
if new_idx != st.session_state.idx:
    st.session_state.idx = new_idx

idx = st.session_state.idx
image_path = image_files[idx]
image_name = os.path.basename(image_path)

left_col, right_col = st.columns([1, 1.6])
with left_col:
    st.subheader(f"📷 {image_name}")
    img = Image.open(image_path)
    st.image(img, caption=image_name, use_container_width=True)

with right_col:
    st.subheader("Model outputs (for current image)")
    # First check results CSV for precomputed outputs
    precomputed = None
    if os.path.exists(RESULTS_CSV):
        try:
            rdf = pd.read_csv(RESULTS_CSV)
            precomputed = rdf[rdf["image_path"] == image_path]
        except Exception as e:
            st.error(f"Error reading results CSV: {e}")
            precomputed = None

    if precomputed is not None and not precomputed.empty:
        st.info("Showing precomputed results from CSV")
        for _, r in precomputed.iterrows():
            st.markdown(f"### {r['model']}")
            st.caption(f"Recorded time: {r.get('time_s','')} s — saved at {r.get('timestamp','')}")
            st.text(r.get("calories_estimate", ""))
    else:
        st.info("No precomputed results for this image.")
        st.write("You can run live analyzers for this image and append results to CSV (recommended for one-offs).")

        # Live run button (runs analyzers for single image and appends to RESULTS_CSV)
        if st.button("Run live analysis for this image and append to CSV"):
            # run analyzers and append four rows to CSV
            try:
                t0 = time.time()
                r1 = analyze_image_gemini_1(image_path)
                t1 = time.time() - t0
                r2 = analyze_image_gemini_2(image_path)
                t2 = time.time() - t0
                r3 = analyze_image_gemini_3(image_path)
                t3 = time.time() - t0
                r4 = analyze_image_gemini_4(image_path)
                t4 = time.time() - t0

                # ensure header exists
                first_write = not os.path.exists(RESULTS_CSV)
                with open(RESULTS_CSV, "a", newline="", encoding="utf-8") as fout:
                    import csv
                    writer = csv.writer(fout)
                    if first_write:
                        writer.writerow([
                            "image_path", "image_name",
                            "model", "calories_estimate", "time_s", "timestamp"
                        ])
                    writer.writerow([image_path, image_name, r1.get("model",""), r1.get("calories_estimate",""), t1, time.time()])
                    writer.writerow([image_path, image_name, r2.get("model",""), r2.get("calories_estimate",""), t2, time.time()])
                    writer.writerow([image_path, image_name, r3.get("model",""), r3.get("calories_estimate",""), t3, time.time()])
                    writer.writerow([image_path, image_name, r4.get("model",""), r4.get("calories_estimate",""), t4, time.time()])
                st.success("Appended live analysis results to CSV.")
                st.experimental_rerun()
            except Exception as e:
                st.error(f"Live analysis failed: {e}")

# Optional summary row checkbox
if st.checkbox("Show summary row for this image"):
    # try reading precomputed or show last live runs
    summary_row = {
        "Image": image_name,
        "gemini-2.5-pro_calories": "",
        "gemini-2.5-pro_time_s": "",
        "gemini-2.5-flash_calories": "",
        "gemini-2.5-flash_time_s": "",
        "gemini-2.5-pro-preview_calories": "",
        "gemini-2.5-pro-preview_time_s": "",
        "gemini-2.5-flash-preview_calories": "",
        "gemini-2.5-flash-preview_time_s": "",
    }
    if os.path.exists(RESULTS_CSV):
        try:
            rdf = pd.read_csv(RESULTS_CSV)
            rows = rdf[rdf["image_path"] == image_path]
            for _, r in rows.iterrows():
                mod = r.get("model","")
                val = r.get("calories_estimate","")
                ts = r.get("time_s","")
                if "pro-preview" in mod:
                    summary_row["gemini-2.5-pro-preview_calories"] = val
                    summary_row["gemini-2.5-pro-preview_time_s"] = ts
                elif "flash-preview" in mod:
                    summary_row["gemini-2.5-flash-preview_calories"] = val
                    summary_row["gemini-2.5-flash-preview_time_s"] = ts
                elif "flash" in mod and "preview" not in mod:
                    summary_row["gemini-2.5-flash_calories"] = val
                    summary_row["gemini-2.5-flash_time_s"] = ts
                elif "pro" in mod and "preview" not in mod:
                    summary_row["gemini-2.5-pro_calories"] = val
                    summary_row["gemini-2.5-pro_time_s"] = ts
        except Exception as e:
            st.write("Could not read results CSV for summary:", e)
    st.dataframe(pd.DataFrame([summary_row]))
