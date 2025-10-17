import streamlit as st
from version2 import run_version2
from version1 import run_version1

# 初始化 session_state
if "selected_version" not in st.session_state:
    st.session_state.selected_version = None

# 如果还没选择版本，则显示选择框
if st.session_state.selected_version is None:
    page = st.selectbox("Select version", ["Version 1", "Version 2"])
    if st.button("Confirm"):
        st.session_state.selected_version = page
        # 使用 experimental_rerun 确保完全刷新
        st.rerun()

# 如果已选择版本，则进入对应版本页面
else:
    # 在加载任何版本前，先清除可能的 CSS 影响
    st.markdown("""
    <style>
        /* 重置所有可能的缩放和变换 */
        * {
            transform: none !important;
            width: auto !important;
            height: auto !important;
            zoom: 1 !important;
            scale: 1 !important;
        }
        
        /* 确保 Streamlit 容器恢复正常 */
        .block-container {
            padding: 1rem 1rem 10rem !important;
            max-width: none !important;
        }
        
        /* 重置所有可能被影响的元素 */
        .main .block-container, 
        div[data-testid="stAppViewContainer"], 
        div[data-testid="stSidebar"],
        .stApp {
            transform: none !important;
            width: 100% !important;
            max-width: 100% !important;
        }
    </style>
    """, unsafe_allow_html=True)
    
    # 强制刷新页面状态
    st.markdown('<div style="display:none">Force Refresh</div>', unsafe_allow_html=True)
    
    if st.session_state.selected_version == "Version 1":
        run_version1()
    elif st.session_state.selected_version == "Version 2":
        run_version2()
    
    # 提供一个返回按钮
    if st.button("⬅ Back to version selection"):
        st.session_state.selected_version = None
        # 清除所有可能的缓存状态
        st.session_state.clear()
        st.rerun()
