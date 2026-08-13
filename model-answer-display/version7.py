import streamlit as st
import json
import os
import ast
import pandas as pd
from PIL import Image

# -----------------------------------------------------------------------
# Paths — edit these to match where you run the app
# -----------------------------------------------------------------------
GROUND_TRUTH_CSV_PATH = "fsb_dataset/food_scan_bench_v1.csv"
MODEL_FILES = {
    "gemini-3.1-flash": "output/FoodScanBench_Gemini_pydantic_food_dataset_analysis.json",
}
IMAGE_DIR = "fsb_dataset/fsb_images"  # folder containing fsb_00000.jpg, fsb_00001.jpg, ...


def parse_ingredients_cell(cell):
    """The CSV stores ingredients_list as a double-encoded Python-literal
    string, e.g. '"[{\\'name\\': ...}]"'. Unwrap it back into a list of dicts."""
    if cell is None or (isinstance(cell, float) and pd.isna(cell)):
        return []
    try:
        value = ast.literal_eval(cell)
        # First pass may just peel off an outer string layer
        if isinstance(value, str):
            value = ast.literal_eval(value)
        if isinstance(value, list):
            return value
    except (ValueError, SyntaxError):
        pass
    return []


def load_model_data():
    """Load prediction data from the JSON file(s) and ground truth from the CSV"""
    model_data = {}
    available_models = []

    for model_name, file_path in MODEL_FILES.items():
        try:
            encodings = ["utf-8", "utf-8-sig", "latin-1", "cp1252"]
            loaded = False
            for encoding in encodings:
                try:
                    with open(file_path, "r", encoding=encoding) as f:
                        model_data[model_name] = json.load(f)
                        available_models.append(model_name)
                        loaded = True
                        break
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
            if not loaded:
                st.warning(f"Failed to load {model_name}")
        except FileNotFoundError:
            st.error(f"File not found: {file_path}")
        except Exception as e:
            st.error(f"Error loading {model_name}: {e}")

    # Load ground truth data from CSV
    ground_truth_df = pd.DataFrame()
    try:
        ground_truth_df = pd.read_csv(GROUND_TRUTH_CSV_PATH)
        st.success(f"Loaded {len(ground_truth_df)} ground truth records")
    except FileNotFoundError:
        st.error(f"Ground truth file not found: {GROUND_TRUTH_CSV_PATH}")
    except Exception as e:
        st.error(f"Error loading ground truth: {e}")

    return model_data, available_models, ground_truth_df


def get_all_images():
    """Get all image paths, support multiple formats"""
    if not os.path.exists(IMAGE_DIR):
        st.error(f"Directory does not exist: {IMAGE_DIR}")
        return None

    all_files = os.listdir(IMAGE_DIR)
    image_extensions = [".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"]
    image_files = []

    for file in all_files:
        file_lower = file.lower()
        if any(file_lower.endswith(ext) for ext in image_extensions):
            full_path = os.path.join(IMAGE_DIR, file)
            image_files.append(full_path)

    if not image_files:
        st.error(f"No image files found in: {IMAGE_DIR}")
        return None

    image_files.sort()
    return image_files


def build_indices(model_data, available_models, ground_truth_df):
    """Build indices for fast lookup, keyed directly by image_id"""
    # Build model prediction index (by image_id)
    model_dish_mapping = {}
    for model_name in available_models:
        model_dish_mapping[model_name] = {}
        for item in model_data.get(model_name, []):
            image_id = item.get("image_id")
            if image_id:
                model_dish_mapping[model_name][str(image_id)] = item

    # Build ground truth index (by image_id)
    ground_truth_mapping = {}
    if not ground_truth_df.empty and "image_id" in ground_truth_df.columns:
        for _, row in ground_truth_df.iterrows():
            image_id = row.get("image_id")
            if pd.notna(image_id):
                ground_truth_mapping[str(image_id)] = row.to_dict()

    # Build image path index (by image_id, matched against image_filename in CSV)
    image_files = get_all_images()
    image_mapping = {}
    if image_files:
        filename_to_path = {os.path.basename(p): p for p in image_files}
        for image_id, row in ground_truth_mapping.items():
            filename = row.get("image_filename")
            if filename and filename in filename_to_path:
                image_mapping[image_id] = filename_to_path[filename]

    # Print debug information
    print("Built indices:")
    print(f"  - Model dishes: {len(model_dish_mapping.get('gemini-2.5-pro', {}))}")
    print(f"  - Ground truth dishes: {len(ground_truth_mapping)}")
    print(f"  - Image dishes: {len(image_mapping)}")

    if ground_truth_mapping:
        sample_ids = list(ground_truth_mapping.keys())[:5]
        print(f"  - Sample ground truth image_ids: {sample_ids}")

    return model_dish_mapping, ground_truth_mapping, image_mapping


def find_model_response_by_dish_id(dish_id, model_dish_mapping, model_name):
    """Find model response by image_id"""
    if model_name not in model_dish_mapping:
        return None
    return model_dish_mapping[model_name].get(str(dish_id))


def find_ground_truth_by_dish_id(dish_id, ground_truth_mapping):
    """Find ground truth by image_id"""
    if not dish_id:
        return None
    return ground_truth_mapping.get(str(dish_id))


def find_image_by_dish_id(dish_id, image_mapping):
    """Find image path by image_id"""
    if not dish_id:
        return None
    return image_mapping.get(str(dish_id))


def render_ingredient_box(items, key_field="name", value_field="quantity", unit="g"):
    """Render an ingredient list as a light-background HTML box instead of st.code,
    so it isn't forced into Streamlit's dark code-block styling."""
    rows = "".join(
        f"<div class='ingredient-row'>"
        f"<span class='ingredient-name'>{item.get(key_field, 'Unknown')}</span>"
        f"<span class='ingredient-value'>{float(item.get(value_field, 0) or 0):.1f} {item.get('unit', unit)}</span>"
        f"</div>"
        for item in items
    )
    st.markdown(f"<div class='content-box'>{rows}</div>", unsafe_allow_html=True)


def display_model_predicted_ingredients(response, model_name):
    """Display model's predicted ingredients (visible and hidden)"""
    if not response:
        st.info("No model response available")
        return

    st.subheader(f"{model_name} Predictions")

    visible_ingredients = response.get("visible_ingredients", [])
    hidden_ingredients = response.get("hidden_ingredients", [])

    st.markdown("**Visible Ingredients:**")
    if visible_ingredients:
        render_ingredient_box(visible_ingredients)
    else:
        st.info("No visible ingredients detected")

    st.markdown("---")

    st.markdown("**Hidden Ingredients:**")
    if hidden_ingredients:
        render_ingredient_box(hidden_ingredients)
    else:
        st.info("No hidden ingredients detected")

    st.markdown("---")
    total_calories = response.get("total_calories")
    if total_calories is not None:
        st.metric("Predicted Total Calories", f"{total_calories:.1f} kcal")


def display_ground_truth_mass(ground_truth):
    """Display ground truth nutrition information from the CSV row"""
    if not ground_truth:
        st.info("No ground truth available")
        return

    st.subheader("Ground Truth")

    # Ingredients first, so this box lines up with "Visible Ingredients"
    # in the prediction column next to it.
    st.markdown("**Ingredients:**")
    ingredients = parse_ingredients_cell(ground_truth.get("ingredients_list"))
    if ingredients:
        render_ingredient_box(ingredients, value_field="quantity")
    else:
        st.info("No ingredients data available")

    st.markdown("---")

    meal_name = ground_truth.get("meal_name")
    if meal_name:
        st.markdown(f"**Meal:** {meal_name}")

    total_calories = ground_truth.get("total_calories")
    cal_text = f"{total_calories:.1f} kcal" if pd.notna(total_calories) else "N/A"
    st.metric("Actual Total Calories", cal_text)

    col_a, col_b, col_c = st.columns(3)
    with col_a:
        carbs = ground_truth.get("total_carbs")
        st.metric("Carbs (g)", f"{carbs:.1f}" if pd.notna(carbs) else "N/A")
    with col_b:
        protein = ground_truth.get("total_protein")
        st.metric("Protein (g)", f"{protein:.1f}" if pd.notna(protein) else "N/A")
    with col_c:
        fat = ground_truth.get("total_fat")
        st.metric("Fat (g)", f"{fat:.1f}" if pd.notna(fat) else "N/A")


def main():
    st.set_page_config(page_title="Food Mass Prediction Display", layout="wide")

    st.markdown(
        """
    <style>
        .stApp {
            background-color: #ffffff;
            color: #111111;
        }
        [data-testid="stHeader"] {
            background-color: #ffffff;
        }
        [data-testid="stSidebar"] {
            background-color: #f5f5f5;
        }

        .main-container {
            min-height: 100vh;
            width: 100%;
        }

        .model-container {
            height: auto !important;
            min-height: 400px;
            max-height: none !important;
            overflow: visible !important;
        }

        .model-content {
            font-size: 14px;
            line-height: 1.6;
        }

        .model-title {
            font-size: 18px;
            font-weight: bold;
            margin-bottom: 15px;
            color: #1f77b4;
        }

        .ground-truth-title {
            font-size: 18px;
            font-weight: bold;
            margin-bottom: 15px;
            color: #ff7f0e;
        }

        .section-title {
            font-size: 14px;
            font-weight: bold;
            margin-top: 10px;
            margin-bottom: 8px;
            color: #333;
        }

        .content-box {
            background-color: #f5f5f5;
            color: #111111;
            padding: 10px;
            border-radius: 5px;
            margin-bottom: 10px;
            font-family: monospace;
            font-size: 14px;
        }

        .ingredient-row {
            display: flex;
            justify-content: space-between;
            padding: 2px 0;
        }

        .ingredient-name {
            font-size: 14px;
        }

        .ingredient-value {
            font-size: 14px;
        }

        .image-container {
            text-align: center;
            margin-bottom: 20px;
        }

        .dish-id-display {
            font-size: 20px;
            font-weight: bold;
            color: #1f77b4;
            text-align: center;
            margin: 20px 0;
        }

        .nav-buttons {
            display: flex;
            gap: 10px;
            justify-content: center;
            margin: 20px 0;
        }

        [data-testid="stMetricValue"] {
            font-size: 14px;
            color: #111111 !important;
        }
        [data-testid="stMetricLabel"] {
            font-size: 14px;
            color: #333333 !important;
        }
        [data-testid="stMetric"] {
            background-color: #f9f9f9;
            padding: 6px 10px;
            border-radius: 5px;
        }

        /* Buttons: white fill, black border/text, in every state */
        .stButton > button {
            background-color: #ffffff !important;
            color: #111111 !important;
            border: 2px solid #111111 !important;
            border-radius: 6px !important;
        }
        .stButton > button:hover {
            background-color: #f2f2f2 !important;
            color: #111111 !important;
            border: 2px solid #111111 !important;
        }
        .stButton > button:active,
        .stButton > button:focus,
        .stButton > button:focus:not(:active) {
            background-color: #e6e6e6 !important;
            color: #111111 !important;
            border: 2px solid #111111 !important;
            box-shadow: none !important;
        }
        .stButton > button:disabled {
            background-color: #f5f5f5 !important;
            color: #aaaaaa !important;
            border: 2px solid #cccccc !important;
        }

        /* Align the search row's text input and buttons on the same baseline */
        div[data-testid="stTextInput"],
        div[data-testid="stButton"] {
            display: flex;
            align-items: flex-end;
        }
        div[data-testid="stTextInput"] > div,
        div[data-testid="stButton"] > button {
            width: 100%;
        }
    </style>
    """,
        unsafe_allow_html=True,
    )

    # Initialize session state
    if "current_page" not in st.session_state:
        st.session_state.current_page = 0
    if "search_dish_id" not in st.session_state:
        st.session_state.search_dish_id = ""
    if "search_mode" not in st.session_state:
        st.session_state.search_mode = False
    if "valid_images" not in st.session_state:
        st.session_state.valid_images = None
    if "data_loaded" not in st.session_state:
        st.session_state.data_loaded = False

    # Load data
    if not st.session_state.data_loaded:
        with st.spinner("Loading data..."):
            model_data, available_models, ground_truth_df = load_model_data()
            if not available_models:
                st.error("No model data found")
                return

            model_dish_mapping, ground_truth_mapping, image_mapping = build_indices(
                model_data, available_models, ground_truth_df
            )

            # Create list of valid entries for pagination.
            # Only include image IDs that have BOTH a ground-truth row AND a
            # model prediction, so every page has something to compare.
            predicted_ids = set(model_dish_mapping.get("gemini-2.5-pro", {}).keys())
            valid_images = []
            for image_id in ground_truth_mapping.keys():
                if image_id in predicted_ids:
                    valid_images.append(
                        {
                            "dish_id": image_id,
                            "image_path": image_mapping.get(image_id),
                        }
                    )

            st.session_state.model_dish_mapping = model_dish_mapping
            st.session_state.available_models = available_models
            st.session_state.ground_truth_mapping = ground_truth_mapping
            st.session_state.image_mapping = image_mapping
            st.session_state.valid_images = valid_images
            st.session_state.data_loaded = True

    # Get data
    model_dish_mapping = st.session_state.model_dish_mapping
    available_models = st.session_state.available_models
    ground_truth_mapping = st.session_state.ground_truth_mapping
    image_mapping = st.session_state.image_mapping
    valid_images = st.session_state.valid_images

    if not valid_images:
        st.warning("No valid ground truth records found.")
        return

    # Title
    st.markdown("<div class='main-container'>", unsafe_allow_html=True)
    st.title("🍽️ Food Ingredient Prediction Display")
    st.markdown("</div>", unsafe_allow_html=True)

    # Search box
    with st.container():
        st.markdown("**Search by Image ID:**")
        col1, col2, col3 = st.columns([3, 1, 1])

        with col1:
            search_input = st.text_input(
                "Search by Image ID:",
                value=st.session_state.search_dish_id,
                placeholder="Enter image ID (e.g., fsb_00000)",
                key="dish_id_search_input",
                label_visibility="collapsed",
            )

        with col2:
            if st.button("Search", use_container_width=True):
                if search_input.strip():
                    st.session_state.search_dish_id = search_input.strip()
                    st.session_state.search_mode = True

                    found_index = -1
                    for i, item in enumerate(valid_images):
                        if item["dish_id"] == st.session_state.search_dish_id:
                            found_index = i
                            break

                    if found_index >= 0:
                        st.session_state.current_page = found_index
                        st.success(f"Found image ID: {st.session_state.search_dish_id}")
                    else:
                        st.error(f"Image ID {st.session_state.search_dish_id} not found")
                else:
                    st.session_state.search_mode = False

        with col3:
            if st.button("Clear Search", use_container_width=True):
                st.session_state.search_dish_id = ""
                st.session_state.search_mode = False
                st.session_state.current_page = 0

    # Navigation and pagination
    total_pages = len(valid_images)
    current_page = st.session_state.current_page

    if 0 <= current_page < total_pages:
        current_item = valid_images[current_page]
        current_dish_id = current_item["dish_id"]
        current_image_path = current_item["image_path"]
        image_name = os.path.basename(current_image_path) if current_image_path else "N/A"

        current_model_response = find_model_response_by_dish_id(
            current_dish_id, model_dish_mapping, "gemini-2.5-pro"
        )
        current_ground_truth = find_ground_truth_by_dish_id(
            current_dish_id, ground_truth_mapping
        )

        st.markdown(
            f"<div class='dish-id-display'>Image ID: {current_dish_id} (Page {current_page + 1}/{total_pages})</div>",
            unsafe_allow_html=True,
        )

        # Navigation controls
        with st.container():
            nav_cols = st.columns([1, 1, 1, 1, 1, 1, 1])

            with nav_cols[0]:
                if st.button("⏮️ First", use_container_width=True):
                    st.session_state.current_page = 0
                    st.session_state.search_mode = False
                    st.rerun()

            with nav_cols[1]:
                if st.button(
                    "◀️ Prev", use_container_width=True, disabled=current_page <= 0
                ):
                    if current_page > 0:
                        st.session_state.current_page -= 1
                        st.session_state.search_mode = False
                        st.rerun()

            with nav_cols[2]:
                page_input = st.number_input(
                    "Page",
                    min_value=1,
                    max_value=total_pages,
                    value=current_page + 1,
                    label_visibility="collapsed",
                    key="page_jump_input",
                )

            with nav_cols[3]:
                if st.button("Go", use_container_width=True):
                    if 1 <= page_input <= total_pages:
                        st.session_state.current_page = page_input - 1
                        st.session_state.search_mode = False
                        st.rerun()

            with nav_cols[4]:
                if st.button(
                    "Next ▶️",
                    use_container_width=True,
                    disabled=current_page >= total_pages - 1,
                ):
                    if current_page < total_pages - 1:
                        st.session_state.current_page += 1
                        st.session_state.search_mode = False
                        st.rerun()

            with nav_cols[5]:
                if st.button("Last ⏭️", use_container_width=True):
                    st.session_state.current_page = total_pages - 1
                    st.session_state.search_mode = False
                    st.rerun()

            with nav_cols[6]:
                st.markdown(f"**{current_page + 1}/{total_pages}**")

        # Three-column layout
        col_left, col_mid, col_right = st.columns([1, 1, 1])

        with col_left:
            if current_image_path:
                try:
                    image = Image.open(current_image_path)
                    st.markdown("<div class='image-container'>", unsafe_allow_html=True)
                    st.image(image, width=300)
                    st.markdown(
                        f"<div style='text-align: center; font-size: 14px; color: #666;'>{image_name}</div>",
                        unsafe_allow_html=True,
                    )
                    st.markdown("</div>", unsafe_allow_html=True)
                except Exception as e:
                    st.error(f"Unable to load image: {e}")
            else:
                st.warning(f"No image found for image ID: {current_dish_id}")

        with col_mid:
            display_model_predicted_ingredients(
                current_model_response, "gemini-2.5-pro"
            )

        with col_right:
            display_ground_truth_mass(current_ground_truth)

    else:
        st.error(f"Invalid page number: {current_page}. Total pages: {total_pages}")
        st.session_state.current_page = 0
        st.rerun()


def run_version7():
    main()


if __name__ == "__main__":
    run_version7()
