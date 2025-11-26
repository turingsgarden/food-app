# streamlit_app.py
from model_pipeline import full_image_analysis
import streamlit as st
import os
import time
import pandas as pd
from PIL import Image

# Constants
INDEX_CSV = "images_index.csv"
RESULTS_CSV = "analysis_results.csv"
DATASET_ROOT = os.path.join(
    os.path.dirname(__file__),
    "datasets",
    "uecfood256-20"
)

# Define all Gemini models to test
GEMINI_MODELS = [
    # 'gemini-2.0-flash-exp',
    'gemini-2.5-pro',
    'gemini-2.5-flash',
    'gemini-2.5-pro-preview-03-25',
    'gemini-2.0-flash-001'
]

st.set_page_config(page_title="Food Calorie Estimator", layout="wide")
st.title("Food Calorie Estimator - Multi-Model Benchmark")

# Helper: Load existing results from CSV
@st.cache_data
def load_results_cache():
    """Load all existing results from CSV into a dictionary for fast lookup"""
    if not os.path.exists(RESULTS_CSV):
        return {}
    
    try:
        df = pd.read_csv(
            RESULTS_CSV,
            on_bad_lines='skip',
            quoting=1,
            escapechar='\\',
            encoding='utf-8'
        )
        cache = {}
        
        for _, row in df.iterrows():
            key = (row['image_path'], row['model'])
            cache[key] = {
                'gemini_description': str(row.get('gemini_description', 'N/A')),
                'dish_names': str(row.get('dish_names', 'N/A')),
                'cleaned_ingredients': str(row.get('cleaned_ingredients', 'N/A')),
                'hidden_ingredients': str(row.get('hidden_ingredients', 'N/A')),
                'nutrition_info': str(row.get('full_nutrition', 'N/A'))
            }
        
        st.info(f"Loaded {len(cache)} cached results from CSV")
        return cache
    except Exception as e:
        st.warning(f"Could not load cache: {e}")
        st.info("Tip: You may need to delete the CSV and start fresh")
        return {}

# Helper: Load full CSV as DataFrame
@st.cache_data
def load_full_csv():
    """Load complete CSV for viewer mode"""
    if not os.path.exists(RESULTS_CSV):
        return None
    
    try:
        df = pd.read_csv(
            RESULTS_CSV,
            on_bad_lines='skip',
            quoting=1,
            escapechar='\\',
            encoding='utf-8'
        )
        return df
    except Exception as e:
        st.error(f"Failed to load CSV: {e}")
        return None

# Helper: Save result to CSV with proper escaping
def save_result_to_csv(image_path, model_name, result_data):
    """Append a single result to CSV with proper escaping"""
    try:
        first_write = not os.path.exists(RESULTS_CSV)
        with open(RESULTS_CSV, "a", newline="", encoding="utf-8") as fout:
            import csv
            writer = csv.writer(fout, quoting=csv.QUOTE_ALL, escapechar='\\')
            
            if first_write:
                writer.writerow([
                    "image_path", "model", "dish_names", "gemini_description",
                    "cleaned_ingredients", "hidden_ingredients", 
                    "full_nutrition", "timestamp"
                ])
            
            # Clean data to remove problematic characters
            def clean_field(value):
                if value is None or value == 'N/A':
                    return 'N/A'
                text = str(value)[:500]
                text = text.replace('\n', ' ').replace('\r', ' ')
                return text
            
            nutrition_str = result_data.get('nutrition_info', 'N/A')
            if nutrition_str != 'N/A':
                nutrition_str = nutrition_str.replace('\n', '; ')
            
            writer.writerow([
                image_path,
                model_name,
                clean_field(result_data.get('dish_names', 'N/A')),
                clean_field(result_data.get('gemini_description', 'N/A')),
                clean_field(result_data.get('cleaned_ingredients', 'N/A')),
                clean_field(result_data.get('hidden_ingredients', 'N/A')),
                clean_field(nutrition_str),
                time.time()
            ])
        
        # Clear cache so it reloads with new data
        st.cache_data.clear()
        
    except Exception as e:
        st.error(f"Failed to save to CSV: {e}")

# Helper: Get or compute result
def get_or_compute_result(image_path, model_name, cache):
    """
    Check if result exists in cache/CSV, otherwise compute it.
    Returns: (result_dict, was_cached)
    """
    cache_key = (image_path, model_name)
    
    if cache_key in cache:
        st.success(f"{model_name} - Loaded from cache")
        return cache[cache_key], True
    
    st.info(f"{model_name} - Computing new result...")
    try:
        result = full_image_analysis(image_path, user_id="streamlit_test", model_name=model_name)
        
        result_data = {
            'gemini_description': result.get('image_description', 'N/A'),
            'dish_names': result.get('dish_prediction', 'N/A'),
            'cleaned_ingredients': result.get('image_description', 'N/A'),
            'hidden_ingredients': result.get('hidden_ingredients', 'N/A'),
            'nutrition_info': result.get('nutrition_info', 'N/A')
        }
        
        save_result_to_csv(image_path, model_name, result_data)
        st.success(f"{model_name} - Computed and saved")
        return result_data, False
        
    except Exception as e:
        st.error(f"{model_name} failed: {e}")
        import traceback
        st.text(traceback.format_exc())
        
        return {
            'gemini_description': 'N/A',
            'dish_names': 'Error',
            'cleaned_ingredients': 'N/A',
            'hidden_ingredients': 'N/A',
            'nutrition_info': 'N/A',
            'error': str(e)
        }, False

# Helper: find images and validate they exist
def find_and_validate_images(root):
    """Find all image files and validate they exist"""
    exts = (".png", ".jpg", ".jpeg")
    valid_images = []
    
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if fn.lower().endswith(exts):
                full_path = os.path.join(dirpath, fn)
                try:
                    with Image.open(full_path) as img:
                        img.verify()
                    valid_images.append(full_path)
                except Exception as e:
                    st.warning(f"Skipping invalid/missing image: {fn} - {str(e)}")
                    continue
    
    return sorted(valid_images)

# Sidebar: Mode selection
with st.sidebar:
    st.header("Mode Selection")
    
    mode = st.radio(
        "Choose mode:",
        ["CSV Viewer", "Process Images"],
        index=0
    )
    
    st.divider()
    st.header("Stats")
    
    # Load cache for stats
    results_cache = load_results_cache()
    st.info(f"**Cached Results:** {len(results_cache)}")
    
    # Count unique images in CSV
    df_full = load_full_csv()
    if df_full is not None and len(df_full) > 0:
        unique_images = df_full['image_path'].nunique()
        st.info(f"**Images in CSV:** {unique_images}")
    
    st.divider()
    
    if st.button("Delete CSV & Reset", type="secondary"):
        if os.path.exists(RESULTS_CSV):
            os.remove(RESULTS_CSV)
            st.success("CSV deleted")
        for key in list(st.session_state.keys()):
            del st.session_state[key]
        st.cache_data.clear()
        st.rerun()

# === MODE 1: CSV VIEWER ===
if mode == "CSV Viewer":
    st.header("CSV Viewer Mode")
    st.info("Browse all results stored in CSV with images")
    
    df = load_full_csv()
    
    if df is None or len(df) == 0:
        st.warning("No results in CSV yet. Run 'Process Images' mode first.")
        st.stop()
    
    # Get unique images
    unique_images = df['image_path'].unique()
    
    # Initialize navigation
    if 'csv_idx' not in st.session_state:
        st.session_state.csv_idx = 0
    
    # Navigation controls
    def prev_csv():
        if st.session_state.csv_idx > 0:
            st.session_state.csv_idx -= 1
    
    def next_csv():
        if st.session_state.csv_idx < len(unique_images) - 1:
            st.session_state.csv_idx += 1
    
    col1, col2, col3 = st.columns([1, 6, 1])
    with col1:
        st.button("← Prev", on_click=prev_csv, disabled=(st.session_state.csv_idx==0))
    with col2:
        st.markdown(f"**Image {st.session_state.csv_idx + 1} / {len(unique_images)}**")
    with col3:
        st.button("Next →", on_click=next_csv, disabled=(st.session_state.csv_idx==len(unique_images)-1))
    
    # Jump slider
    if len(unique_images) > 1:
        new_idx = st.slider(
            "Jump to image:", 
            1, 
            len(unique_images), 
            st.session_state.csv_idx + 1
        ) - 1
        if new_idx != st.session_state.csv_idx:
            st.session_state.csv_idx = new_idx
    else:
        st.info("Only 1 image in dataset")
    
    # Current image
    current_image_path = unique_images[st.session_state.csv_idx]
    image_name = os.path.basename(current_image_path)
    
    # Filter CSV for this image
    image_results = df[df['image_path'] == current_image_path]
    
    # Layout: Image left, results right
    left_col, right_col = st.columns([1, 2])
    
    with left_col:
        st.subheader(f"{image_name}")
        
        if os.path.exists(current_image_path):
            try:
                img = Image.open(current_image_path)
                st.image(img, use_container_width=True)
            except Exception as e:
                st.error(f"Failed to load image: {e}")
        else:
            st.error(f"Image not found: {current_image_path}")
        
        st.caption(f"Path: `{current_image_path}`")
    
    with right_col:
        st.subheader("Model Outputs")
        
        # Display results for each model
        for _, row in image_results.iterrows():
            model_name = row['model']
            
            with st.container():
                st.markdown(f"### {model_name}")
                
                col1, col2 = st.columns(2)
                
                with col1:
                    st.text(f"Dish: {row['dish_names']}")
                    
                    with st.expander("Cleaned Ingredients"):
                        st.text(row['cleaned_ingredients'])
                
                with col2:
                    with st.expander("Hidden Ingredients"):
                        st.text(row['hidden_ingredients'])
                    
                    with st.expander("Nutrition Info"):
                        nutrition = str(row['full_nutrition'])
                        if nutrition and nutrition != 'N/A':
                            st.text(nutrition)
                            # for line in nutrition.replace('; ', '\n').splitlines():
                            #     parts = line.split('|')
                            #     if len(parts) >= 3:
                            #         st.text(f"{parts[0]}: {parts[1].strip()} {parts[2].strip()}")
                        else:
                            st.text("N/A")
                
                st.caption(f"Timestamp: {row['timestamp']}")
                st.divider()

# === MODE 2: PROCESS IMAGES ===
else:
    st.header("Process Images Mode")
    
    # Load and validate image list
    st.info("Scanning for valid images in dataset...")
    image_files = find_and_validate_images(DATASET_ROOT)
    
    if not image_files:
        st.error("No valid images found in dataset path.")
        st.stop()
    
    st.success(f"Found {len(image_files)} valid images")
    
    # Load cache
    results_cache = load_results_cache()
    
    # Session state for batch processing
    if "processing_complete" not in st.session_state:
        st.session_state.image_subset = sorted(image_files)
        st.session_state.current_processing_index = 0
        st.session_state.processing_complete = False
        st.session_state.results = {}
    elif len(image_files) != len(st.session_state.get('image_subset', [])):
        st.warning("Image count changed, resetting processing state")
        st.session_state.image_subset = sorted(image_files)
        st.session_state.current_processing_index = 0
        st.session_state.processing_complete = False
        st.session_state.results = {}
    
    if not st.session_state.processing_complete:
        # PROCESSING MODE
        idx = st.session_state.current_processing_index
        
        if idx >= len(st.session_state.image_subset):
            st.session_state.processing_complete = True
            st.rerun()
        
        image_path = st.session_state.image_subset[idx]
        image_name = os.path.basename(image_path)
        
        if not os.path.exists(image_path):
            st.error(f"Image not found: {image_name}")
            st.session_state.current_processing_index += 1
            time.sleep(1)
            st.rerun()
        
        st.info(f"Processing image {idx + 1}/{len(st.session_state.image_subset)}: {image_name}")
        st.progress((idx + 1) / len(st.session_state.image_subset))
        
        left_col, right_col = st.columns([1, 2])
        
        with left_col:
            st.subheader(f"{image_name}")
            try:
                img = Image.open(image_path)
                st.image(img, use_container_width=True)
            except Exception as e:
                st.error(f"Failed to load image: {e}")
                st.session_state.current_processing_index += 1
                time.sleep(1)
                st.rerun()
        
        with right_col:
            st.subheader("Model Outputs")
            current_image_results = {}
            
            for model_name in GEMINI_MODELS:
                with st.container():
                    st.markdown(f"### {model_name}")
                    
                    result_data, was_cached = get_or_compute_result(image_path, model_name, results_cache)
                    
                    if "error" not in result_data:
                        col1, col2 = st.columns(2)
                        
                        with col1:
                            st.text(f"Dish: {result_data.get('dish_names', 'N/A')}")
                            with st.expander("Cleaned Ingredients"):
                                st.text(result_data.get('cleaned_ingredients', 'N/A'))
                        
                        with col2:
                            with st.expander("Hidden Ingredients"):
                                st.text(result_data.get('hidden_ingredients', 'N/A'))
                            with st.expander("Nutrition Info"):
                                nutrition_info = result_data.get('nutrition_info', 'N/A')
                                if nutrition_info and nutrition_info != 'N/A':
                                    for line in nutrition_info.replace('; ', '\n').splitlines():
                                        parts = line.split('|')
                                        if len(parts) >= 3:
                                            st.text(f"{parts[0]}: {parts[1].strip()} {parts[2].strip()}")
                                else:
                                    st.text("N/A")
                    
                    current_image_results[model_name] = result_data
                    st.divider()
            
            st.session_state.results[image_path] = current_image_results
        
        st.session_state.current_processing_index += 1
        
        if st.session_state.current_processing_index >= len(st.session_state.image_subset):
            st.session_state.processing_complete = True
            st.success("All images processed! Switch to CSV Viewer mode to browse results.")
        
        time.sleep(3)
        st.rerun()
    
    else:
        # PROCESSING COMPLETE
        st.success(f"Processing complete! {len(st.session_state.image_subset)} images processed.")
        st.info("Switch to 'CSV Viewer' mode in the sidebar to browse all results.")
        
        if st.button("Process More Images"):
            st.session_state.processing_complete = False
            st.session_state.current_processing_index = 0
            st.rerun()