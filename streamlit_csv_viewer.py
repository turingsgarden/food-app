# streamlit_csv_viewer.py adapted to just view from csv file generated through llm call in streamlit_app.py
import streamlit as st
import pandas as pd
import os
from PIL import Image

RESULTS_CSV = "analysis_results_viewer.csv"

st.set_page_config(page_title="🍔 Food Calorie Estimator", layout="wide")
st.title("📊 Food Image Results Viewer")

@st.cache_data
def load_full_csv():
    if not os.path.exists(RESULTS_CSV):
        st.error(f"CSV file not found: {RESULTS_CSV}")
        return None
    try:
        df = pd.read_csv(
            RESULTS_CSV,
            on_bad_lines='skip',
            quoting=1,
            escapechar='\\',
            encoding='utf-8'
        )
        return df
    except Exception as e:
        st.error(f"Failed to load CSV: {e}")
        return None

# Load results
df = load_full_csv()
if df is None or len(df) == 0:
    st.warning("⚠️ No results in CSV yet.")
    st.stop()

unique_images = df['image_path'].unique()

# Navigation
if 'csv_idx' not in st.session_state:
    st.session_state.csv_idx = 0

def prev_image():
    if st.session_state.csv_idx > 0:
        st.session_state.csv_idx -= 1

def next_image():
    if st.session_state.csv_idx < len(unique_images) - 1:
        st.session_state.csv_idx += 1

col1, col2, col3 = st.columns([1, 6, 1])
with col1:
    st.button("← Prev", on_click=prev_image, disabled=(st.session_state.csv_idx == 0))
with col2:
    st.markdown(f"**Image {st.session_state.csv_idx + 1} / {len(unique_images)}**")
with col3:
    st.button("Next →", on_click=next_image, disabled=(st.session_state.csv_idx == len(unique_images) - 1))

new_idx = st.slider(
    "Jump to image:", 
    1, 
    len(unique_images), 
    st.session_state.csv_idx + 1
) - 1
if new_idx != st.session_state.csv_idx:
    st.session_state.csv_idx = new_idx

# Display current image and results
current_image_path = unique_images[st.session_state.csv_idx]
image_results = df[df['image_path'] == current_image_path]

left_col, right_col = st.columns([1, 2])

with left_col:
    st.subheader(f"📷 {os.path.basename(current_image_path)}")
    if os.path.exists(current_image_path):
        img = Image.open(current_image_path)
        st.image(img, use_container_width=True)
    else:
        st.error(f"Image not found: {current_image_path}")
    st.caption(f"Path: `{current_image_path}`")

with right_col:
    st.subheader("🤖 Model Outputs")
    for _, row in image_results.iterrows():
        model = row['model']
        st.markdown(f"### 🤖 {model}")
        st.text(f"🍽️ Dish: {row['dish_names']}")
        with st.expander("🥦 Cleaned Ingredients"):
            st.text(row['cleaned_ingredients'])
        with st.expander("🧂 Hidden Ingredients"):
            st.text(row['hidden_ingredients'])
        with st.expander("📊 Nutrition Info"):
            st.text(str(row['full_nutrition']).replace('; ', '\n'))
        st.caption(f"Timestamp: {row['timestamp']}")
        st.divider()
