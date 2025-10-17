import streamlit as st
from version2 import run_version2
from version1 import run_version1
import traceback

# 初始化状态
if "selected_version" not in st.session_state:
    st.session_state.selected_version = ""
if "page_select" not in st.session_state:
    st.session_state.page_select = "Version 1"

# 版本选择页
if not st.session_state.selected_version:
    st.selectbox("Select version", ["Version 1", "Version 2"], key="page_select")
    if st.button("Confirm"):
        st.session_state.selected_version = st.session_state.page_select

# 显示所选版本页面
else:
    # --- 统一样式 ---
    st.markdown("""
    <style>
        * {
            box-sizing: border-box;
            transform: none !important;
            zoom: 1 !important;
        }
        .block-container {
            max-width: 1200px !important;
            padding: 1rem 2rem 5rem !important;
        }
        img {
            max-width: 100% !important;
            height: auto !important;
        }
        body, .stApp {
            background-color: white !important;
            font-family: "Helvetica", "Arial", sans-serif !important;
        }
    </style>
    """, unsafe_allow_html=True)

    st.subheader(f"📘 当前版本：{st.session_state.selected_version}")

    # --- 运行子页面 ---
    try:
        if st.session_state.selected_version == "Version 1":
            run_version1()
        elif st.session_state.selected_version == "Version 2":
            run_version2()
    except Exception:
        st.error("子页面执行时出错：")
        st.text(traceback.format_exc())

    # --- 返回按钮 ---
    if st.button("⬅ Back to version selection"):
        st.session_state.selected_version = ""
