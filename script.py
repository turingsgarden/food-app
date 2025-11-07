# import os, shutil, random

# SRC = "/home/sheru/.cache/kagglehub/datasets/rkuo2000/uecfood256/versions/1"
# DST = os.path.expanduser("~/projects/food-app/datasets/uecfood256-small-random")
# os.makedirs(DST, exist_ok=True)

# # Collect all image paths
# exts = (".jpg", ".jpeg", ".png")
# all_images = []
# for dirpath, _, files in os.walk(SRC):
#     for fn in files:
#         if fn.lower().endswith(exts):
#             all_images.append(os.path.join(dirpath, fn))

# random.shuffle(all_images)

# total_size = 0
# limit = 75 * 1024 * 1024

# for img_path in all_images:
#     rel = os.path.relpath(img_path, SRC)
#     dst_path = os.path.join(DST, rel)
#     os.makedirs(os.path.dirname(dst_path), exist_ok=True)
#     shutil.copy2(img_path, dst_path)
#     total_size += os.path.getsize(dst_path)
#     if total_size >= limit:
#         print(f"✅ Random subset ready ({total_size/1e6:.1f} MB)")
#         break

#above script was to take a random selection of the large ~3gb, below is to add images in csv
# import pandas as pd
# from openpyxl import load_workbook
# from openpyxl.drawing.image import Image as XLImage
# from openpyxl.utils import get_column_letter
# import os

# CSV_PATH = "analysis_results.csv"
# XLSX_PATH = "analysis_results_with_images.xlsx"

# # Step 1: Load CSV
# # df = pd.read_csv(CSV_PATH, sep=",|\t", engine="python")  # supports tab or comma
# df = pd.read_csv(CSV_PATH)
# print(f"Loaded {len(df)} rows")

# # Step 2: Write to Excel first
# df.to_excel(XLSX_PATH, index=False)
# wb = load_workbook(XLSX_PATH)
# ws = wb.active

# # Find column indexes
# headers = [cell.value for cell in ws[1]]
# img_col_idx = headers.index("image_path") + 1  # openpyxl is 1-based
# insert_col_idx = img_col_idx + 1  # add image right next to path

# # Shift other columns to the right of inserted column
# ws.insert_cols(insert_col_idx)
# ws.cell(row=1, column=insert_col_idx, value="Thumbnail")

# # Step 3: Embed image thumbnails
# for row in range(2, ws.max_row + 1):
#     img_path = ws.cell(row=row, column=img_col_idx).value
#     if not os.path.exists(img_path):
#         continue
#     try:
#         img = XLImage(img_path)
#         img.width, img.height = 80, 80  # small thumbnails
#         cell_ref = f"{get_column_letter(insert_col_idx)}{row}"
#         ws.add_image(img, cell_ref)
#         ws.row_dimensions[row].height = 65  # adjust row height
#     except Exception as e:
#         print(f"Skipping {img_path}: {e}")

# # Step 4: Adjust column widths
# for col in range(1, ws.max_column + 1):
#     ws.column_dimensions[get_column_letter(col)].width = 30

# wb.save(XLSX_PATH)
# print(f"✅ Saved Excel file with thumbnails → {XLSX_PATH}")

#below is script to take only random 20 images, and to use those images only - 

# create_20_image_subset.py
import os
import random
import shutil

# Paths
DATASET_ROOT = "datasets/uecfood256-small-random/UECFOOD256"  # original dataset
SUBSET_FOLDER = "datasets/uecfood256-20"  # folder for the 20 selected images

# Print current working directory for debugging
print(f"📍 Current working directory: {os.getcwd()}")
print(f"🔍 Looking for images in: {os.path.abspath(DATASET_ROOT)}")

# Check if source path exists
if not os.path.exists(DATASET_ROOT):
    print(f"\n❌ ERROR: Source path does not exist!")
    print(f"   Looking for: {os.path.abspath(DATASET_ROOT)}")
    print(f"\n💡 Possible solutions:")
    print(f"   1. Run this script from your project root directory")
    print(f"   2. Or change DATASET_ROOT to the full absolute path")
    
    # Try to find the dataset
    possible_roots = [
        "datasets/uecfood256-small-random/UECFOOD256",
        "../datasets/uecfood256-small-random/UECFOOD256",
        "uecfood256-small-random/UECFOOD256",
    ]
    print(f"\n🔎 Checking alternative paths:")
    for path in possible_roots:
        exists = os.path.exists(path)
        print(f"   {'✅' if exists else '❌'} {path}")
        if exists:
            print(f"\n💡 Found it! Update DATASET_ROOT to: {path}")
    exit(1)

print(f"✅ Source path exists!\n")

# Ensure subset folder exists
os.makedirs(SUBSET_FOLDER, exist_ok=True)

# Get all image paths
exts = (".jpg", ".jpeg", ".png")
all_images = []
folder_count = 0

print(f"🔍 Searching for images...")

for dirpath, dirnames, filenames in os.walk(DATASET_ROOT):
    image_files = [fn for fn in filenames if fn.lower().endswith(exts)]
    if image_files:
        folder_count += 1
        for fn in image_files:
            all_images.append(os.path.join(dirpath, fn))

print(f"📊 Found {len(all_images)} images across {folder_count} folders")

if len(all_images) == 0:
    print("\n❌ ERROR: No images found!")
    print(f"   Checked in: {DATASET_ROOT}")
    print(f"\n📁 Directory structure:")
    if os.path.exists(DATASET_ROOT):
        for item in os.listdir(DATASET_ROOT)[:10]:
            print(f"   - {item}")
    exit(1)

if len(all_images) < 20:
    print(f"\n⚠️  WARNING: Only found {len(all_images)} images")
    print(f"   Selecting all {len(all_images)} images")
    subset_images = all_images
else:
    # Deterministically pick 20 images
    random.seed(42)  # fixed seed for reproducibility
    subset_images = random.sample(all_images, 20)
    print(f"✅ Selected 20 random images (seed=42 for reproducibility)")

# Copy selected images to subset folder
print(f"\n📁 Copying to: {os.path.abspath(SUBSET_FOLDER)}")
print(f"─" * 60)

for i, img_path in enumerate(subset_images, 1):
    img_name = os.path.basename(img_path)
    # To avoid filename conflicts, prefix with folder number
    folder_num = os.path.basename(os.path.dirname(img_path))
    new_name = f"{folder_num}_{img_name}"
    dest_path = os.path.join(SUBSET_FOLDER, new_name)
    
    shutil.copy(img_path, dest_path)
    print(f"[{i:2d}/20] ✓ {img_path} → {new_name}")

print(f"─" * 60)
print(f"\n✅ SUCCESS! Created subset with {len(subset_images)} images")
print(f"📂 Location: {os.path.abspath(SUBSET_FOLDER)}")
print(f"\n📝 Sample images:")
for img in os.listdir(SUBSET_FOLDER)[:5]:
    print(f"   - {img}")
if len(os.listdir(SUBSET_FOLDER)) > 5:
    print(f"   ... and {len(os.listdir(SUBSET_FOLDER)) - 5} more")