# streamlit_app.py
import streamlit as st
import os
import time
import pandas as pd
import random
from PIL import Image
from analysis import (
    analyze_image_gemini_1,
    analyze_image_gemini_2,
    analyze_image_gemini_3,
    analyze_image_gemini_4,
)

# Constants
INDEX_CSV = "images_index.csv"
RESULTS_CSV = "analysis_results.csv"
# DATASET_ROOT = "/home/sheru/datasets/uecfood256-small-random" this line works only on local, not on deployed render
DATASET_ROOT = os.path.join(
    os.path.dirname(__file__),
    "datasets",
    "uecfood256-small-random",
    "UECFOOD256"
)


st.set_page_config(page_title="🍔 Food Calorie Estimator", layout="wide")
st.title("🍔 Food Calorie Estimator Benchmark")

# Helper: find images if index missing
def find_image_files(root):
    exts = (".png", ".jpg", ".jpeg")
    out = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith(exts):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)

# Load image list
if os.path.exists(INDEX_CSV):
    idx_df = pd.read_csv(INDEX_CSV)
    image_files = idx_df["image_path"].tolist()
else:
    image_files = find_image_files(DATASET_ROOT)

if not image_files:
    st.warning("No images found in dataset path.")
    st.stop()

# Session state for batch processing and navigation
if "processing_complete" not in st.session_state:
    # On first run, select 20 random images
    num_images = min(20, len(image_files)) # Ensure we don't exceed available images
    st.session_state.image_subset = random.sample(image_files, num_images)
    st.session_state.current_processing_index = 0
    st.session_state.processing_complete = False
    st.session_state.results = {} # To store results
    st.session_state.idx = 0      # For navigation *after* processing

# Define models and names *before* the if/else block
models = [
    analyze_image_gemini_1,
    analyze_image_gemini_2,
    analyze_image_gemini_3,
    analyze_image_gemini_4
]
model_names = ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-pro-preview", "gemini-2.5-flash-preview"]

# --- Main App Logic: Two Modes ---

if not st.session_state.processing_complete:
    # --- MODE 1: PROCESSING ---
    
    idx = st.session_state.current_processing_index
    image_path = st.session_state.image_subset[idx]
    image_name = os.path.basename(image_path)
    
    st.info(f"Processing image {idx + 1}/{len(st.session_state.image_subset)}: {image_name}")
    st.progress((idx + 1) / len(st.session_state.image_subset))
    
    # Layout: image left, outputs right
    left_col, right_col = st.columns([1.2, 2])

    with left_col:
        st.subheader(f"📷 {image_name}")
        img = Image.open(image_path)
        st.image(img, use_column_width=True)

    with right_col:
        st.subheader("Model outputs (3×2 grid)")
        current_image_results = {}

        # Prepare 2 rows of 3 columns
        for row in range(2):
            cols = st.columns(3)
            for col_idx in range(3):
                model_idx = row*3 + col_idx
                if model_idx >= len(models):
                    continue
                with cols[col_idx]:
                    model_name = model_names[model_idx]
                    st.subheader(model_name)
                    try:
                        # Run model
                        r = models[model_idx](image_path)
                        st.text(r.get("calories_estimate", ""))
                        # Store result for navigation mode
                        current_image_results[model_name] = r 
                        
                        # Append to CSV
                        first_write = not os.path.exists(RESULTS_CSV)
                        with open(RESULTS_CSV, "a", newline="", encoding="utf-8") as fout:
                            import csv
                            writer = csv.writer(fout)
                            if first_write:
                                writer.writerow(["image_path", "image_name", "model", "calories_estimate", "timestamp"])
                            writer.writerow([image_path, image_name, r.get("model",""), r.get("calories_estimate",""), time.time()])
                    except Exception as e:
                        st.error(f"Failed: {e}")
                        # Store error for navigation mode
                        current_image_results[model_name] = {"error": str(e)} 

        # Save all results for this image to session state
        st.session_state.results[image_path] = current_image_results

    # --- Auto-advance logic ---
    st.session_state.current_processing_index += 1
    
    if st.session_state.current_processing_index >= len(st.session_state.image_subset):
        # Finished processing
        st.session_state.processing_complete = True
        st.success("All 20 images processed! Reloading in navigation mode...")
    
    # Wait 3 seconds and rerun to show the next image
    time.sleep(3) 
    st.rerun()

else:
    # --- MODE 2: NAVIGATION ---
    
    st.success(f"Processing complete. You can now browse the {len(st.session_state.image_subset)} results.")
    
    image_files_subset = st.session_state.image_subset
    
    # Navigation functions
    def prev_image():
        if st.session_state.idx > 0:
            st.session_state.idx -= 1

    def next_image():
        if st.session_state.idx < len(image_files_subset) - 1:
            st.session_state.idx += 1
    
    # Navigation UI
    nav_col1, nav_col2, nav_col3 = st.columns([1, 6, 1])
    with nav_col1:
        st.button("← Prev", on_click=prev_image, disabled=(st.session_state.idx==0))
    with nav_col2:
        st.markdown(f"**Image {st.session_state.idx + 1}/{len(image_files_subset)}**")
    with nav_col3:
        st.button("Next →", on_click=next_image, disabled=(st.session_state.idx==len(image_files_subset)-1))

    # Jump slider
    new_idx = st.slider("Jump to image", 1, len(image_files_subset), st.session_state.idx + 1) - 1
    if new_idx != st.session_state.idx:
        st.session_state.idx = new_idx

    # Current image
    idx = st.session_state.idx
    image_path = image_files_subset[idx]
    image_name = os.path.basename(image_path)

    # Layout: image left, outputs right
    left_col, right_col = st.columns([1.2, 2])

    with left_col:
        st.subheader(f"📷 {image_name}")
        img = Image.open(image_path)
        st.image(img, use_column_width=True)

    with right_col:
        st.subheader("Model outputs (3×2 grid)")
        
        # Get pre-computed results from session state
        all_model_results = st.session_state.results.get(image_path, {})

        # Prepare 2 rows of 3 columns
        for row in range(2):
            cols = st.columns(3)
            for col_idx in range(3):
                model_idx = row*3 + col_idx
                if model_idx >= len(models):
                    continue
                with cols[col_idx]:
                    model_name = model_names[model_idx]
                    st.subheader(model_name)
                    
                    # Display the stored result
                    r = all_model_results.get(model_name)
                    if r:
                        if "error" in r:
                            st.error(f"Failed: {r['error']}")
                        else:
                            st.text(r.get("calories_estimate", ""))
                    else:
                        st.warning("No result found.")

    # Optional summary
    if st.checkbox("Show summary for this image"):
        if os.path.exists(RESULTS_CSV):
            rdf = pd.read_csv(RESULTS_CSV)
            rows = rdf[rdf["image_path"] == image_path]
            st.dataframe(rows)