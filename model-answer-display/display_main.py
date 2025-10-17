import streamlit as st
from version2 import run_version2
from version1 import run_version1
import traceback

# 初始化 session_state
if "selected_version" not in st.session_state:
    st.session_state.selected_version = ""    # 用空字符串表示未选择

# 将 selectbox 的值放到 session_state（避免本地变量在 rerun 时丢失）
if "page_select" not in st.session_state:
    st.session_state.page_select = "Version 1"

# 选择器 + 确认放在同一处；也可以使用 st.form 更整洁
st.selectbox("Select version", ["Version 1", "Version 2"], key="page_select")

# 点击确认后把选择写入 selected_version（不要立刻 rerun）
if st.button("Confirm"):
    st.session_state.selected_version = st.session_state.page_select

# 如果已选择版本，则显示对应页面
if st.session_state.selected_version:
    # （可选）清理不必要的 CSS 操作：避免隐藏/断开 streamlit 的默认布局。仅在确实需要时注入样式。
    # 下面示范如何安全地包裹运行并在出错时显示 traceback
    try:
        if st.session_state.selected_version == "Version 1":
            run_version1()
        elif st.session_state.selected_version == "Version 2":
            run_version2()
    except Exception as e:
        st.error("子页面执行时发生异常，请查看下面的 traceback：")
        st.text(traceback.format_exc())

    # 返回按钮：只重置选中的版本键，而不清空全部 session_state
    if st.button("⬅ Back to version selection"):
        st.session_state.selected_version = ""
        # 你可以有选择地清除 page_select 或其它中间状态键，但不要 clear() 所有键
        # st.session_state.page_select = "Version 1"
        # st.experimental_rerun()  # 一般不需要；Streamlit 会自动在下一次交互时重新渲染
