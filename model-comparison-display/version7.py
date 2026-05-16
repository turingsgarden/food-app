"""
version7.py
-----------
All models displayed side by side for each food image.
Styled exactly like Version 5 (white background, light theme, same CSS).
Models: Gemini 2.5 Pro, Gemini 2.5 Flash, Claude Sonnet 4.5, GPT-5.4
Ground truth column shows correct food name from filename.
Sanity check: calculates expected calories from macros vs model output.
Calorie accuracy stats shown at the bottom.
"""

import streamlit as st
import json
import os
from PIL import Image

# ---------------------------------------------------------------------------
# Model files
# ---------------------------------------------------------------------------
MODEL_FILES = {
    "Gemini 2.5 Pro":    "output/Gemini-2.5-pro_pydantic_food_dataset_analysis.json",
    "Gemini 2.5 Flash":  "output/Gemini-2.5-flash_pydantic_food_dataset_analysis.json",
    "Claude Sonnet 4.5": "output/Claude-4.5-sonnet_food-101_analysis.json",
    "GPT-5.4":           "output/GPT-5.4_food-101_analysis.json",
}

IMAGE_DIR = "food-101_100images"

MODEL_COLORS = {
    "Gemini 2.5 Pro":    "#1f77b4",
    "Gemini 2.5 Flash":  "#ff7f0e",
    "Claude Sonnet 4.5": "#9467bd",
    "GPT-5.4":           "#2ca02c",
}

# Tolerance for calorie sanity check (±20%)
CALORIE_TOLERANCE = 0.20

# ---------------------------------------------------------------------------
# CSS — exact copy from Version 5
# ---------------------------------------------------------------------------
CSS = """
<style>
    .main-container { min-height: 100vh; width: 100%; }

    .model-container {
        height: auto !important;
        min-height: 400px;
        max-height: none !important;
        overflow: visible !important;
        border: 1px solid #e1e4e8;
        border-radius: 8px;
        padding: 8px;
        margin-bottom: 15px;
        background: white;
    }

    .section-title {
        font-weight: 600;
        font-size: 0.9em;
        color: #2c3e50;
        margin: 8px 0 3px 0;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }

    .content-box {
        white-space: pre-wrap;
        font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
        margin: 3px 0;
        padding: 5px;
        background: #f8f9fa;
        border-radius: 6px;
        line-height: 1.5;
        border: 1px solid #e1e4e8;
        font-size: 0.72em;
        color: #333;
    }

    .model-title {
        font-size: 0.95em;
        font-weight: 600;
        margin-bottom: 10px;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        padding-bottom: 8px;
        border-bottom: 2px solid #e1e4e8;
    }

    .sanity-pass {
        background: #e6ffe6;
        border: 1px solid #2ca02c;
        border-radius: 6px;
        padding: 5px;
        font-size: 0.72em;
        color: #1a7a1a;
        margin: 3px 0;
        white-space: pre-wrap;
        font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    }

    .sanity-fail {
        background: #ffe6e6;
        border: 1px solid #ff4444;
        border-radius: 6px;
        padding: 5px;
        font-size: 0.72em;
        color: #aa0000;
        margin: 3px 0;
        white-space: pre-wrap;
        font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    }

    .image-container {
        background: white;
        padding: 0 10px 10px 10px;
        border-radius: 8px;
        border: 1px solid #e1e4e8;
        margin-bottom: 10px;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        text-align: center;
    }

    .filename-text {
        text-align: center;
        margin-top: 8px;
        font-weight: 500;
        font-size: 0.85em;
        color: #555;
    }

    .dish-id-display {
        font-size: 1.1em;
        font-weight: 600;
        color: #333;
        margin: 5px 0 8px 0;
        text-align: center;
        padding: 6px 10px;
        background: #f8f9fa;
        border-radius: 6px;
        border: 1px solid #e1e4e8;
    }

    .nav-container {
        margin-bottom: 15px;
        padding: 10px;
        background: #f8f9fa;
        border-radius: 6px;
        border: 1px solid #e1e4e8;
    }

    .search-box { margin-bottom: 15px; }

    * {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
    }

    .main-title-container { margin-bottom: 20px; }
    .stApp { padding-top: 10px; }
    .block-container { padding-top: 2rem; padding-bottom: 2rem; }

    .not-available {
        background: #f9fafb;
        border: 1.5px dashed #d1d5db;
        border-radius: 8px;
        padding: 20px;
        color: #6b7280;
        font-size: 0.85em;
        text-align: center;
        min-height: 150px;
    }

    .stats-container {
        border: 1px solid #e1e4e8;
        border-radius: 8px;
        padding: 15px;
        background: white;
        margin-top: 10px;
    }

    .stats-title {
        font-size: 1.1em;
        font-weight: 600;
        color: #2c3e50;
        margin-bottom: 10px;
        padding-bottom: 8px;
        border-bottom: 2px solid #e1e4e8;
    }

    .stat-box {
        background: #f8f9fa;
        border-radius: 6px;
        padding: 10px;
        border: 1px solid #e1e4e8;
        text-align: center;
        margin: 5px 0;
    }

    .stat-value {
        font-size: 1.5em;
        font-weight: 700;
    }

    .stat-label {
        font-size: 0.8em;
        color: #666;
        margin-top: 3px;
    }
</style>
"""

# ---------------------------------------------------------------------------
# Data helpers
# ---------------------------------------------------------------------------

def load_json(path):
    for enc in ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252']:
        try:
            with open(path, 'r', encoding=enc) as f:
                return json.load(f)
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    return None


def build_record_index(records):
    index = {}
    for rec in records:
        if 'image_filename' in rec:
            index[rec['image_filename']] = rec
        elif 'image_path' in rec:
            index[os.path.basename(rec['image_path'])] = rec
    return index


def build_image_index():
    index = {}
    if not os.path.exists(IMAGE_DIR):
        return index
    for fname in os.listdir(IMAGE_DIR):
        if os.path.splitext(fname)[1].lower() in {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}:
            index[fname] = os.path.join(IMAGE_DIR, fname)
    return index


def format_time(t):
    if t is None:
        return ""
    if isinstance(t, str):
        return t
    return f"{t:.1f}s" if t < 60 else f"{int(t//60)}m{t%60:.1f}s"


def food_name_from_filename(filename):
    name = os.path.splitext(filename)[0]
    name = name.rsplit("_", 1)[0]
    return name.replace("_", " ").title()


# ---------------------------------------------------------------------------
# Calorie sanity check
# Atwater factors: Protein=4 kcal/g, Carbs=4 kcal/g, Fat=9 kcal/g
# ---------------------------------------------------------------------------

def calculate_expected_calories(nutrition):
    """Calculate expected calories from macros using Atwater factors."""
    try:
        protein = float(nutrition.get("protein", 0) or 0)
        carbs   = float(nutrition.get("carbohydrates", 0) or 0)
        fat     = float(nutrition.get("fat", 0) or 0)
        return round(protein * 4 + carbs * 4 + fat * 9, 1)
    except (TypeError, ValueError):
        return None


def calorie_sanity_check(nutrition):
    """
    Compare model-reported calories vs macro-calculated calories.
    Returns (pass, reported, expected, difference_pct) tuple.
    """
    try:
        reported = float(nutrition.get("calories", 0) or 0)
        expected = calculate_expected_calories(nutrition)
        if expected is None or expected == 0:
            return None, reported, None, None
        diff_pct = abs(reported - expected) / expected
        passed   = diff_pct <= CALORIE_TOLERANCE
        return passed, reported, expected, diff_pct
    except (TypeError, ValueError):
        return None, None, None, None


# ---------------------------------------------------------------------------
# Compute accuracy stats across all images for one model
# ---------------------------------------------------------------------------

def compute_calorie_stats(record_index):
    """
    Returns dict with:
      total, checked, passed, failed, pass_rate, avg_diff_pct
    """
    total     = len(record_index)
    checked   = 0
    passed    = 0
    failed    = 0
    diff_pcts = []

    for rec in record_index.values():
        nutrition = rec.get("nutrition", {})
        if not nutrition:
            continue
        result, reported, expected, diff_pct = calorie_sanity_check(nutrition)
        if result is None:
            continue
        checked += 1
        if result:
            passed += 1
        else:
            failed += 1
        if diff_pct is not None:
            diff_pcts.append(diff_pct)

    avg_diff = round(sum(diff_pcts) / len(diff_pcts) * 100, 1) if diff_pcts else 0
    pass_rate = round(passed / checked * 100, 1) if checked > 0 else 0

    return {
        "total":     total,
        "checked":   checked,
        "passed":    passed,
        "failed":    failed,
        "pass_rate": pass_rate,
        "avg_diff":  avg_diff,
    }


# ---------------------------------------------------------------------------
# Display one model card
# ---------------------------------------------------------------------------

def display_model_card(record, model_name):
    color = MODEL_COLORS.get(model_name, "#1f77b4")

    if not record:
        st.markdown(f"""
<div class="model-container">
  <div class="model-title" style="color:{color};">{model_name}</div>
  <div class="not-available">No data available for this image</div>
</div>""", unsafe_allow_html=True)
        return

    elapsed      = format_time(record.get("analysis_time_seconds") or record.get("analysis_time"))
    time_display = f"({elapsed})" if elapsed else ""

    dish_names    = record.get("dish_names", [])
    dish_pred     = ", ".join(dish_names) if dish_names else "—"
    units_map     = {"calories": "kcal", "protein": "g", "fat": "g",
                     "carbohydrates": "g", "fiber": "g", "sugar": "g", "sodium": "mg"}
    visible       = record.get("visible_ingredients", [])
    hidden        = record.get("hidden_ingredients", [])
    nutrition     = record.get("nutrition", {})

    visible_lines = [f"• {i['name']:<20} {i['quantity']:>5} {i['unit']}" for i in visible]
    hidden_lines  = [f"• {i['name']:<20} {i['quantity']:>5} {i['unit']}" for i in hidden]
    nutrition_map = {k.capitalize(): f"{v} {units_map.get(k, '')}"
                     for k, v in nutrition.items()}

    visible_text   = "\n".join(visible_lines) if visible_lines else "—"
    hidden_text    = "\n".join(hidden_lines)  if hidden_lines  else "—"
    nutrition_text = "\n".join(f"• {k:<14} {v}" for k, v in nutrition_map.items()) or "—"

    # Sanity check
    passed, reported, expected, diff_pct = calorie_sanity_check(nutrition)
    if passed is None:
        sanity_html = '<div class="content-box">Not enough macro data</div>'
    else:
        expected_cal = calculate_expected_calories(nutrition)
        diff_str     = f"{diff_pct*100:.1f}%"
        status       = "✅ PASS" if passed else "❌ FAIL"
        css_class    = "sanity-pass" if passed else "sanity-fail"
        sanity_html  = f"""<div class="{css_class}">{status}
Reported:  {reported:.0f} kcal
Expected:  {expected_cal:.0f} kcal
Diff:      {diff_str} (tolerance ±{int(CALORIE_TOLERANCE*100)}%)</div>"""

    st.markdown(f"""
<div class="model-container">
<div class="model-title" style="color:{color};">{model_name} {time_display}</div>

<div class="section-title">Dish Prediction</div>
<div class="content-box">{dish_pred}</div>

<div class="section-title">Visible Ingredients</div>
<div class="content-box">{visible_text}</div>

<div class="section-title">Hidden Ingredients</div>
<div class="content-box">{hidden_text}</div>

<div class="section-title">Nutrition</div>
<div class="content-box">{nutrition_text}</div>

<div class="section-title">🔬 Calorie Sanity Check</div>
{sanity_html}
</div>""", unsafe_allow_html=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    st.set_page_config(layout="wide")
    st.markdown(CSS, unsafe_allow_html=True)

    # Session state
    for k, v in {
        'v7_page':        0,
        'v7_search':      "",
        'v7_data_loaded': False,
        'v7_all_indices': {},
        'v7_image_index': {},
        'v7_filenames':   [],
    }.items():
        if k not in st.session_state:
            st.session_state[k] = v

    # Title
    st.markdown("<div class='main-title-container'>", unsafe_allow_html=True)
    st.title("🍽️ Food Analysis — Model Comparison")
    st.markdown("</div>", unsafe_allow_html=True)

    # Load all model data once
    if not st.session_state.v7_data_loaded:
        with st.spinner("Loading model data..."):
            all_indices = {}
            image_index = build_image_index()

            for model_name, path in MODEL_FILES.items():
                if os.path.exists(path):
                    records = load_json(path)
                    if records:
                        all_indices[model_name] = build_record_index(records)

            all_fnames = set()
            for idx in all_indices.values():
                all_fnames.update(idx.keys())
            filenames = sorted(f for f in all_fnames if f in image_index)
            if not filenames:
                filenames = sorted(all_fnames)

            st.session_state.v7_all_indices = all_indices
            st.session_state.v7_image_index = image_index
            st.session_state.v7_filenames   = filenames
            st.session_state.v7_data_loaded = True

    all_indices = st.session_state.v7_all_indices
    image_index = st.session_state.v7_image_index
    filenames   = st.session_state.v7_filenames

    if not filenames:
        st.error("No images found. Make sure pipeline scripts have been run.")
        return

    total = len(filenames)

    # Search
    with st.container():
        st.markdown("<div class='search-box'>", unsafe_allow_html=True)
        sc1, sc2, sc3 = st.columns([3, 1, 1])
        with sc1:
            search_val = st.text_input(
                "Search by filename:",
                value=st.session_state.v7_search,
                placeholder="e.g. baklava_399226.jpg",
                key="v7_search_input"
            )
        with sc2:
            if st.button("🔍 Search", use_container_width=True):
                if search_val.strip():
                    st.session_state.v7_search = search_val.strip()
                    matches = [i for i, f in enumerate(filenames)
                               if search_val.strip().lower() in f.lower()]
                    if matches:
                        st.session_state.v7_page = matches[0]
                        st.success(f"Found: {filenames[matches[0]]}")
                    else:
                        st.error(f"Not found: {search_val.strip()}")
        with sc3:
            if st.button("📄 Clear Search", use_container_width=True):
                st.session_state.v7_search = ""
                st.session_state.v7_page   = 0
        st.markdown("</div>", unsafe_allow_html=True)

    # Current item
    page = max(0, min(st.session_state.v7_page, total - 1))
    current_filename = filenames[page]

    st.markdown(
        f"<div class='dish-id-display'>{current_filename} "
        f"(Page {page + 1}/{total})</div>",
        unsafe_allow_html=True
    )

    # Navigation
    with st.container():
        st.markdown("<div class='nav-container'>", unsafe_allow_html=True)
        n = st.columns([1, 1, 1, 1, 1, 1, 1])
        with n[0]:
            if st.button("⏮️ First", use_container_width=True):
                st.session_state.v7_page = 0; st.rerun()
        with n[1]:
            if st.button("◀️ Prev", use_container_width=True, disabled=page <= 0):
                st.session_state.v7_page -= 1; st.rerun()
        with n[2]:
            page_input = st.number_input("p", min_value=1, max_value=total,
                value=page + 1, label_visibility="collapsed", key="v7_page_num")
        with n[3]:
            if st.button("Go", use_container_width=True):
                st.session_state.v7_page = int(page_input) - 1; st.rerun()
        with n[4]:
            if st.button("Next ▶️", use_container_width=True, disabled=page >= total - 1):
                st.session_state.v7_page += 1; st.rerun()
        with n[5]:
            if st.button("Last ⏭️", use_container_width=True):
                st.session_state.v7_page = total - 1; st.rerun()
        with n[6]:
            st.markdown(f"**{page + 1}/{total}**")
        st.markdown("</div>", unsafe_allow_html=True)

    # ── Layout: ground truth | image | 4 model columns ───────────────────────
    gt_col, img_col, models_area = st.columns([1, 1, 5])

    with gt_col:
        food_name = food_name_from_filename(current_filename)
        st.markdown(f"""
<div class="model-container">
<div class="model-title" style="color:#2ca02c;">Ground Truth</div>

<div class="section-title">Actual Food</div>
<div class="content-box">{food_name}</div>

<div class="section-title">Dataset</div>
<div class="content-box">Food-101</div>

<div class="section-title">Filename</div>
<div class="content-box">{current_filename}</div>
</div>""", unsafe_allow_html=True)

    with img_col:
        img_path = image_index.get(current_filename)
        if img_path and os.path.exists(img_path):
            try:
                st.markdown("<div class='image-container'>", unsafe_allow_html=True)
                st.image(Image.open(img_path), width='stretch')
                st.markdown(
                    f"<div class='filename-text'>{current_filename}</div>",
                    unsafe_allow_html=True
                )
                st.markdown("</div>", unsafe_allow_html=True)
            except Exception as e:
                st.error(f"Image error: {e}")
        else:
            st.warning("No local image for this record.")

    with models_area:
        model_names = list(MODEL_FILES.keys())
        cols = st.columns(len(model_names))
        for col, model_name in zip(cols, model_names):
            with col:
                record = all_indices.get(model_name, {}).get(current_filename)
                display_model_card(record, model_name)

    # ── Calorie Accuracy Statistics (across all 100 images) ──────────────────
    st.markdown("---")
    st.markdown("## 📊 Calorie Sanity Check — Statistics Across All Images")
    st.caption(
        f"A prediction **passes** if reported calories are within "
        f"±{int(CALORIE_TOLERANCE*100)}% of macro-calculated calories "
        f"(Protein×4 + Carbs×4 + Fat×9 kcal)."
    )

    stat_cols = st.columns(len(all_indices))
    for col, (model_name, record_index) in zip(stat_cols, all_indices.items()):
        stats = compute_calorie_stats(record_index)
        color = MODEL_COLORS.get(model_name, "#333")
        with col:
            pass_color = "#2ca02c" if stats["pass_rate"] >= 50 else "#d9534f"
            st.markdown(f"""
<div class="stats-container">
  <div class="stats-title" style="color:{color};">{model_name}</div>

  <div class="stat-box">
    <div class="stat-value" style="color:{pass_color};">{stats['pass_rate']}%</div>
    <div class="stat-label">Calorie Pass Rate</div>
  </div>

  <div class="stat-box">
    <div class="stat-value">{stats['passed']}/{stats['checked']}</div>
    <div class="stat-label">Images Passed / Checked</div>
  </div>

  <div class="stat-box">
    <div class="stat-value">{stats['avg_diff']}%</div>
    <div class="stat-label">Avg Difference from Expected</div>
  </div>

  <div class="stat-box">
    <div class="stat-value">{stats['total']}</div>
    <div class="stat-label">Total Images</div>
  </div>
</div>""", unsafe_allow_html=True)


def run_version7():
    main()


if __name__ == "__main__":
    run_version7()
