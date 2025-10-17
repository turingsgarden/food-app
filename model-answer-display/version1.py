import streamlit as st
import json
import os
import glob
from PIL import Image

# -------------------------------
# 🔹 加载模型 JSON 数据
# -------------------------------
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
        except FileNotFoundError:
            continue
    return model_data, available_models

# -------------------------------
# 🔹 获取图片
# -------------------------------
def get_all_images():
    image_dir = "food-101_100images"
    image_files = glob.glob(os.path.join(image_dir, "*.jpg"))
    image_files.sort()
    return image_files if image_files else None

# -------------------------------
# 🔹 构建图片索引
# -------------------------------
def build_image_index(model_data, available_models):
    image_has_response = set()
    model_file_mapping = {}
    for model_name in available_models:
        model_file_mapping[model_name] = {}
        for item in model_data.get(model_name, []):
            filename = os.path.basename(item.get("image_path", ""))
            model_file_mapping[model_name][filename] = item
            image_has_response.add(filename)
    return image_has_response, model_file_mapping

# -------------------------------
# 🔹 快速查找模型 response
# -------------------------------
def find_model_response_fast(image_path, model_file_mapping, model_name):
    if model_name not in model_file_mapping:
        return None
    filename = os.path.basename(image_path)
    return model_file_mapping[model_name].get(filename)

# -------------------------------
# 🔹 格式化配料文本
# -------------------------------
def format_ingredients_text(text):
    if not text or text == "N/A":
        return "N/A"

    # list -> dict 格式化
    if isinstance(text, list):
        formatted_items = []
        for item in text:
            if isinstance(item, dict):
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
                formatted_lines.append(f"• {parts[0]:<25} {parts[1]:>6} {parts[2]:<6} {parts[3]}")
            else:
                formatted_lines.append(f"• {line}")
    return '\n'.join(formatted_lines)

# -------------------------------
# 🔹 格式化营养信息
# -------------------------------
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
                formatted_lines.append(f"• {nutrient:<18} {value:>8} {unit}")
            else:
                formatted_lines.append(f"• {line}")
    return '\n'.join(formatted_lines)

# -------------------------------
# 🔹 显示模型输出
# -------------------------------
def display_model_response(response, model_name, page_num):
    if not response:
        return

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
    except:
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
    st.markdown(f"<div style='height: 650px; overflow-y: auto; border: 1px solid #e1e4e8; border-radius: 8px; padding: 15px;'>{content_html}</div>", unsafe_allow_html=True)

# -------------------------------
# 🔹 主逻辑
# -------------------------------
def main():
    # 初始化 session_state
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
    current_page = st.session_state.current_page

    if not valid_images:
        st.warning("No valid images with responses.")
        return

    current_image_path = valid_images[current_page]
    image_name = os.path.basename(current_image_path)

    # ✅ 构建当前模型 response
    current_responses = {}
    for m in available_models:
        resp = find_model_response_fast(current_image_path, model_file_mapping, m)
        if resp:
            current_responses[m] = resp

    # 三列显示
    col_left, col_mid, col_right = st.columns([1,1,1])
    with col_left:
        st.markdown("<br><br>", unsafe_allow_html=True)
        try:
            image = Image.open(current_image_path)
            st.image(image, width='stretch')
        except:
            st.error("Unable to load image")
        st.write(f"**Filename:** {image_name}")

    if "gemini-2.5-pro" in current_responses:
        with col_mid:
            display_model_response(current_responses["gemini-2.5-pro"], "gemini-2.5-pro", current_page)
    if "gemini-2.5-flash" in current_responses:
        with col_right:
            display_model_response(current_responses["gemini-2.5-flash"], "gemini-2.5-flash", current_page)

# -------------------------------
# 🔹 运行版本1
# -------------------------------
def run_version1():
    st.set_page_config(page_title="Food Image Analysis Display", layout="wide")
    main()
