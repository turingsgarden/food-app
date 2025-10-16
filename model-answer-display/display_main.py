import streamlit as st

# 初始化 session_state
if "selected_version" not in st.session_state:
    st.session_state.selected_version = None

st.title("Model Answer Display")

# 如果还没选择版本，则显示选择框
if st.session_state.selected_version is None:
    page = st.selectbox("Select version", ["Version 1", "Version 2"])
    if st.button("Confirm"):
        st.session_state.selected_version = page
        st.rerun()

# 如果已选择版本，则进入对应版本页面
else:
    if st.session_state.selected_version == "Version 1":
        from version1 import main as version1_main
        version1_main()
    elif st.session_state.selected_version == "Version 2":
        from version2 import main as version2_main
        version2_main()

    # 提供一个返回按钮
    if st.button("⬅ Back to version selection"):
        st.session_state.selected_version = None
        st.rerun()
