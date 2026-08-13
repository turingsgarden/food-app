import streamlit as st
import traceback
from version1 import run_version1
from version2 import run_version2
from version3 import run_version3
from version4 import run_version4
from version5 import run_version5  # 添加Version 5导入
from version6 import run_version6 
from version7 import run_version7 


# -------------------------------
# 🔹 Clean version-specific state keys
# -------------------------------
def clear_version_state(version_prefix):
    """Clear session_state keys for specified version to avoid conflicts"""
    keywords_v1 = [
        "current_page", "data_loaded", "valid_images",
        "model_file_mapping", "available_models",
        "current_responses", "selected_image", "uploaded_file",
        "analysis_time", "display_mode", "image_display_mode",
        "image_index", "model_responses", "json_str",
        "result_display", "response_data", "analysis_time" 
    ]

    keywords_v2 = [
        "pydantic_output", "structured_output", "parsed_data",
        "schema_data", "json_display", "selected_model",
        "current_response", "model_answer", "formatted_output",
        "response_json", "analysis_summary", "image_result",
        "food_info", "nutrition_data", "display_mode_v2"
    ]
    
    keywords_v3 = [
        "v3_current_page", "v3_data_loaded", "v3_valid_images",
        "v3_model_responses", "v3_selected_image", "v3_uploaded_file",
        "v3_analysis_time", "v3_display_mode", "v3_image_index",
        "v3_response_data", "v3_result_display", "v3_structured_data"
    ]
    
    keywords_v4 = [
        "v4_current_page", "v4_data_loaded", "v4_valid_images",
        "v4_model_responses", "v4_selected_image", "v4_uploaded_file",
        "v4_analysis_time", "v4_display_mode", "v4_image_index",
        "v4_response_data", "v4_result_display", "v4_structured_data",
        "v4_advanced_settings", "v4_custom_config"
    ]
    
    keywords_v5 = [
        "v5_current_dish_id", "v5_show_console_output", "v5_model_dish_mapping",
        "v5_available_models", "v5_ground_truth_mapping", "v5_image_mapping",
        "v5_data_loaded", "v5_search_query", "v5_current_response",
        "v5_current_ground_truth", "v5_current_image_path", "v5_error_stats",
        "v5_display_mode", "v5_filter_mode", "v5_sort_order"
    ]

    keywords_v6 = [
    "v6_current_page", "v6_data_loaded", "v6_dish_order",
    "v6_dish_rows", "v6_image_map", "v6_search_dish_id",
    "v6_summary_dict"
    ]

    keywords_v7 = [
    "v7_current_page", "v7_search_dish_id", "v7_search_mode",
    "v7_valid_images", "v7_data_loaded", "v7_model_dish_mapping",
    "v7_available_models", "v7_ground_truth_mapping", "v7_image_mapping"
    ]

    to_delete = []
    for key in list(st.session_state.keys()):
        if version_prefix == "v1" and any(k in key for k in keywords_v1):
            to_delete.append(key)
        elif version_prefix == "v2" and any(k in key for k in keywords_v2):
            to_delete.append(key)
        elif version_prefix == "v3" and any(k in key for k in keywords_v3):
            to_delete.append(key)
        elif version_prefix == "v4" and any(k in key for k in keywords_v4):
            to_delete.append(key)
        elif version_prefix == "v5" and any(k in key for k in keywords_v5):
            to_delete.append(key)
        elif version_prefix == "v6" and any(k in key for k in keywords_v6):
            to_delete.append(key)
        elif version_prefix == "v7" and any(k in key for k in keywords_v7):
            to_delete.append(key)

    for key in to_delete:
        del st.session_state[key]

    if to_delete:
        print(f"🧹 Clean {version_prefix} keys: {to_delete}")


# -------------------------------
# 🔹 Initialize
# -------------------------------
if "selected_version" not in st.session_state:
    st.session_state.selected_version = ""  # Currently selected version
if "page_select" not in st.session_state:
    st.session_state.page_select = "Version 1"  # Default option
if "version_initialized" not in st.session_state:
    st.session_state.version_initialized = False  # Track if version is freshly initialized


# -------------------------------
# 🔹 UI: Version Selector (Only show when no version is selected)
# -------------------------------
if not st.session_state.selected_version:
    # Update selection box to include all versions
    st.selectbox("Select version to display:", 
                ["Version 1", "Version 2", "Version 3", "Version 4", "Version 5", "Version 6", "Version 7"],  # 添加Version 5
                key="page_select")

    if st.button("✅ Confirm Selection"):
        new_version = st.session_state.page_select
        prev_version = st.session_state.selected_version

        # ✅ Clean previous version state before switching
        if prev_version == "Version 1":
            clear_version_state("v1")
        elif prev_version == "Version 2":
            clear_version_state("v2")
        elif prev_version == "Version 3":
            clear_version_state("v3")
        elif prev_version == "Version 4":
            clear_version_state("v4")
        elif prev_version == "Version 5":  # 添加Version 5清理
            clear_version_state("v5")
        elif prev_version == "Version 6":
            clear_version_state
        elif prev_version == "Version 7":
            clear_version_state

        # ✅ Update selection and mark as freshly initialized
        st.session_state.selected_version = new_version
        st.session_state.version_initialized = True
        st.rerun()


# -------------------------------
# 🔹 Load different subpages based on selection
# -------------------------------
if st.session_state.selected_version:
    # Reset initialization flag after first render
    if st.session_state.version_initialized:
        st.session_state.version_initialized = False
        st.rerun()  # Force a rerun to ensure clean state
    
    try:
        if st.session_state.selected_version == "Version 1":
            run_version1()
        elif st.session_state.selected_version == "Version 2":
            run_version2()
        elif st.session_state.selected_version == "Version 3": 
            run_version3()
        elif st.session_state.selected_version == "Version 4":
            run_version4()
        elif st.session_state.selected_version == "Version 5":  # 添加Version 5执行
            run_version5()
        elif st.session_state.selected_version == "Version 6":
            run_version6()
        elif st.session_state.selected_version == "Version 7":
            run_version7()
    except Exception as e:
        st.error("❌ Error occurred while executing subpage, please check traceback:")
        st.text(traceback.format_exc())
        st.error(f"Error details: {str(e)}")

    # 🔙 Return button: Clean current version state and return to selection page
    if st.button("⬅ Back to Version Selection"):
        current_version = st.session_state.selected_version
        if current_version == "Version 1":
            clear_version_state("v1")
        elif current_version == "Version 2":
            clear_version_state("v2")
        elif current_version == "Version 3": 
            clear_version_state("v3")
        elif current_version == "Version 4":
            clear_version_state("v4")
        elif current_version == "Version 5":  # 添加Version 5清理
            clear_version_state("v5")
        elif current_version == "Version 6":
            clear_version_state("v6")
        elif current_version == "Version 7":
            clear_version_state("v7")

        st.session_state.selected_version = ""
        st.session_state.version_initialized = False
        st.rerun()
