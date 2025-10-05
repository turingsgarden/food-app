import os, shutil, random

SRC = "/home/sheru/.cache/kagglehub/datasets/rkuo2000/uecfood256/versions/1"
DST = os.path.expanduser("~/datasets/uecfood256-small-random")
os.makedirs(DST, exist_ok=True)

# Collect all image paths
exts = (".jpg", ".jpeg", ".png")
all_images = []
for dirpath, _, files in os.walk(SRC):
    for fn in files:
        if fn.lower().endswith(exts):
            all_images.append(os.path.join(dirpath, fn))

random.shuffle(all_images)

total_size = 0
limit = 500 * 1024 * 1024

for img_path in all_images:
    rel = os.path.relpath(img_path, SRC)
    dst_path = os.path.join(DST, rel)
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    shutil.copy2(img_path, dst_path)
    total_size += os.path.getsize(dst_path)
    if total_size >= limit:
        print(f"✅ Random subset ready ({total_size/1e6:.1f} MB)")
        break
