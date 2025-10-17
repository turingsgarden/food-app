import streamlit as st
import json
import os
from PIL import Image
import glob


def load_model_data():
    model_files = {
        "gemini-2.5-flash": "output/Gemini-2.5-flash_food-101_analysis.json",
        "gemini-2.5-pro": "output/Gemini-2.5-pro_food-101_analysis.json"
    }
    
    model_data = {}
    available_models = []
    
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
                pass
        except FileNotFoundError:
            pass
        except Exception:
            pass
    return model_data, available_models

def get_all_images():
    image_dir = "food-101_100images"
    image_files = glob.glob(os.path.join(image_dir, "*.jpg"))
    if not image_files:
        return None
    image_files.sort()
    return image_files

def build_image_index(model_data, available_models):
    image_has_response = set()
    model_file_mapping = {}
    for model_name in available_models:
        model_file_mapping[model_name] = {}
        for item in model_data.get(model_name, []):
            raw_path = item.get("image_path", "")
            filename = os.path.basename(raw_path.replace("\\", "/")) 
            model_file_mapping[model_name][filename] = item
            image_has_response.add(filename)

        print(f"DEBUG - {model_name} loaded {len(model_file_mapping[model_name])} items.")
        print(f"DEBUG - Example filenames: {list(model_file_mapping[model_name].keys())[:5]}")
    return image_has_response, model_file_mapping


def find_model_response_fast(image_path, model_file_mapping, model_name):
    if model_name not in model_file_mapping:
        return None
    filename = os.path.basename(image_path)
    return model_file_mapping[model_name].get(filename)

def format_ingredients_text(text):
    if not text or text == "N/A":
        return "N/A"

   
    if isinstance(text, list):
        formatted_items = []
        for item in text:
            if isinstance(item, dict):
                # 假设 dict 里有 name, amount, unit, note 字段
                name = item.get("name", "")
                amount = item.get("amount", "")
                unit = item.get("unit", "")
                note = item.get("note", "")
                formatted_items.append(f"{name} | {amount} | {unit} | {note}")
            else:
                
                formatted_items.append(str(item))
        text = "\n".join(formatted_items)
    
    lines = text.split('\n')
    formatted_lines = []

    for line in lines:
        line = line.strip()
        if line:
            if '|' in line:
                parts = [p.strip() for p in line.split('|')]
                while len(parts) < 4:
                    parts.append('')
                formatted_line = f"• {parts[0]:<25} {parts[1]:>6} {parts[2]:<6} {parts[3]}"
                formatted_lines.append(formatted_line)
            else:
                formatted_lines.append(f"• {line}")

    return '\n'.join(formatted_lines)


def format_nutrition_text(text):
    if not text or text == "N/A":
        return "N/A"
    
    lines = text.split('\n')
    formatted_lines = []
    
    for line in lines:
        line = line.strip()
        if line:
            if '|' in line:
                parts = [p.strip() for p in line.split('|')]
                nutrient = parts[0]
                value = parts[1]
                unit = parts[2] if len(parts) > 2 else ""
                formatted_line = f"• {nutrient:<18} {value:>8} {unit}"
                formatted_lines.append(formatted_line)
            else:
                formatted_lines.append(f"• {line}")
    
    return '\n'.join(formatted_lines)

def display_model_response(response, model_name, page_num):
    if not response:
        return
    
    #show model name
    st.markdown(f"<h4 style='margin-top:0; margin-bottom:10px;'>{model_name}</h4>", unsafe_allow_html=True)
    
    section_style = "font-weight:bold; font-size:16px; color:#1f77b4; margin: 15px 0 8px 0;"
    content_style = "white-space: pre; font-family: 'Courier New', monospace; margin: 8px 0; padding: 8px; background: #f8f9fa; border-radius: 4px; line-height: 1.4; border: 1px solid #e1e4e8;"
    
    analysis_time = response.get("analysis_time", "N/A")
    
    try:
        if analysis_time not in ("N/A", None):
           
            time_value = float(str(analysis_time).replace("s", "").strip())
            time_text = f" ({time_value:.2f}s)"
        else:
            time_text = ""
    except Exception:
        time_text = ""
    
    dish_prediction = response.get("dish_prediction", "N/A")
    image_description = response.get("image_description", "N/A")
    hidden_ingredients = response.get("hidden_ingredients", "N/A")
    nutrition_info = response.get("nutrition_info", "N/A")
    
    formatted_description = format_ingredients_text(image_description)
    formatted_hidden = format_ingredients_text(hidden_ingredients)
    formatted_nutrition = format_nutrition_text(nutrition_info)
    
    
    content_html = f"""
<div style='margin-bottom:15px;'>

<div style='{section_style}'>Dish Prediction{time_text}</div>
<div style='{content_style}'>{dish_prediction if dish_prediction != 'N/A' else 'N/A'}</div>

<div style='{section_style}'>Image Description</div>
<div style='{content_style}'>{formatted_description}</div>

<div style='{section_style}'>Hidden Ingredients</div>
<div style='{content_style}'>{formatted_hidden}</div>

<div style='{section_style}'>Nutrition Information</div>
<div style='{content_style}'>{formatted_nutrition}</div>

</div>
"""
    
    
    st.markdown(f"""
    <div style="height: 650px; overflow-y: auto; border: 1px solid #e1e4e8; border-radius: 8px; padding: 15px;">
        {content_html}

    """, unsafe_allow_html=True)

def main():
    if 'current_page' not in st.session_state:
        st.session_state.current_page = 0
    if 'valid_images' not in st.session_state:
        st.session_state.valid_images = None
    if 'model_file_mapping' not in st.session_state:
        st.session_state.model_file_mapping = None
    if 'available_models' not in st.session_state:
        st.session_state.available_models = None
    if 'data_loaded' not in st.session_state:
        st.session_state.data_loaded = False
    
    if not st.session_state.data_loaded:
        with st.spinner("Loading data..."):
            model_data, available_models = load_model_data()
            if not available_models:
                st.error("No model data found")
                return
            all_images = get_all_images()
            if not all_images:
                st.error("No images found")
                return
            image_has_response, model_file_mapping = build_image_index(model_data, available_models)
            valid_images = [img for img in all_images if os.path.basename(img) in image_has_response]
            
            st.session_state.valid_images = valid_images
            st.session_state.model_file_mapping = model_file_mapping
            st.session_state.available_models = available_models
            st.session_state.data_loaded = True
    
    valid_images = st.session_state.valid_images
    model_file_mapping = st.session_state.model_file_mapping
    available_models = st.session_state.available_models
    
    if not valid_images:
        st.warning("No valid images with responses.")
        return
    
    total_pages = len(valid_images)
    current_page = st.session_state.current_page
    current_image_path = valid_images[current_page]
    image_name = os.path.basename(current_image_path)
    
    current_responses = {m: find_model_response_fast(current_image_path, model_file_mapping, m) for m in available_models if find_model_response_fast(current_image_path, model_file_mapping, m)}
    
   
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

        st.markdown("<br><br>", unsafe_allow_html=True)  
        st.markdown("<br><br>", unsafe_allow_html=True) 
        try:
            image = Image.open(current_image_path)
            st.image(image, width='stretch')
        except:
            st.error("Unable to load image")
        st.write(f"**Filename:** {image_name}")
    
    model_names = list(current_responses.keys())

    if "gemini-2.5-pro" in current_responses:
        with col_mid:
            display_model_response(current_responses["gemini-2.5-pro"], "gemini-2.5-pro", current_page)

    if "gemini-2.5-flash" in current_responses:
        with col_right:
            display_model_response(current_responses["gemini-2.5-flash"], "gemini-2.5-flash", current_page)


def run_version1():
    st.set_page_config(
        page_title="Food Image Analysis Display",
        layout="wide"
    )


    st.markdown("""
    <style>
        /* 整体页面布局优化 */
        .main .block-container {
            padding: 1rem 2rem 5rem !important;
            max-width: 95% !important;
        }

        /* 三列布局：左图居中，两侧模型结果 */
        .image-container {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            text-align: center;
            height: 100%;
        }

        .filename-text {
            margin-top: 10px;
            font-size: 14px;
            color: #555;
        }

        /* 模型输出框滚动样式 */
        .model-response-box {
            height: 650px;
            overflow-y: auto;
            border: 1px solid #e1e4e8;
            border-radius: 8px;
            padding: 15px;
            background: #fafafa;
        }

        /* 导航栏样式 */
        .nav-bar {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 0.5rem;
            margin-bottom: 0.5rem;
        }

        .nav-label {
            font-size: 14px;
            font-weight: bold;
            color: #333;
            padding: 8px 0;
            text-align: center;
        }

        /* 让 Streamlit 默认容器自适应 */
        div[data-testid="stHorizontalBlock"] {
            align-items: flex-start !important;
        }

        /* 调整左右栏内容对齐 */
        [data-testid="stVerticalBlock"] {
            display: flex;
            flex-direction: column;
            justify-content: flex-start;
        }

    </style>
    """, unsafe_allow_html=True)

   
    main()
