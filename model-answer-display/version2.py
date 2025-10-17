
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
    
    # 添加自适应CSS样式
    st.markdown("""
    <style>
        /* 整体页面缩放控制 */
        .main-container {
            min-height: 100vh;
            width: 100%;
        }
        
        /* 模型容器 - 完全自适应 */
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
        
        /* 响应式字体大小 */
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
        
        /* 模型标题样式 - 现在放在框内 */
        .model-title {
            font-size: 1.3em;
            font-weight: 600;
            color: #1f77b4;
            margin-bottom: 15px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding-bottom: 10px;
            border-bottom: 2px solid #e1e4e8;
        }
        
        /* 图片容器 - 添加居中样式 */
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
        
        /* 图片样式 */
        .centered-image {
            display: flex;
            justify-content: center;
            align-items: center;
            width: 100%;
        }
        
        /* 文件名样式 */
        .filename-text {
            text-align: center;
            margin-top: 10px;
            font-weight: 500;
        }
        
        /* 导航栏样式 - 修复空白问题 */
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
        
        /* 移除 Streamlit 默认列间距与空白框 */
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
    
        /* 移除整个图片区域上下额外空白 */
        .image-container {
            background: white;
            padding: 10px 10px 5px 10px;
            border-radius: 8px;
            border: 1px solid #e1e4e8;
            margin: 0 !important;
        }
        
        /* 响应式布局调整 */
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
                
        /* 让图片列内容垂直居中 */
        .left-column {
            display: flex;
            flex-direction: column;
            justify-content: center;  /* 垂直居中 */
            align-items: center;      /* 水平居中 */
            height: 100%;
        }
        
        /* 确保所有元素使用现代字体 */
        * {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
        }
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
