import streamlit as st
import json
import os
from PIL import Image
import glob

# 移除模块级的 st.set_page_config()
# 将 CSS 样式移到函数内部

def load_model_data():
    # 保持不变
    model_files = {
        "gemini-2.5-flash": "output/Gemini-2.5-flash_pydantic_food_dataset_analysis.json",
        "gemini-2.5-pro": "output/Gemini-2.5-pro_pydantic_food_dataset_analysis.json"
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
    # 保持不变
    image_dir = "food-101_100images"
    image_files = glob.glob(os.path.join(image_dir, "*.jpg"))
    if not image_files:
        return None
    image_files.sort()
    return image_files

def build_image_index(model_data, available_models):
    # 保持不变
    image_has_response = set()
    model_file_mapping = {}
    for model_name in available_models:
        model_file_mapping[model_name] = {}
        for item in model_data.get(model_name, []):
            filename = os.path.basename(item.get("image_path", ""))
            model_file_mapping[model_name][filename] = item
            image_has_response.add(filename)
    return image_has_response, model_file_mapping

def find_model_response_fast(image_path, model_file_mapping, model_name):
    # 保持不变
    if model_name not in model_file_mapping:
        return None
    filename = os.path.basename(image_path)
    return model_file_mapping[model_name].get(filename)

def format_analysis_time(seconds):
    # 保持不变
    if seconds is None:
        return "N/A"
    if seconds < 60:
        return f"{seconds:.1f}s"
    else:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m{remaining_seconds:.1f}s"

def display_model_response(response, model_name, page_num):
    # 使用你提供的修复版本
    if not response:
        return

    # Get analysis time
    analysis_time_seconds = response.get("analysis_time_seconds")
    analysis_time_formatted = response.get("analysis_time", format_analysis_time(analysis_time_seconds))
    
    # 基本字段
    dish_names = response.get("dish_names", [])
    visible_ingredients = response.get("visible_ingredients", [])
    hidden_ingredients = response.get("hidden_ingredients", [])
    nutrition = response.get("nutrition", {})
    console_output = response.get("console_output", "N/A")
    success = response.get("success", False)

    # 菜品名称
    dish_list = "\n".join([f"• {d}" for d in dish_names]) if dish_names else "N/A"
    
    # 时间显示
    time_display = f"({analysis_time_formatted})" if analysis_time_formatted and analysis_time_formatted != "N/A" else ""

    # 可见食材
    visible_list = []
    for ing in visible_ingredients:
        line = f"• {ing['name']:<20} {ing['quantity']:>6} {ing['unit']:<6}"
        visible_list.append(line)
    visible_text = "\n".join(visible_list) if visible_list else "N/A"

    # 隐藏食材 - 使用修复版本
    hidden_list = []
    for i, ing in enumerate(hidden_ingredients):
        if isinstance(ing, dict):
            line = f"• {ing.get('name', ''):<20} {ing.get('quantity', ''):>6} {ing.get('unit', ''):<6}"
        else:
            # 如果不是字典，说明数据格式有问题
            line = f"• {repr(ing)}"
        hidden_list.append(line)
    
    hidden_text = "\n".join(hidden_list) if hidden_list else "N/A"

    # 营养成分
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

    # 使用改进的HTML结构
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

def main():
    # 在函数内部设置页面配置
    st.set_page_config(
        page_title="Food Image Analysis Display",
        layout="wide"
    )
    
    # 在函数内部添加 CSS 样式
    st.markdown("""
    <style>
        /* 你的所有 CSS 样式代码 */
        .main-container { min-height: 100vh; width: 100%; }
        .model-container { height: auto !important; min-height: 400px; max-height: none !important; overflow: visible !important; border: 1px solid #e1e4e8; border-radius: 8px; padding: 15px; margin-bottom: 15px; background: white; }
        /* ... 其余 CSS 样式 ... */
    </style>
    """, unsafe_allow_html=True)
    
    # 原有的 main() 函数内容保持不变
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
    
    # 使用容器包装整个内容区域
    with st.container():
        model_names = list(current_responses.keys())
        
        # 根据屏幕宽度和模型数量动态调整布局
        if len(model_names) == 2:
            # 有两个模型时，使用1:1:1的三列布局
            col_left, col_mid, col_right = st.columns([1, 1, 1])
            
            with col_left:
                # 在图片列上方添加紧凑导航栏 - 使用更紧凑的布局
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
                
                # 图片列 - 使用居中的图片容器
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
            
            # 模型回答列 - 直接显示，没有空白
            if "gemini-2.5-pro" in current_responses:
                with col_mid:
                    display_model_response(current_responses["gemini-2.5-pro"], "gemini-2.5-pro", current_page)

            if "gemini-2.5-flash" in current_responses:
                with col_right:
                    display_model_response(current_responses["gemini-2.5-flash"], "gemini-2.5-flash", current_page)
                    
        elif len(model_names) == 1:
            # 只有一个模型时，使用1:2的两列布局
            col_left, col_model = st.columns([1, 2])
            
            with col_left:
                # 在图片列上方添加紧凑导航栏 - 使用更紧凑的布局
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
                
                # 图片列 - 使用居中的图片容器
                st.markdown("<div class='image-container'>", unsafe_allow_html=True)
                try:
                    image = Image.open(current_image_path)
                    # 使用居中的图片显示
                    st.markdown("<div class='centered-image'>", unsafe_allow_html=True)
                    st.image(image, width='stretch')
                    st.markdown("</div>", unsafe_allow_html=True)
                    # 居中的文件名
                    st.markdown(f"<div class='filename-text'>Filename: {image_name}</div>", unsafe_allow_html=True)
                except:
                    st.error("Unable to load image")
                st.markdown("</div>", unsafe_allow_html=True)
            
            with col_model:
                model_name = model_names[0]
                display_model_response(current_responses[model_name], model_name, current_page)
                
        else:
            # 没有模型响应时，只显示图片和导航栏
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
            
            # 没有模型时的图片显示也居中
            st.markdown("<div class='image-container'>", unsafe_allow_html=True)
            try:
                image = Image.open(current_image_path)
                # 使用居中的图片显示
                st.markdown("<div class='centered-image'>", unsafe_allow_html=True)
                st.image(image, width='stretch')
                st.markdown("</div>", unsafe_allow_html=True)
                # 居中的文件名
                st.markdown(f"<div class='filename-text'>Filename: {image_name}</div>", unsafe_allow_html=True)
            except:
                st.error("Unable to load image")
            st.markdown("</div>", unsafe_allow_html=True)
            st.warning("No model responses available for this image.")

def run_version2():
    """供 display_main.py 调用的入口函数"""
    main()

# 移除或注释掉模块级的 __name__ == "__main__" 检查
# if __name__ == "__main__":
#     main()
