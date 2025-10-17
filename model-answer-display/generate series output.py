# filename_extract_check.py
# -*- coding: utf-8 -*-
import json
import os

# 输入文件路径
flash_file = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\Gemini-2.5-flash_food-101_analysis.json"
pro_file   = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\Gemini-2.5-pro_food-101_analysis.json"

# 输出txt文件路径
flash_txt  = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\Gemini-2.5-flash_filenames.txt"
pro_txt    = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\Gemini-2.5-pro_filenames.txt"

def extract_filenames(json_file, output_txt):
    filenames = []
    seen = set()
    missing = 0

    with open(json_file, "r", encoding="utf-8") as f:
        data = json.load(f)

        # 如果是单个对象就转成列表
        if isinstance(data, dict):
            data = [data]

        total_items = len(data)

        for item in data:
            image_path = item.get("image_path", "")
            if image_path:
                filename = os.path.basename(image_path).strip()
                filenames.append(filename)
                seen.add(filename)
            else:
                missing += 1

    # 保存到txt（只写去重后的）
    with open(output_txt, "w", encoding="utf-8") as f:
        for name in sorted(seen):
            f.write(name + "\n")

    print(f"📊 {json_file}")
    print(f"  总条目数: {total_items}")
    print(f"  提取到的文件名数: {len(filenames)} (可能含重复)")
    print(f"  去重后文件名数: {len(seen)}")
    print(f"  丢失image_path的条目: {missing}")
    print(f"✅ 输出文件: {output_txt}\n")

# 分别处理两个文件
extract_filenames(flash_file, flash_txt)
extract_filenames(pro_file, pro_txt)















#unique file
# -*- coding: utf-8 -*-
import os

# 输入文件
flash_txt = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\Gemini-2.5-flash_filenames.txt"
pro_txt = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\Gemini-2.5-pro_filenames.txt"

# 输出文件
flash_unique_txt = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\flash_unique.txt"
pro_unique_txt = r"C:\Users\PC\OneDrive\Desktop\Nutrify\food-app\output\pro_unique.txt"

def read_txt(path):
    with open(path, "r", encoding="utf-8") as f:
        return set(line.strip() for line in f if line.strip())

# 读取文件名集合
flash_set = read_txt(flash_txt)
pro_set = read_txt(pro_txt)

# 对比
flash_unique = flash_set - pro_set
pro_unique = pro_set - flash_set

# 写入结果
with open(flash_unique_txt, "w", encoding="utf-8") as f:
    for name in sorted(flash_unique):
        f.write(name + "\n")

with open(pro_unique_txt, "w", encoding="utf-8") as f:
    for name in sorted(pro_unique):
        f.write(name + "\n")

print(f"✅ 对比完成! flash_unique: {len(flash_unique)} 个, pro_unique: {len(pro_unique)} 个")
