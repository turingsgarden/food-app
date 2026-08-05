import streamlit as st
import pandas as pd
import os
import re
import glob
from PIL import Image

# ---------------------------------------------------------------------------
# CONFIG - adjust these two paths to match where your files actually live
# ---------------------------------------------------------------------------
EXCEL_PATH = "strict_ingredient_comparison_groundtruth_based.xlsx"
IMAGE_DIR = (
    "/Users/rainou/imagery/realsense_overhead"  # folder containing dish_<id>.jpg images
)

CONFIDENCE_COLORS = {
    "High": "#2ca02c",
    "High (Hidden)": "#5fbf5f",
    "Contained": "#1f77b4",
    "Contained (Hidden)": "#6ba6d6",
    "No Match": "#d62728",
}


def load_data():
    """Load the Detail and Summary sheets from the comparison workbook."""
    try:
        detail_df = pd.read_excel(EXCEL_PATH, sheet_name="Detail")
        summary_df = pd.read_excel(EXCEL_PATH, sheet_name="Summary")
    except FileNotFoundError:
        st.error(f"Workbook not found: {EXCEL_PATH}")
        return None, None
    except Exception as e:
        st.error(f"Error loading workbook: {e}")
        return None, None

    # image_filename is only populated on the first row of each dish group;
    # forward-fill so every ingredient row knows which dish it belongs to.
    detail_df["image_filename"] = detail_df["image_filename"].ffill()

    # dish_1562688426.jpg -> 1562688426
    detail_df["dish_id"] = detail_df["image_filename"].apply(extract_dish_id)

    summary_dict = dict(zip(summary_df["metric"], summary_df["value"]))

    return detail_df, summary_dict


def extract_dish_id(filename):
    if not isinstance(filename, str):
        return None
    match = re.search(r"dish_(\d+)", filename)
    return match.group(1) if match else None


def get_all_images():
    if not os.path.exists(IMAGE_DIR):
        return {}
    image_files = glob.glob(os.path.join(IMAGE_DIR, "*"))
    image_map = {}
    for path in image_files:
        dish_id = extract_dish_id(os.path.basename(path))
        if dish_id:
            image_map[dish_id] = path
    return image_map


def build_dish_index(detail_df):
    """dish_id -> list of ingredient-row dicts, in file order."""
    dish_rows = {}
    dish_order = []
    for dish_id, group in detail_df.groupby("dish_id", sort=False):
        if dish_id is None:
            continue
        dish_rows[dish_id] = group.to_dict("records")
        dish_order.append(dish_id)
    return dish_rows, dish_order


def fmt(value, decimals=1, suffix=""):
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return "—"
    try:
        return f"{float(value):.{decimals}f}{suffix}"
    except (TypeError, ValueError):
        return str(value)


def display_summary_panel(summary_dict):
    rows_html = "".join(
        f"<div class='summary-row'><span>{metric}</span><strong>{value}</strong></div>"
        for metric, value in summary_dict.items()
    )
    st.markdown(
        f"""
        <div class='model-container'>
        <div class='model-title'>Overall Summary</div>
        <div class='content-box' style="white-space:normal;">{rows_html}</div>
        </div>
        """,
        unsafe_allow_html=True,
    )


def display_dish_confidence_breakdown(rows):
    counts = {}
    for r in rows:
        c = r.get("confidence") or "Unknown"
        counts[c] = counts.get(c, 0) + 1

    badges_html = "".join(
        f"<span class='confidence-badge' style='background:{CONFIDENCE_COLORS.get(c, '#999')}'>"
        f"{c}: {n}</span>"
        for c, n in counts.items()
    )
    st.markdown(
        f"""
        <div class='model-container'>
        <div class='model-title'>Confidence Breakdown (this dish)</div>
        <div class='content-box' style="white-space:normal;">{badges_html}</div>
        </div>
        """,
        unsafe_allow_html=True,
    )


def display_ingredient_table(rows, dish_id):
    table_rows_html = []
    for r in rows:
        confidence = r.get("confidence") or "Unknown"
        color = CONFIDENCE_COLORS.get(confidence, "#999")
        table_rows_html.append(
            f"""
            <tr>
                <td>{r.get("gt_name") or "—"}</td>
                <td>{r.get("pred_name") or "—"}</td>
                <td>{fmt(r.get("similarity_score"), 1, "%")}</td>
                <td>{fmt(r.get("gt_qty"), 1, " g")}</td>
                <td>{fmt(r.get("pred_qty"), 1, " g")}</td>
                <td>{fmt(r.get("diff"), 1)}</td>
                <td>{fmt(r.get("abs_diff"), 1)}</td>
                <td>{fmt(r.get("pct_diff"), 1, "%")}</td>
                <td><span class='confidence-badge' style='background:{color}'>{confidence}</span></td>
            </tr>
            """
        )

    table_html = f"""
    <div class='model-container'>
    <div class='model-title'>Ingredient Comparison — Dish {dish_id}</div>
    <table class='ingredient-table'>
        <thead>
            <tr>
                <th>GT Name</th><th>Pred Name</th><th>Sim %</th>
                <th>GT Qty</th><th>Pred Qty</th><th>Diff</th>
                <th>Abs Diff</th><th>Pct Diff</th><th>Confidence</th>
            </tr>
        </thead>
        <tbody>
            {"".join(table_rows_html)}
        </tbody>
    </table>
    </div>
    """
    st.markdown(table_html, unsafe_allow_html=True)


def main():
    st.set_page_config(page_title="Ingredient Comparison Display", layout="wide")

    st.markdown(
        """
        <style>
            .block-container { padding-top: 2rem; padding-bottom: 3rem; max-width: 96% !important; }

            .model-container {
                border: 1px solid #e1e4e8;
                border-radius: 8px;
                padding: 15px;
                margin-bottom: 15px;
                background: white;
            }
            .model-title {
                font-size: 1.2em;
                font-weight: 600;
                color: #1f77b4;
                margin-bottom: 12px;
                padding-bottom: 8px;
                border-bottom: 2px solid #e1e4e8;
            }
            .content-box {
                background: #f8f9fa;
                border-radius: 6px;
                border: 1px solid #e1e4e8;
                padding: 10px;
                font-size: 0.9em;
            }
            .summary-row {
                display: flex;
                justify-content: space-between;
                padding: 4px 2px;
                border-bottom: 1px solid #eee;
            }
            .confidence-badge {
                display: inline-block;
                color: white;
                border-radius: 4px;
                padding: 3px 8px;
                margin: 2px;
                font-size: 0.85em;
                font-weight: 600;
            }
            .ingredient-table {
                width: 100%;
                border-collapse: collapse;
                font-size: 0.88em;
            }
            .ingredient-table th, .ingredient-table td {
                border: 1px solid #e1e4e8;
                padding: 6px 8px;
                text-align: left;
            }
            .ingredient-table th {
                background: #f0f2f5;
            }
            .ingredient-table tbody tr:nth-child(even) {
                background: #fafbfc;
            }
            .dish-id-display {
                font-size: 1.15em;
                font-weight: 600;
                text-align: center;
                padding: 8px;
                background: #f8f9fa;
                border-radius: 6px;
                border: 1px solid #e1e4e8;
                margin-bottom: 10px;
            }
        </style>
        """,
        unsafe_allow_html=True,
    )

    # ---- session state -------------------------------------------------
    if "current_page" not in st.session_state:
        st.session_state.current_page = 0
    if "search_dish_id" not in st.session_state:
        st.session_state.search_dish_id = ""
    if "data_loaded" not in st.session_state:
        st.session_state.data_loaded = False

    if not st.session_state.data_loaded:
        with st.spinner("Loading data..."):
            detail_df, summary_dict = load_data()
            if detail_df is None:
                return
            dish_rows, dish_order = build_dish_index(detail_df)
            image_map = get_all_images()

            st.session_state.dish_rows = dish_rows
            st.session_state.dish_order = dish_order
            st.session_state.summary_dict = summary_dict
            st.session_state.image_map = image_map
            st.session_state.data_loaded = True

    dish_rows = st.session_state.dish_rows
    dish_order = st.session_state.dish_order
    summary_dict = st.session_state.summary_dict
    image_map = st.session_state.image_map

    if not dish_order:
        st.warning("No dishes found in the workbook.")
        return

    st.title("🥗 Ingredient Comparison — Ground Truth vs Prediction")

    # ---- search ----------------------------------------------------
    col1, col2, col3 = st.columns([3, 1, 1])
    with col1:
        search_input = st.text_input(
            "Search by Dish ID:",
            value=st.session_state.search_dish_id,
            placeholder="e.g. 1562688426",
        )
    with col2:
        if st.button("🔍 Search", use_container_width=True):
            if search_input.strip() in dish_order:
                st.session_state.current_page = dish_order.index(search_input.strip())
                st.session_state.search_dish_id = search_input.strip()
                st.success(f"Found dish {search_input.strip()}")
            else:
                st.error(f"Dish ID {search_input.strip()} not found")
    with col3:
        if st.button("📄 Clear", use_container_width=True):
            st.session_state.search_dish_id = ""
            st.session_state.current_page = 0
            st.rerun()

    # ---- pagination --------------------------------------------------
    total_pages = len(dish_order)
    current_page = st.session_state.current_page
    current_dish_id = dish_order[current_page]

    st.markdown(
        f"<div class='dish-id-display'>Dish ID: {current_dish_id} "
        f"(Page {current_page + 1}/{total_pages})</div>",
        unsafe_allow_html=True,
    )

    nav_cols = st.columns(6)
    with nav_cols[0]:
        if st.button("⏮️ First", use_container_width=True):
            st.session_state.current_page = 0
            st.rerun()
    with nav_cols[1]:
        if st.button("◀️ Prev", use_container_width=True, disabled=current_page <= 0):
            st.session_state.current_page -= 1
            st.rerun()
    with nav_cols[2]:
        page_input = st.number_input(
            "Page",
            min_value=1,
            max_value=total_pages,
            value=current_page + 1,
            label_visibility="collapsed",
        )
    with nav_cols[3]:
        if st.button("Go", use_container_width=True):
            st.session_state.current_page = page_input - 1
            st.rerun()
    with nav_cols[4]:
        if st.button(
            "Next ▶️", use_container_width=True, disabled=current_page >= total_pages - 1
        ):
            st.session_state.current_page += 1
            st.rerun()
    with nav_cols[5]:
        if st.button("Last ⏭️", use_container_width=True):
            st.session_state.current_page = total_pages - 1
            st.rerun()

    # ---- main three-column layout -------------------------------------
    rows = dish_rows[current_dish_id]
    col_left, col_mid, col_right = st.columns([1, 1.6, 1])

    with col_left:
        image_path = image_map.get(current_dish_id)
        if image_path:
            try:
                image = Image.open(image_path)
                st.image(image, width="stretch")
                st.caption(os.path.basename(image_path))
            except Exception as e:
                st.error(f"Unable to load image: {e}")
        else:
            st.warning(f"No image found for dish ID: {current_dish_id}")

        display_dish_confidence_breakdown(rows)

    with col_mid:
        display_ingredient_table(rows, current_dish_id)

    with col_right:
        display_summary_panel(summary_dict)


if __name__ == "__main__":
    main()
