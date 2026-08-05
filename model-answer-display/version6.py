import streamlit as st
import json
import os
from PIL import Image


def load_model_data():
    """Load new prediction data from new JSON file and ground truth from metadata"""
    # Use the new prediction file
    model_files = {
        "gemini-2.5-pro": "output/Nutrition5k_Gemini-2.5-pro_pydantic_food_dataset_analysis_1.json"
    }
    ground_truth_path = "Nutrition5k/metadata/dish_metadata_cafe1.json"

    model_data = {}
    available_models = []
    ground_truth_data = []

    # Load model prediction data
    for model_name, file_path in model_files.items():
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

    # Load ground truth data
    try:
        with open(ground_truth_path, "r", encoding="utf-8") as f:
            ground_truth_data = json.load(f)
        st.success(f"Loaded {len(ground_truth_data)} ground truth records")
    except FileNotFoundError:
        st.error(f"Ground truth file not found: {ground_truth_path}")
    except Exception as e:
        st.error(f"Error loading ground truth: {e}")

    return model_data, available_models, ground_truth_data


def get_all_images():
    """Get all image paths, support multiple formats"""
    image_dir = "Nutrition5k/Nutrition5K-300"

    if not os.path.exists(image_dir):
        st.error(f"Directory does not exist: {image_dir}")
        return None

    all_files = os.listdir(image_dir)
    image_extensions = [".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"]
    image_files = []

    for file in all_files:
        file_lower = file.lower()
        if any(file_lower.endswith(ext) for ext in image_extensions):
            full_path = os.path.join(image_dir, file)
            image_files.append(full_path)

    if not image_files:
        st.error(f"No image files found in: {image_dir}")
        return None

    image_files.sort()
    return image_files


def build_indices(model_data, available_models, ground_truth_data):
    """Build indices for fast lookup"""
    # Build model prediction index (by image_filename first, then extract dish_id)
    model_dish_mapping = {}
    for model_name in available_models:
        model_dish_mapping[model_name] = {}
        for item in model_data.get(model_name, []):
            # The new JSON uses image_filename
            image_filename = item.get("image_filename")
            if image_filename:
                # Extract dish_id from image_filename
                # Format: dish_1234567890.jpg -> 1234567890
                filename_without_ext = image_filename.split(".")[0]
                parts = filename_without_ext.split("_")
                if len(parts) >= 2 and parts[1].isdigit():
                    dish_id = parts[1]
                    model_dish_mapping[model_name][str(dish_id)] = item

    # Build ground truth index - extract dish_id from image_filename
    ground_truth_mapping = {}
    for item in ground_truth_data:
        if isinstance(item, dict):
            # Extract dish_id from image_filename
            if "image_filename" in item:
                filename = item["image_filename"]
                # Format: dish_1234567890_rgb.png
                if filename.startswith("dish_") and "_rgb" in filename:
                    # Extract numeric part: dish_1234567890_rgb.png -> 1234567890
                    filename_without_ext = filename.split(".")[0]
                    parts = filename_without_ext.split("_")
                    if len(parts) >= 2 and parts[1].isdigit():
                        dish_id = parts[1]
                        ground_truth_mapping[dish_id] = item
                        print(f"Mapped dish_id: {dish_id} from filename: {filename}")

    # Build image path index (by dish_id)
    image_files = get_all_images()
    image_mapping = {}
    if image_files:
        for img_path in image_files:
            filename = os.path.basename(img_path)
            # Try to extract dish_id from filename
            # Support formats: dish_1234567890_rgb.png
            if filename.startswith("dish_") and "_rgb" in filename:
                # Extract dish_id: dish_1234567890_rgb.png -> 1234567890
                filename_without_ext = filename.split(".")[0]
                parts = filename_without_ext.split("_")
                if len(parts) >= 2 and parts[1].isdigit():
                    dish_id = parts[1]
                    image_mapping[dish_id] = img_path

    # Print debug information
    print("Built indices:")
    print(f"  - Model dishes: {len(model_dish_mapping.get('gemini-2.5-pro', {}))}")
    print(f"  - Ground truth dishes: {len(ground_truth_mapping)}")
    print(f"  - Image dishes: {len(image_mapping)}")

    # Print some sample dish_ids
    if ground_truth_mapping:
        sample_ids = list(ground_truth_mapping.keys())[:5]
        print(f"  - Sample ground truth dish_ids: {sample_ids}")

    return model_dish_mapping, ground_truth_mapping, image_mapping


def find_model_response_by_dish_id(dish_id, model_dish_mapping, model_name):
    """Find model response by dish_id"""
    if model_name not in model_dish_mapping:
        return None
    return model_dish_mapping[model_name].get(str(dish_id))


def find_ground_truth_by_dish_id(dish_id, ground_truth_mapping):
    """Find ground truth by dish_id"""
    if not dish_id:
        return None
    return ground_truth_mapping.get(str(dish_id))


def find_image_by_dish_id(dish_id, image_mapping):
    """Find image path by dish_id"""
    if not dish_id:
        return None
    return image_mapping.get(str(dish_id))


def format_analysis_time(seconds):
    """Format analysis time"""
    if seconds is None:
        return "N/A"
    if seconds < 60:
        return f"{seconds:.1f}s"
    else:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m{remaining_seconds:.1f}s"


def display_model_predicted_ingredients(response, model_name):
    """Display model's predicted ingredients (visible and hidden)"""
    if not response:
        st.info("No model response available")
        return

    st.subheader(f"🤖 {model_name} Predictions")

    # Get visible and hidden ingredients
    visible_ingredients = response.get("visible_ingredients", [])
    hidden_ingredients = response.get("hidden_ingredients", [])

    # Calculate totals
    visible_total = sum(item.get("quantity", 0) for item in visible_ingredients)
    hidden_total = sum(item.get("quantity", 0) for item in hidden_ingredients)

    # Display visible ingredients
    st.markdown("**Visible Ingredients:**")
    if visible_ingredients:
        visible_text = "\n".join(
            [
                f"• {item.get('name', 'Unknown'):<30} {item.get('quantity', 0):>8.1f} g"
                for item in visible_ingredients
            ]
        )
        st.code(visible_text)
        st.metric("Visible Total", f"{visible_total:.1f} g")
    else:
        st.info("No visible ingredients detected")

    st.markdown("---")

    # Display hidden ingredients
    st.markdown("**Hidden Ingredients:**")
    if hidden_ingredients:
        hidden_text = "\n".join(
            [
                f"• {item.get('name', 'Unknown'):<30} {item.get('quantity', 0):>8.1f} g"
                for item in hidden_ingredients
            ]
        )
        st.code(hidden_text)
        st.metric("Hidden Total", f"{hidden_total:.1f} g")
    else:
        st.info("No hidden ingredients detected")

    st.markdown("---")

    # Display totals
    col1, col2, col3 = st.columns(3)
    with col1:
        st.metric("Visible Weight", f"{visible_total:.1f} g")
    with col2:
        st.metric("Hidden Weight", f"{hidden_total:.1f} g")
    with col3:
        st.metric("Grand Total", f"{visible_total + hidden_total:.1f} g")


def display_ground_truth_mass(ground_truth):
    """Display ground truth mass information"""
    if not ground_truth:
        st.info("No ground truth available")
        return

    st.subheader("📊 Ground Truth")

    # Get ground truth mass from nutrition.mass
    ground_truth_mass = None
    if "nutrition" in ground_truth and isinstance(ground_truth["nutrition"], dict):
        ground_truth_mass = ground_truth["nutrition"].get("mass")

    # Display ground truth mass
    mass_text = f"{ground_truth_mass:.1f} g" if ground_truth_mass is not None else "N/A"
    st.metric("Actual Mass", mass_text)

    st.markdown("---")

    # Display ingredients if available
    st.markdown("**Ingredients:**")
    if ground_truth.get("ingredients"):
        ingredients_list = []
        total_ingredient_mass = 0
        for ing in ground_truth["ingredients"]:
            name = ing.get("name", "Unknown")
            quantity = ing.get("quantity", 0)
            unit = ing.get("unit", "g")
            ingredients_list.append(f"• {name:<30} {quantity:>8.1f} {unit}")
            if unit == "g":
                total_ingredient_mass += quantity

        ingredients_text = "\n".join(ingredients_list)
        st.code(ingredients_text)
        st.metric("Total Ingredients Weight", f"{total_ingredient_mass:.1f} g")
    else:
        st.info("No ingredients data available")


def main():
    st.set_page_config(page_title="Food Mass Prediction Display", layout="wide")

    # CSS styles
    st.markdown(
        """
    <style>
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
            padding: 10px;
            border-radius: 5px;
            margin-bottom: 10px;
            white-space: pre-wrap;
            word-wrap: break-word;
            font-family: monospace;
            font-size: 12px;
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
            model_data, available_models, ground_truth_data = load_model_data()
            if not available_models:
                st.error("No model data found")
                return

            model_dish_mapping, ground_truth_mapping, image_mapping = build_indices(
                model_data, available_models, ground_truth_data
            )

            # Create list of valid images for pagination
            valid_images = []
            for dish_id, img_path in image_mapping.items():
                valid_images.append({"dish_id": dish_id, "image_path": img_path})

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
        st.warning("No valid images with responses.")
        return

    # Title
    st.markdown("<div class='main-title-container'>", unsafe_allow_html=True)
    st.title("🍽️ Food Ingredient Prediction Display")
    st.markdown("</div>", unsafe_allow_html=True)

    # Search box
    with st.container():
        col1, col2, col3 = st.columns([3, 1, 1])

        with col1:
            search_input = st.text_input(
                "Search by Dish ID:",
                value=st.session_state.search_dish_id,
                placeholder="Enter dish ID (e.g., 1561662216)",
                key="dish_id_search_input",
            )

        with col2:
            if st.button("🔍 Search", use_container_width=True):
                if search_input.strip():
                    st.session_state.search_dish_id = search_input.strip()
                    st.session_state.search_mode = True

                    # Find the dish in valid_images
                    found_index = -1
                    for i, item in enumerate(valid_images):
                        if item["dish_id"] == st.session_state.search_dish_id:
                            found_index = i
                            break

                    if found_index >= 0:
                        st.session_state.current_page = found_index
                        st.success(f"Found dish ID: {st.session_state.search_dish_id}")
                    else:
                        st.error(f"Dish ID {st.session_state.search_dish_id} not found")
                else:
                    st.session_state.search_mode = False

        with col3:
            if st.button("📄 Clear Search", use_container_width=True):
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
        image_name = os.path.basename(current_image_path)

        # Get current data
        current_model_response = find_model_response_by_dish_id(
            current_dish_id, model_dish_mapping, "gemini-2.5-pro"
        )
        current_ground_truth = find_ground_truth_by_dish_id(
            current_dish_id, ground_truth_mapping
        )

        # Display dish ID
        st.markdown(
            f"<div class='dish-id-display'>Dish ID: {current_dish_id} (Page {current_page + 1}/{total_pages})</div>",
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
                # Display current position
                st.markdown(f"**{current_page + 1}/{total_pages}**")

        # Three-column layout
        col_left, col_mid, col_right = st.columns([1, 1, 1])

        with col_left:
            # Display image
            if current_image_path:
                try:
                    image = Image.open(current_image_path)
                    st.markdown("<div class='image-container'>", unsafe_allow_html=True)
                    st.image(image, width=300)
                    st.markdown(
                        f"<div style='text-align: center; font-size: 12px; color: #666;'>{image_name}</div>",
                        unsafe_allow_html=True,
                    )
                    st.markdown("</div>", unsafe_allow_html=True)
                except Exception as e:
                    st.error(f"Unable to load image: {e}")
            else:
                st.warning(f"No image found for dish ID: {current_dish_id}")

        with col_mid:
            # Display model prediction
            display_model_predicted_ingredients(
                current_model_response, "gemini-2.5-pro"
            )

        with col_right:
            # Display ground truth
            display_ground_truth_mass(current_ground_truth)

    else:
        st.error(f"Invalid page number: {current_page}. Total pages: {total_pages}")
        st.session_state.current_page = 0
        st.rerun()


def run_version6():
    main()


if __name__ == "__main__":
    run_version6()
