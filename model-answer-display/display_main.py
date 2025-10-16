import streamlit as st

st.title("Model Answer Display")

page = st.selectbox("Select version", ["Version 1", "Version 2"])

if page == "Version 1":
    from version1 import main as version1_main
    version1_main()
elif page == "Version 2":
    from version2 import main as version2_main
    version2_main()
