import streamlit as st
import json
import os
from PIL import Image
import glob

def load_model_data():
    model_files = {"gemini-2.5-pro": "output/Nutrition5k_Gemini-2.5-pro_pydantic_food_dataset_analysis.json"}
    ground_truth_path = "Nutrition5k/metadata/dish_metadata_cafe1.json"
    
    model_data = {}
    available_models = []
    ground_truth_data = []  

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
    

    basenames = [os.path.basename(f) for f in image_files]
    duplicates = [name for name in basenames if basenames.count(name) > 1]
    if duplicates:
        st.warning(f"Found duplicate files: {set(duplicates)}")
    
    return image_files

def build_image_index(model_data, available_models, ground_truth_data):
    image_has_response = set()
    model_file_mapping = {}
    
    for model_name in available_models:
        model_file_mapping[model_name] = {}
        for item in model_data.get(model_name, []):

            filename = os.path.basename(item.get("image_path", ""))
            model_file_mapping[model_name][filename] = item
            image_has_response.add(filename)
    

    ground_truth_mapping = {}
    for item in ground_truth_data:
        if isinstance(item, dict) and 'image_filename' in item:
            ground_truth_mapping[item['image_filename']] = item
    
    return image_has_response, model_file_mapping, ground_truth_mapping

def find_model_response_fast(image_path, model_file_mapping, model_name):
    if model_name not in model_file_mapping:
        return None
    filename = os.path.basename(image_path)
    return model_file_mapping[model_name].get(filename)

def find_ground_truth(image_path, ground_truth_mapping):

    if not ground_truth_mapping:
        return None
    filename = os.path.basename(image_path)
    return ground_truth_mapping.get(filename)

def format_analysis_time(seconds):
    if seconds is None:
        return "N/A"
    if seconds < 60:
        return f"{seconds:.1f}s"
    else:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m{remaining_seconds:.1f}s"

def display_model_response(response, model_name, page_num):
    if not response:
        return

    # Get analysis time
    analysis_time_seconds = response.get("analysis_time_seconds")
    analysis_time_formatted = response.get("analysis_time", format_analysis_time(analysis_time_seconds))
    
    dish_names = response.get("dish_names", [])
    visible_ingredients = response.get("visible_ingredients", [])
    hidden_ingredients = response.get("hidden_ingredients", [])
    nutrition = response.get("nutrition", {})

    dish_list = "\n".join([f"• {d}" for d in dish_names]) if dish_names else "N/A"
    
    time_display = f"({analysis_time_formatted})" if analysis_time_formatted and analysis_time_formatted != "N/A" else ""

    visible_list = []
    for ing in visible_ingredients:
        line = f"• {ing['name']:<20} {ing['quantity']:>6} {ing['unit']:<6}"
        visible_list.append(line)
    visible_text = "\n".join(visible_list) if visible_list else "N/A"
    
    hidden_list = []
    for i, ing in enumerate(hidden_ingredients):
        if isinstance(ing, dict):
            line = f"• {ing.get('name', ''):<20} {ing.get('quantity', ''):>6} {ing.get('unit', ''):<6}"
        else:
            line = f"• {repr(ing)}"
        hidden_list.append(line)
    
    hidden_text = "\n".join(hidden_list) if hidden_list else "N/A"
    
    nutri_lines = []
    nutri_units = {
        'calories': 'kcal',
        'protein': 'g',
        'fat': 'g',
        'carbohydrates': 'g',
        'fiber': 'g',
        'sugar': 'g',
        'sodium': 'mg'
    }
    
    for k, v in nutrition.items():
        unit = nutri_units.get(k, '')
        nutri_lines.append(f"• {k.capitalize():<15} {v} {unit}")
    nutrition_text = "\n".join(nutri_lines) if nutri_lines else "N/A"
    
    content_html = f"""
<div class='model-content'>
<div class='model-title'>{model_name}</div>

<div class='section-title'>Dish Prediction <span class='analysis-time'>{time_display}</span></div>
<div class='content-box'>{dish_list}</div>

<div class='section-title'>Visible Ingredients</div>
<div class='content-box'>{visible_text}</div>

<div class='section-title'>Hidden Ingredients</div>
<div class='content-box'>{hidden_text}</div>

<div class='section-title'>Nutrition Information</div>
<div class='content-box'>{nutrition_text}</div>
</div>
"""

    st.markdown(
        f"""
    <div class="model-container">
        {content_html}
    """,
        unsafe_allow_html=True,
    )

def display_ground_truth(ground_truth, page_num):
    if not ground_truth:
        return

    ingredients = ground_truth.get("ingredients", [])
    nutrition = ground_truth.get("nutrition", {})
    

    ingredient_list = []
    for ing in ingredients:
        line = f"• {ing['name']:<20} {ing['quantity']:>6} {ing['unit']:<6}"
        ingredient_list.append(line)
    ingredient_text = "\n".join(ingredient_list) if ingredient_list else "N/A"
    

    nutri_lines = []
    nutri_units = {
        'calories': 'kcal',
        'protein': 'g',
        'fat': 'g',
        'carbohydrates': 'g'
    }
    
    for k, v in nutrition.items():
        unit = nutri_units.get(k, '')
        nutri_lines.append(f"• {k.capitalize():<15} {v} {unit}")
    nutrition_text = "\n".join(nutri_lines) if nutri_lines else "N/A"
    
    content_html = f"""
<div class='model-content'>
<div class='ground-truth-title'>Ground Truth</div>

<div class='section-title'>Ingredients</div>
<div class='content-box'>{ingredient_text}</div>

<div class='section-title'>Nutrition Information</div>
<div class='content-box'>{nutrition_text}</div>
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
        page_title="Food Image Analysis Display",
        layout="wide"
    )
    
    # ... (CSS样式保持不变，与你的代码相同)
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
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 6px 0;
            padding: 10px;
            background: #f8f9fa;
            border-radius: 6px;
            line-height: 1.5;
            border: 1px solid #e1e4e8;
            font-size: 0.95em;
            color: #333;
        }
        
        .analysis-time {
            font-size: 1em !important;
            color: #666;
            margin-left: 8px;
            font-weight: 500;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
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
            padding: 15px;
            border-radius: 8px;
            border: 1px solid #e1e4e8;
            margin-bottom: 15px;
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
        
        .compact-nav {
            margin-bottom: 5px !important;
            padding: 0 !important;
        }
        .nav-button {
            height: 30px !important;
            min-height: 30px !important;
            padding: 0 6px !important;
            font-size: 11px !important;
            margin: 0 !important;
        }
        .nav-input {
            height: 30px !important;
            min-height: 30px !important;
            margin: 0 !important;
        }
        .nav-label {
            font-size: 11px !important;
            padding: 2px 0 !important;
            margin: 0 !important;
            text-align: center;
        }
        
        div[data-testid="stHorizontalBlock"] {
            gap: 0 !important;
            margin: 0 !important;
            padding: 0 !important;
        }
    
        div[data-testid="stVerticalBlock"] {
            gap: 0 !important;
            margin: 0 !important;
            padding: 0 !important;
        }
    
        .image-container {
            background: white;
            padding: 10px 10px 5px 10px;
            border-radius: 8px;
            border: 1px solid #e1e4e8;
            margin: 0 !important;
        }
        
        @media (max-height: 800px) {
            .model-container {
                min-height: 350px;
                padding: 12px;
            }
            .section-title {
                font-size: 1.05em;
                margin: 10px 0 5px 0;
            }
            .content-box {
                font-size: 0.9em;
                padding: 8px;
            }
        }
        
        @media (max-height: 600px) {
            .model-container {
                min-height: 300px;
                padding: 10px;
            }
            .section-title {
                font-size: 1em;
            }
            .content-box {
                font-size: 0.85em;
                padding: 6px;
            }
        }
                
        .left-column {
            display: flex;
            flex-direction: column;
            justify-content: center;  
            align-items: center;      
            height: 100%;
        }
        
        * {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
        }
    </style>
    """, unsafe_allow_html=True)
    
    if 'current_page' not in st.session_state:
        st.session_state.current_page = 0
    if 'valid_images' not in st.session_state:
        st.session_state.valid_images = None
    if 'model_file_mapping' not in st.session_state:
        st.session_state.model_file_mapping = None
    if 'available_models' not in st.session_state:
        st.session_state.available_models = None
    if 'ground_truth_mapping' not in st.session_state:
        st.session_state.ground_truth_mapping = None
    if 'data_loaded' not in st.session_state:
        st.session_state.data_loaded = False
    
    if not st.session_state.data_loaded:
        with st.spinner("Loading data..."):
            model_data, available_models, ground_truth_data = load_model_data()
            if not available_models:
                st.error("No model data found")
                return
            all_images = get_all_images()
            if not all_images:
                st.error("No images found")
                return
            image_has_response, model_file_mapping, ground_truth_mapping = build_image_index(model_data, available_models, ground_truth_data)
            valid_images = [img for img in all_images if os.path.basename(img) in image_has_response]
            
            st.session_state.valid_images = valid_images
            st.session_state.model_file_mapping = model_file_mapping
            st.session_state.available_models = available_models
            st.session_state.ground_truth_mapping = ground_truth_mapping
            st.session_state.data_loaded = True
    
    valid_images = st.session_state.valid_images
    model_file_mapping = st.session_state.model_file_mapping
    available_models = st.session_state.available_models
    ground_truth_mapping = st.session_state.ground_truth_mapping
    
    if not valid_images:
        st.warning("No valid images with responses.")
        return
    
    total_pages = len(valid_images)
    current_page = st.session_state.current_page
    current_image_path = valid_images[current_page]
    image_name = os.path.basename(current_image_path)
    
    current_responses = {m: find_model_response_fast(current_image_path, model_file_mapping, m) for m in available_models if find_model_response_fast(current_image_path, model_file_mapping, m)}
    current_ground_truth = find_ground_truth(current_image_path, ground_truth_mapping)
    
    with st.container():
        model_names = list(current_responses.keys())
        

        col_left, col_mid, col_right = st.columns([1, 1, 1])
        
        with col_left:

            nav_cols = st.columns([1.5, 1, 1, 1, 1])
            
            with nav_cols[0]:
                st.markdown(f"<div class='nav-label'>{current_page+1}/{total_pages}</div>", unsafe_allow_html=True)
            
            with nav_cols[1]:
                page_input = st.number_input(
                    "Page", 
                    min_value=1, 
                    max_value=total_pages, 
                    value=current_page+1,
                    label_visibility="collapsed",
                    key=f"page_jump_{current_page}"
                )
            
            with nav_cols[2]:
                if st.button("Go", width='stretch', key=f"jump_btn_{current_page}"):
                    if 1 <= page_input <= total_pages:
                        st.session_state.current_page = page_input-1
                        st.rerun()
            
            with nav_cols[3]:
                if st.button("◀", width='stretch', disabled=current_page<=0, key=f"prev_{current_page}"):
                    st.session_state.current_page -= 1
                    st.rerun()
            
            with nav_cols[4]:
                if st.button("▶", width='stretch', disabled=current_page>=total_pages-1, key=f"next_{current_page}"):
                    st.session_state.current_page += 1
                    st.rerun()
            
            st.markdown("<div class='left-column'>", unsafe_allow_html=True)
            st.markdown("<div class='image-container'>", unsafe_allow_html=True)
            try:
                image = Image.open(current_image_path)
                st.markdown("<div class='centered-image'>", unsafe_allow_html=True)
                st.image(image, width='stretch')
                st.markdown("</div>", unsafe_allow_html=True)
                st.markdown(f"<div class='filename-text'>Filename: {image_name}</div>", unsafe_allow_html=True)
            except:
                st.error("Unable to load image")
            st.markdown("</div>", unsafe_allow_html=True)
            st.markdown("</div>", unsafe_allow_html=True)

        with col_mid:
            if "gemini-2.5-pro" in current_responses:
                display_model_response(current_responses["gemini-2.5-pro"], "gemini-2.5-pro", current_page)
            else:
                st.info("No model response available")

        with col_right:
            if current_ground_truth:
                display_ground_truth(current_ground_truth, current_page)
            else:
                st.info("No ground truth available")

def run_version3():
    
    main()




