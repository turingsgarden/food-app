import streamlit as st
import traceback
from version1 import run_version1
from version2 import run_version2
from version3 import run_version3  


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

    to_delete = []
    for key in list(st.session_state.keys()):
        if version_prefix == "v1" and any(k in key for k in keywords_v1):
            to_delete.append(key)
        elif version_prefix == "v2" and any(k in key for k in keywords_v2):
            to_delete.append(key)
        elif version_prefix == "v3" and any(k in key for k in keywords_v3):
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
    # 更新选择框包含Version 3
    st.selectbox("Select version to display:", 
                ["Version 1", "Version 2", "Version 3"], 
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

        st.session_state.selected_version = ""
        st.session_state.version_initialized = False
        st.rerun()
