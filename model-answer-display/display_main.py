import streamlit as st
import traceback
from version1 import run_version1
from version2 import run_version2


# -------------------------------
# 🔹 清理旧版本专属状态键
# -------------------------------
def clear_version_state(version_prefix):
    """清除指定版本的 session_state key，避免两个版本切换时冲突"""
    # === Version 1 专属 keys（来自 version1.py）===
    keywords_v1 = [
        "current_page", "data_loaded", "valid_images",
        "model_file_mapping", "available_models",
        "current_responses", "selected_image", "uploaded_file",
        "analysis_time", "display_mode", "image_display_mode",
        "image_index", "model_responses", "json_str",
        "result_display", "response_data"
    ]

    # === Version 2 专属 keys（来自 version2.py）===
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
        print(f"🧹 已清理 {version_prefix} 状态键: {to_delete}")


# -------------------------------
# 🔹 初始化
# -------------------------------
if "selected_version" not in st.session_state:
    st.session_state.selected_version = ""  # 当前已选择的版本
if "page_select" not in st.session_state:
    st.session_state.page_select = "Version 1"  # 默认选项


# -------------------------------
# 🔹 UI：版本选择器
# -------------------------------
st.title("📊 Model Answer Display")
st.markdown("---")

st.selectbox("选择要展示的版本：", ["Version 1", "Version 2"], key="page_select")

if st.button("✅ Confirm"):
    new_version = st.session_state.page_select
    prev_version = st.session_state.selected_version

    # ✅ 切换前清理上一个版本的状态
    if prev_version == "Version 1":
        clear_version_state("v1")
    elif prev_version == "Version 2":
        clear_version_state("v2")

    # 更新当前选择并刷新页面
    st.session_state.selected_version = new_version
    st.rerun()


# -------------------------------
# 🔹 根据选择加载不同子页面
# -------------------------------
if st.session_state.selected_version:
    st.markdown(f"### 🔄 当前展示：{st.session_state.selected_version}")
    st.markdown("---")

    try:
        if st.session_state.selected_version == "Version 1":
            run_version1()
        elif st.session_state.selected_version == "Version 2":
            run_version2()
    except Exception:
        st.error("❌ 子页面执行时发生异常，请查看 traceback：")
        st.text(traceback.format_exc())

    # 返回按钮：只重置 selected_version，不清空全局状态
    if st.button("⬅ 返回版本选择"):
        # 清理当前版本的缓存
        if st.session_state.selected_version == "Version 1":
            clear_version_state("v1")
        elif st.session_state.selected_version == "Version 2":
            clear_version_state("v2")

        st.session_state.selected_version = ""
        st.rerun()
