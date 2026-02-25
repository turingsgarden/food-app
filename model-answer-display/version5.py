import streamlit as st
import json
import os
from PIL import Image

def load_model_data():
    model_files = {"gemini-2.5-pro": "output/mass_prediction.json"}
    ground_truth_path = "Nutrition5k/metadata/dish_metadata_cafe1.json"
    
    model_data = {}
    available_models = []
    ground_truth_data = []

    # Load model prediction data
    for model_name, file_path in model_files.items():
        try:
            encodings = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252']
            loaded = False
            for encoding in encodings:
                try:
                    with open(file_path, 'r', encoding=encoding) as f:
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
        with open(ground_truth_path, 'r', encoding='utf-8') as f:
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
    image_extensions = ['.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp']
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
    # Build model prediction index (by dish_id)
    model_dish_mapping = {}
    for model_name in available_models:
        model_dish_mapping[model_name] = {}
        for item in model_data.get(model_name, []):
            dish_id = item.get("dish_id")
            if dish_id:
                model_dish_mapping[model_name][str(dish_id)] = item
    
    # Build ground truth index - 关键修复：根据image_filename提取dish_id
    ground_truth_mapping = {}
    for item in ground_truth_data:
        if isinstance(item, dict):
            # 从image_filename中提取dish_id
            if 'image_filename' in item:
                filename = item['image_filename']
                # 格式: dish_1234567890_rgb.png
                if filename.startswith('dish_') and '_rgb' in filename:
                    # 提取数字部分作为dish_id: dish_1234567890_rgb.png -> 1234567890
                    # 移除可能的扩展名
                    filename_without_ext = filename.split('.')[0]
                    parts = filename_without_ext.split('_')
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
            if filename.startswith('dish_') and '_rgb' in filename:
                # 提取dish_id: dish_1234567890_rgb.png -> 1234567890
                filename_without_ext = filename.split('.')[0]
                parts = filename_without_ext.split('_')
                if len(parts) >= 2 and parts[1].isdigit():
                    dish_id = parts[1]
                    image_mapping[dish_id] = img_path
    
    # 打印调试信息
    print(f"Built indices:")
    print(f"  - Model dishes: {len(model_dish_mapping.get('gemini-2.5-pro', {}))}")
    print(f"  - Ground truth dishes: {len(ground_truth_mapping)}")
    print(f"  - Image dishes: {len(image_mapping)}")
    
    # 打印一些dish_id示例
    if ground_truth_mapping:
        sample_ids = list(ground_truth_mapping.keys())[:5]
        print(f"  - Sample ground truth dish_ids: {sample_ids}")
        # 打印示例数据中的mass信息
        for dish_id in sample_ids:
            item = ground_truth_mapping[dish_id]
            if 'nutrition' in item and 'mass' in item['nutrition']:
                print(f"    Dish {dish_id}: mass = {item['nutrition']['mass']} g")
    
    return model_dish_mapping, ground_truth_mapping, image_mapping


    st.markdown(
        f"""
    <div class="model-container">
        {content_html}
    """,
        unsafe_allow_html=True,
    )
    
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

# def display_model_mass_prediction(response, model_name):
#     """Display model's mass prediction"""
#     if not response:
#         st.info("No model response available")
#         return
    
#     # Get analysis time
#     analysis_time_seconds = response.get("analysis_time_seconds")
#     analysis_time_formatted = response.get("analysis_time", format_analysis_time(analysis_time_seconds))
    
#     # Get mass estimation
#     mass_estimation = response.get("mass_estimation", {})
#     total_mass = mass_estimation.get("total_mass_g")
#     calculated_volume = mass_estimation.get("calculated_volume_cm3")
#     food_items = mass_estimation.get("food_items", [])
    
#     time_display = f"({analysis_time_formatted})" if analysis_time_formatted and analysis_time_formatted != "N/A" else ""
    
#     # Display total mass
#     total_mass_text = f"{total_mass:.1f} g" if total_mass is not None else "N/A"
    
#     # Display calculated volume
#     volume_text = f"{calculated_volume:.1f} cm³" if calculated_volume is not None else "N/A"
    
#     # Display food items (without confidence)
#     food_items_list = []
#     for item in food_items:
#         name = item.get("name", "Unknown")
#         mass = item.get("predicted_mass_g", 0)
#         food_items_list.append(f"• {name:<25} {mass:>8.1f} g")
    
#     food_items_text = "\n".join(food_items_list) if food_items_list else "No food items detected"
    
#     content_html = f"""
# <div class='model-content'>
# <div class='model-title'>{model_name} {time_display}</div>

# <div class='section-title'>Mass Prediction</div>
# <div class='content-box'>
# <strong>Total Mass:</strong> {total_mass_text}
# <strong>Calculated Volume:</strong> {volume_text}
# </div>

# <div class='section-title'>Food Items</div>
# <div class='content-box'>{food_items_text}</div>
# </div>
# """

#     st.markdown(
#         f"""
#     <div class="model-container">
#         {content_html}
#     """,
#         unsafe_allow_html=True,
#     )
def display_model_mass_prediction(response, model_name):
    """Display model's mass prediction"""
    if not response:
        st.info("No model response available")
        return
    
    # Get analysis time
    analysis_time_seconds = response.get("analysis_time_seconds")
    analysis_time_formatted = response.get("analysis_time", format_analysis_time(analysis_time_seconds))
    
    # Get mass estimation
    mass_estimation = response.get("mass_estimation", {})
    total_mass = mass_estimation.get("total_mass_g")
    calculated_volume = mass_estimation.get("calculated_volume_cm3")
    food_items = mass_estimation.get("food_items", [])
    
    time_display = f"({analysis_time_formatted})" if analysis_time_formatted and analysis_time_formatted != "N/A" else ""
    
    # Display total mass
    total_mass_text = f"{total_mass:.1f} g" if total_mass is not None else "N/A"
    
    # Display calculated volume
    volume_text = f"{calculated_volume:.1f} cm³" if calculated_volume is not None else "N/A"
    
    # Display food items (without confidence)
    food_items_list = []
    for item in food_items:
        name = item.get("name", "Unknown")
        mass = item.get("predicted_mass_g", 0)
        food_items_list.append(f"• {name:<25} {mass:>8.1f} g")
    
    food_items_text = "\n".join(food_items_list) if food_items_list else "No food items detected"
    
    content_html = f"""
<div class='model-content'>
<div class='model-title'>{model_name} {time_display}</div>

<div class='section-title'>Mass Prediction</div>
<div class='content-box'>
<strong>Total Mass:</strong> {total_mass_text}<br>
<strong>Calculated Volume:</strong> {volume_text}
</div>

<div class='section-title'>Food Items</div>
<div class='content-box'>{food_items_text}</div>
</div>
"""

    st.markdown(
        f"""
    <div class="model-container">
        {content_html}
    """,
        unsafe_allow_html=True,
    )

def display_ground_truth_mass(ground_truth):
    """Display ground truth mass information"""
    if not ground_truth:
        st.info("No ground truth available")
        return
    
    
    # Get ground truth mass from nutrition.mass
    ground_truth_mass = None
    if 'nutrition' in ground_truth and isinstance(ground_truth['nutrition'], dict):
        ground_truth_mass = ground_truth['nutrition'].get('mass')
    
    # Display ground truth mass
    mass_text = f"{ground_truth_mass:.1f} g" if ground_truth_mass is not None else "N/A"
    
    # Display ingredients if available
    ingredients_text = "N/A"
    if 'ingredients' in ground_truth and ground_truth['ingredients']:
        ingredients_list = []
        for ing in ground_truth['ingredients']:
            name = ing.get('name', 'Unknown')
            quantity = ing.get('quantity', 0)
            unit = ing.get('unit', 'g')
            ingredients_list.append(f"• {name:<25} {quantity:>8.1f} {unit}")
        ingredients_text = "\n".join(ingredients_list)
    
    content_html = f"""
<div class='model-content'>
<div class='ground-truth-title'>Ground Truth</div>

<div class='section-title'>Actual Mass</div>
<div class='content-box'>{mass_text}</div>

<div class='section-title'>Ingredients</div>
<div class='content-box'>{ingredients_text}</div>
</div>
"""

    st.markdown(
        f"""
    <div class="model-container">
        {content_html}
    """,
        unsafe_allow_html=True,
    )



def main():
    st.set_page_config(
        page_title="Food Mass Prediction Display",
        layout="wide"
    )
    
    # CSS styles - 修改这部分
    st.markdown("""
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
            border: 1px solid #e1e4e8;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 15px;
            background: white;
        }
        
        .section-title {
            font-weight: 600;
            font-size: 1.1em;
            color: #2c3e50;
            margin: 12px 0 6px 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        
        .content-box {
            white-space: pre-wrap;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            margin: 6px 0;
            padding: 10px;
            background: #f8f9fa;
            border-radius: 6px;
            line-height: 1.5;
            border: 1px solid #e1e4e8;
            font-size: 0.9em;
            color: #333;
        }
        
        .model-title {
            font-size: 1.3em;
            font-weight: 600;
            color: #1f77b4;
            margin-bottom: 15px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding-bottom: 10px;
            border-bottom: 2px solid #e1e4e8;
        }
        
        .ground-truth-title {
            font-size: 1.3em;
            font-weight: 600;
            color: #2ca02c;
            margin-bottom: 15px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding-bottom: 10px;
            border-bottom: 2px solid #e1e4e8;
        }
        
        .image-container {
            background: white;
            padding: 0 15px 10px 15px;   /* 去掉顶部 padding */
            border-radius: 8px;
            border: 1px solid #e1e4e8;
            margin-bottom: 10px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            text-align: center;
        }
        
        .centered-image {
            display: flex;
            justify-content: center;
            align-items: center;
            width: 100%;
        }
        
        .filename-text {
            text-align: center;
            margin-top: 10px;
            font-weight: 500;
        }
        
        .search-container {
            background: white;
            padding: 15px;
            border-radius: 8px;
            border: 1px solid #e1e4e8;
            margin-bottom: 15px;
        }
        
        /* 修复这个类 - 添加顶部边距避免与标题重叠 */
        .dish-id-display {
            font-size: 1.2em;
            font-weight: 600;
            color: #333;
            margin: 5px 0 8px 0;       /* 大幅减少上下间距 */
            text-align: center;
            padding: 6px 10px;         /* 减少 padding */
            background: #f8f9fa;
            border-radius: 6px;
            border: 1px solid #e1e4e8;
        }

        
        .nav-container {
            margin-bottom: 15px;
            padding: 10px;
            background: #f8f9fa;
            border-radius: 6px;
            border: 1px solid #e1e4e8;
        }
        
        .search-box {
            margin-bottom: 15px;
        }
        
        * {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
        }
        
        .error-box {
            background: #ffe6e6;
            padding: 10px;
            border-radius: 6px;
            margin: 5px 0;
            border-left: 4px solid #ff6b6b;
        }
        
        .success-box {
            background: #e6ffe6;
            padding: 10px;
            border-radius: 6px;
            margin: 5px 0;
            border-left: 4px solid #2ca02c;
        }
        
        /* 添加这个类来给主标题更多空间 */
        .main-title-container {
            margin-bottom: 20px;
        }
        
        /* 给所有容器添加一些内边距 */
        .stApp {
            padding-top: 10px;
        }
        
        /* 防止Streamlit的默认元素重叠 */
        .block-container {
            padding-top: 2rem;
            padding-bottom: 2rem;
        }
    </style>
    """, unsafe_allow_html=True)
    
    # Initialize session state
    if 'current_page' not in st.session_state:
        st.session_state.current_page = 0
    if 'search_dish_id' not in st.session_state:
        st.session_state.search_dish_id = ""
    if 'search_mode' not in st.session_state:
        st.session_state.search_mode = False
    if 'model_dish_mapping' not in st.session_state:
        st.session_state.model_dish_mapping = None
    if 'available_models' not in st.session_state:
        st.session_state.available_models = None
    if 'ground_truth_mapping' not in st.session_state:
        st.session_state.ground_truth_mapping = None
    if 'image_mapping' not in st.session_state:
        st.session_state.image_mapping = None
    if 'valid_images' not in st.session_state:
        st.session_state.valid_images = None
    if 'data_loaded' not in st.session_state:
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
                valid_images.append({
                    'dish_id': dish_id,
                    'image_path': img_path
                })
            
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
    
    # Title - 添加一个容器来更好地控制间距
    st.markdown("<div class='main-title-container'>", unsafe_allow_html=True)
    st.title("🍽️ Food Mass Prediction Display")
    st.markdown("</div>", unsafe_allow_html=True)
    
    # Search box
    with st.container():
        st.markdown("<div class='search-box'>", unsafe_allow_html=True)
        col1, col2, col3 = st.columns([3, 1, 1])
        
        with col1:
            search_input = st.text_input(
                "Search by Dish ID:",
                value=st.session_state.search_dish_id,
                placeholder="Enter dish ID (e.g., 1558113154)",
                key="dish_id_search_input"
            )
        
        with col2:
            if st.button("🔍 Search", use_container_width=True):
                if search_input.strip():
                    st.session_state.search_dish_id = search_input.strip()
                    st.session_state.search_mode = True
                    
                    # Find the dish in valid_images
                    found_index = -1
                    for i, item in enumerate(valid_images):
                        if item['dish_id'] == st.session_state.search_dish_id:
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
        
        st.markdown("</div>", unsafe_allow_html=True)
    
    # Navigation and pagination
    total_pages = len(valid_images)
    current_page = st.session_state.current_page
    
    if 0 <= current_page < total_pages:
        current_item = valid_images[current_page]
        current_dish_id = current_item['dish_id']
        current_image_path = current_item['image_path']
        image_name = os.path.basename(current_image_path)
        
        # Get current data
        current_model_response = find_model_response_by_dish_id(
            current_dish_id, model_dish_mapping, "gemini-2.5-pro"
        )
        current_ground_truth = find_ground_truth_by_dish_id(current_dish_id, ground_truth_mapping)
        
        # Display dish ID - 现在会有更多空间
        st.markdown(f"<div class='dish-id-display'>Dish ID: {current_dish_id} (Page {current_page + 1}/{total_pages})</div>", unsafe_allow_html=True)
        
        # Navigation controls
        with st.container():
            st.markdown("<div class='nav-container'>", unsafe_allow_html=True)
            
            nav_cols = st.columns([1, 1, 1, 1, 1, 1, 1])
            
            with nav_cols[0]:
                if st.button("⏮️ First", use_container_width=True):
                    st.session_state.current_page = 0
                    st.session_state.search_mode = False
                    st.rerun()
            
            with nav_cols[1]:
                if st.button("◀️ Prev", use_container_width=True, disabled=current_page <= 0):
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
                    key="page_jump_input"
                )
            
            with nav_cols[3]:
                if st.button("Go", use_container_width=True):
                    if 1 <= page_input <= total_pages:
                        st.session_state.current_page = page_input - 1
                        st.session_state.search_mode = False
                        st.rerun()
            
            with nav_cols[4]:
                if st.button("Next ▶️", use_container_width=True, disabled=current_page >= total_pages - 1):
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
            
            st.markdown("</div>", unsafe_allow_html=True)
        
        # Three-column layout
        col_left, col_mid, col_right = st.columns([1, 1, 1])
        
        with col_left:
            # Display image
            if current_image_path:
                try:
                    image = Image.open(current_image_path)
                    st.markdown("<div class='image-container'>", unsafe_allow_html=True)
                    st.markdown("<div class='centered-image'>", unsafe_allow_html=True)
                    st.image(image, width='stretch')
                    st.markdown("</div>", unsafe_allow_html=True)
                    st.markdown(f"<div class='filename-text'>{image_name}</div>", unsafe_allow_html=True)
                    st.markdown("</div>", unsafe_allow_html=True)
                except Exception as e:
                    st.error(f"Unable to load image: {e}")
            else:
                st.warning(f"No image found for dish ID: {current_dish_id}")
        
        with col_mid:
            # Display model prediction
            display_model_mass_prediction(current_model_response, "gemini-2.5-pro")
        
        with col_right:
            # Display ground truth
            display_ground_truth_mass(current_ground_truth)
    
    else:
        st.error(f"Invalid page number: {current_page}. Total pages: {total_pages}")
        st.session_state.current_page = 0
        st.rerun()


def run_version5():
    main()

if __name__ == "__main__":
    run_version5()      
