def ensure_subset_data(max_images=100):
    data_dir = "subset"
    if os.path.exists(data_dir) and os.listdir(data_dir):
        print("Subset dataset already exists, skipping download.")
        return

    print("Downloading subset dataset from Kaggle...")
    dataset_path = kagglehub.dataset_download("hehelentu/food-101-subset")

    os.makedirs(data_dir, exist_ok=True)
    zip_files = glob.glob(os.path.join(dataset_path, "*.zip"))

    if not zip_files:
        print("No zip files found in downloaded dataset.")
        return

    extracted_count = 0
    for z in zip_files:
        with zipfile.ZipFile(z, "r") as zip_ref:
            for file in zip_ref.namelist():
                if extracted_count >= max_images:
                    break
                zip_ref.extract(file, data_dir)
                extracted_count += 1
        if extracted_count >= max_images:
            break

    print(f"Downloaded and extracted {extracted_count} images. Dataset ready!")
