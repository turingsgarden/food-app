import os
import glob
import zipfile
import kagglehub

def ensure_subset_data(max_images=100):
    data_dir = "subset"
    os.makedirs(data_dir, exist_ok=True)

    existing_images = glob.glob(os.path.join(data_dir, "*.jpg"))
    existing_count = len(existing_images)
    if existing_count >= max_images:
        print(f"Subset dataset already has {existing_count} images, skipping download.")
        return

    print(f"Downloading subset dataset from Kaggle... (already have {existing_count} images)")
    dataset_path = kagglehub.dataset_download("hehelentu/food-101-subset")

    zip_files = glob.glob(os.path.join(dataset_path, "*.zip"))
    if not zip_files:
        print("No zip files found in downloaded dataset.")
        return

    extracted_count = existing_count
    for z in zip_files:
        with zipfile.ZipFile(z, "r") as zip_ref:
            for file in zip_ref.namelist():

                if not file.lower().endswith(".jpg"):
                    continue

                target_path = os.path.join(data_dir, os.path.basename(file))
                if os.path.exists(target_path):
                    continue
                zip_ref.extract(file, data_dir)
                extracted_count += 1
                if extracted_count >= max_images:
                    break
        if extracted_count >= max_images:
            break

    print(f"Downloaded and extracted {extracted_count - existing_count} new images. Total now: {extracted_count}")
