import streamlit as st
import traceback
from version1 import run_version1
from version2 import run_version2


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

    to_delete = []
    for key in list(st.session_state.keys()):
        if version_prefix == "v1" and any(k in key for k in keywords_v1):
            to_delete.append(key)
        elif version_prefix == "v2" and any(k in key for k in keywords_v2):
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


# -------------------------------
# 🔹 UI: Version Selector
# -------------------------------
st.selectbox("Select version to display:", ["Version 1", "Version 2"], key="page_select")

if st.button("✅ Confirm Selection"):
    new_version = st.session_state.page_select
    prev_version = st.session_state.selected_version

    # ✅ Clean previous version state before switching
    if prev_version == "Version 1":
        clear_version_state("v1")
    elif prev_version == "Version 2":
        clear_version_state("v2")

    # ✅ Update selection and refresh immediately
    st.session_state.selected_version = new_version
    st.rerun()


# -------------------------------
# 🔹 Load different subpages based on selection
# -------------------------------
if st.session_state.selected_version:
    try:
        if st.session_state.selected_version == "Version 1":
            run_version1()
        elif st.session_state.selected_version == "Version 2":
            run_version2()
    except Exception:
        st.error("❌ Error occurred while executing subpage, please check traceback:")
        st.text(traceback.format_exc())

    # 🔙 Return button: Clean current version state and return to selection page
    if st.button("⬅ Back to Version Selection"):
        if st.session_state.selected_version == "Version 1":
            clear_version_state("v1")
        elif st.session_state.selected_version == "Version 2":
            clear_version_state("v2")

        st.session_state.selected_version = ""
        st.rerun()
