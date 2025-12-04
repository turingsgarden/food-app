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
    return image_files

def build_indices(model_data, available_models, ground_truth_data):
    
    # 构建模型预测索引 (按dish_id)
    model_dish_mapping = {}
    for model_name in available_models:
        model_dish_mapping[model_name] = {}
        for item in model_data.get(model_name, []):
            dish_id = item.get("dish_id")
            if dish_id:
                model_dish_mapping[model_name][dish_id] = item
    
   
    ground_truth_mapping = {}
    for item in ground_truth_data:
        if isinstance(item, dict) and 'dish_id' in item:
            ground_truth_mapping[str(item['dish_id'])] = item
        elif isinstance(item, dict) and 'image_filename' in item:
            
            filename = item['image_filename']
           
            if filename.startswith('dish_') and '_rgb' in filename:
                dish_id = filename.split('_')[1]
                ground_truth_mapping[dish_id] = item
    
   
    image_files = get_all_images()
    image_mapping = {}
    if image_files:
        for img_path in image_files:
            filename = os.path.basename(img_path)
      
            if filename.startswith('dish_') and '_rgb' in filename:
                dish_id = filename.split('_')[1]
            elif filename.endswith('.jpg') or filename.endswith('.png'):
                dish_id = filename.split('.')[0]
            else:
                dish_id = None
            
            if dish_id:
                image_mapping[dish_id] = img_path
    
    return model_dish_mapping, ground_truth_mapping, image_mapping

def find_model_response_by_dish_id(dish_id, model_dish_mapping, model_name):
  
    if model_name not in model_dish_mapping:
        return None
    return model_dish_mapping[model_name].get(str(dish_id))

def find_ground_truth_by_dish_id(dish_id, ground_truth_mapping):
   
    return ground_truth_mapping.get(str(dish_id))

def find_image_by_dish_id(dish_id, image_mapping):
 
    return image_mapping.get(str(dish_id))

def format_analysis_time(seconds):
 
    if seconds is None:
        return "N/A"
    if seconds < 60:
        return f"{seconds:.1f}s"
    else:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m{remaining_seconds:.1f}s"

def display_model_mass_prediction(response, model_name):
   
    if not response:
        st.info("No model response available")
        return
    
  
    analysis_time_seconds = response.get("analysis_time_seconds")
    analysis_time_formatted = response.get("analysis_time", format_analysis_time(analysis_time_seconds))
    
   
    mass_estimation = response.get("mass_estimation", {})
    total_mass = mass_estimation.get("total_mass_g")
    calculated_volume = mass_estimation.get("calculated_volume_cm3")
    food_items = mass_estimation.get("food_items", [])
    
    time_display = f"({analysis_time_formatted})" if analysis_time_formatted and analysis_time_formatted != "N/A" else ""

    total_mass_text = f"{total_mass:.1f} g" if total_mass is not None else "N/A"
    
  
    volume_text = f"{calculated_volume:.1f} cm³" if calculated_volume is not None else "N/A"
    
   
    food_items_list = []
    for item in food_items:
        name = item.get("name", "Unknown")
        mass = item.get("predicted_mass_g", 0)
        confidence = item.get("confidence", 0)
        food_items_list.append(f"• {name:<20} {mass:>8.1f} g (Confidence: {confidence:.2f})")
    
    food_items_text = "\n".join(food_items_list) if food_items_list else "No food items detected"
    
    content_html = f"""
<div class='model-content'>
<div class='model-title'>{model_name}</div>

<div class='section-title'>质量预测 {time_display}</div>
<div class='content-box'>
<strong>Total mass:</strong> {total_mass_text}
<strong>Calculated Vol:</strong> {volume_text}
</div>

<div class='section-title'>食物项目</div>
<div class='content-box'>{food_items_text}</div>
</div>
"""

    st.markdown(
        f"""
    <div class="model-container">
        {content_html}
    </div>
    """,
        unsafe_allow_html=True,
    )

def display_ground_truth_mass(ground_truth):

    if not ground_truth:
        st.info("No ground truth available")
        return
    
    
    ground_truth_mass = None
    if 'ground_truth_mass_g' in ground_truth:
        ground_truth_mass = ground_truth['ground_truth_mass_g']
    elif 'mass_g' in ground_truth:
        ground_truth_mass = ground_truth['mass_g']
    elif 'nutrition' in ground_truth and 'mass' in ground_truth['nutrition']:
        ground_truth_mass = ground_truth['nutrition']['mass']
    

    mass_text = f"{ground_truth_mass:.1f} g" if ground_truth_mass is not None else "N/A"
    
    content_html = f"""
<div class='model-content'>
<div class='ground-truth-title'>Ground Truth</div>

<div class='section-title'>
<div class='content-box'>{mass_text}</div>
</div>
"""

    st.markdown(
        f"""
    <div class="model-container">
        {content_html}
    </div>
    """,
        unsafe_allow_html=True,
    )

def main():
    st.set_page_config(
        page_title="Food Mass Prediction Display",
        layout="wide"
    )
    
    # CSS样式
    st.markdown("""
    <style>
        .main-container {
            min-height: 100vh;
            width: 100%;
        }
        
        .model-container {
            height: auto !important;
            min-height: 300px;
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
        
        .search-container {
            background: white;
            padding: 15px;
            border-radius: 8px;
            border: 1px solid #e1e4e8;
            margin-bottom: 15px;
        }
        
        .dish-id-display {
            font-size: 1.2em;
            font-weight: 600;
            color: #333;
            margin-bottom: 10px;
            text-align: center;
        }
        
        * {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
        }
        
        .stats-box {
            background: #f0f8ff;
            padding: 10px;
            border-radius: 6px;
            margin: 5px 0;
            border-left: 4px solid #1f77b4;
        }
    </style>
    """, unsafe_allow_html=True)
    

    if 'current_dish_id' not in st.session_state:
        st.session_state.current_dish_id = None
    if 'model_dish_mapping' not in st.session_state:
        st.session_state.model_dish_mapping = None
    if 'available_models' not in st.session_state:
        st.session_state.available_models = None
    if 'ground_truth_mapping' not in st.session_state:
        st.session_state.ground_truth_mapping = None
    if 'image_mapping' not in st.session_state:
        st.session_state.image_mapping = None
    if 'data_loaded' not in st.session_state:
        st.session_state.data_loaded = False
    
    if not st.session_state.data_loaded:
        with st.spinner("Loading data..."):
            model_data, available_models, ground_truth_data = load_model_data()
            if not available_models:
                st.error("No model data found")
                return
            
            model_dish_mapping, ground_truth_mapping, image_mapping = build_indices(
                model_data, available_models, ground_truth_data
            )
            
            st.session_state.model_dish_mapping = model_dish_mapping
            st.session_state.available_models = available_models
            st.session_state.ground_truth_mapping = ground_truth_mapping
            st.session_state.image_mapping = image_mapping
            st.session_state.data_loaded = True
    
    
    model_dish_mapping = st.session_state.model_dish_mapping
    available_models = st.session_state.available_models
    ground_truth_mapping = st.session_state.ground_truth_mapping
    image_mapping = st.session_state.image_mapping

    st.title("🍽️ Food Mass Prediction Display")
    
   
    with st.container():
        st.markdown("<div class='search-container'>", unsafe_allow_html=True)
        
        col1, col2, col3 = st.columns([2, 1, 1])
        
        with col1:
            dish_id_input = st.text_input(
                "Search by Dish ID:",
                placeholder="Enter dish ID (e.g., 1558113154)",
                key="dish_id_search"
            )
        
        with col2:
            if st.button("🔍 Search", use_container_width=True):
                if dish_id_input.strip():
                    st.session_state.current_dish_id = dish_id_input.strip()
                    st.rerun()
        
        with col3:
        
            if st.button("🎲 Random Dish", use_container_width=True):
                if image_mapping:
                    random_dish_id = list(image_mapping.keys())[0]  # 取第一个
                    st.session_state.current_dish_id = random_dish_id
                    st.rerun()
        
        st.markdown("</div>", unsafe_allow_html=True)
    
   
    current_dish_id = st.session_state.current_dish_id
    
    if current_dish_id:
      
        current_image_path = find_image_by_dish_id(current_dish_id, image_mapping)
        current_model_response = find_model_response_by_dish_id(
            current_dish_id, model_dish_mapping, "gemini-2.5-pro"
        )
        current_ground_truth = find_ground_truth_by_dish_id(current_dish_id, ground_truth_mapping)
        
    
        st.markdown(f"<div class='dish-id-display'>Dish ID: {current_dish_id}</div>", unsafe_allow_html=True)
        
        
        col_left, col_mid, col_right = st.columns([1, 1, 1])
        
        with col_left:
           
            if current_image_path:
                try:
                    image = Image.open(current_image_path)
                    st.markdown("<div class='image-container'>", unsafe_allow_html=True)
                    st.markdown("<div class='centered-image'>", unsafe_allow_html=True)
                    st.image(image, width='stretch')
                    st.markdown("</div>", unsafe_allow_html=True)
                    st.markdown(f"<div class='filename-text'>{os.path.basename(current_image_path)}</div>", unsafe_allow_html=True)
                    st.markdown("</div>", unsafe_allow_html=True)
                except Exception as e:
                    st.error(f"Unable to load image: {e}")
            else:
                st.warning(f"No image found for dish ID: {current_dish_id}")
              
                if current_model_response and 'file_paths' in current_model_response:
                    file_paths = current_model_response['file_paths']
                    st.info("Available file paths in model data:")
                    for key, path in file_paths.items():
                        st.text(f"{key}: {path}")
        
        with col_mid:
            
            display_model_mass_prediction(current_model_response, "gemini-2.5-pro")
            
         
            if current_model_response:
                st.markdown("<div class='stats-box'>", unsafe_allow_html=True)
                st.markdown("**Additional Info:**")
                
              
                success = current_model_response.get("success", False)
                status = "✅ Success" if success else "❌ Failed"
                st.text(f"Status: {status}")
                
               
                if 'analysis_timestamp' in current_model_response:
                    st.text(f"Analysis: {current_model_response['analysis_timestamp']}")
                if 'processing_timestamp' in current_model_response:
                    st.text(f"Processing: {current_model_response['processing_timestamp']}")
                st.markdown("</div>", unsafe_allow_html=True)
        
        with col_right:
           
            display_ground_truth_mass(current_ground_truth)
            
            
            if current_ground_truth:
                st.markdown("<div class='stats-box'>", unsafe_allow_html=True)
                st.markdown("**Ground Truth Details:**")
                
               
                if 'dish_name' in current_ground_truth:
                    st.text(f"Dish: {current_ground_truth['dish_name']}")
                if 'ingredients' in current_ground_truth:
                    st.text(f"Ingredients: {len(current_ground_truth['ingredients'])} items")
                
             
                for key in ['calories', 'protein_g', 'fat_g', 'carbs_g']:
                    if key in current_ground_truth:
                        st.text(f"{key}: {current_ground_truth[key]}")
                st.markdown("</div>", unsafe_allow_html=True)
                
              
                if (current_model_response and 
                    current_model_response.get('mass_estimation', {}).get('total_mass_g') and
                    current_ground_truth.get('ground_truth_mass_g')):
                    
                    predicted_mass = current_model_response['mass_estimation']['total_mass_g']
                    true_mass = current_ground_truth['ground_truth_mass_g']
                    
                    if true_mass > 0:
                        error = abs(predicted_mass - true_mass)
                        error_percent = (error / true_mass) * 100
                        
                        st.markdown("<div class='stats-box' style='border-left-color: #ff6b6b;'>", unsafe_allow_html=True)
                        st.markdown("**Prediction Error:**")
                        st.text(f"Absolute: {error:.1f} g")
                        st.text(f"Relative: {error_percent:.1f}%")
                        st.markdown("</div>", unsafe_allow_html=True)
    
    else:
        st.info("👆 Enter a Dish ID to search for predictions")
        if image_mapping:
            total_dishes = len(image_mapping)
            st.markdown(f"**Dataset Stats:** {total_dishes} dishes available")
          
            if total_dishes > 0:
                st.markdown("**Sample Dish IDs:**")
                sample_ids = list(image_mapping.keys())[:5]
                for dish_id in sample_ids:
                    st.text(f"• {dish_id}")

def run_version5():
    main()
