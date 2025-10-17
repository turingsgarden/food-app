import streamlit as st
from version1 import run_version1
from version2 import run_version2

def clear_version_state(prefix: str):
    """清理指定前缀的 Streamlit session_state"""
    keys_to_delete = [k for k in st.session_state.keys() if k.startswith(prefix)]
    for k in keys_to_delete:
        del st.session_state[k]

# --- 页面逻辑 ---
st.sidebar.title("Model Version Switcher")

# 记录上一次选中的版本
if "selected_version" not in st.session_state:
    st.session_state.selected_version = "Version 1"

selected_version = st.sidebar.radio(
    "Choose a version:",
    ["Version 1", "Version 2"],
    index=0 if st.session_state.selected_version == "Version 1" else 1
)

# 检查版本是否切换
if selected_version != st.session_state.selected_version:
    if selected_version == "Version 1":
        clear_version_state("v2_")  # 清理 version2 专用状态
    else:
        clear_version_state("v1_")  # 清理 version1 专用状态
    st.session_state.selected_version = selected_version

# --- 根据选择运行 ---
if selected_version == "Version 1":
    run_version1()
else:
    run_version2()
