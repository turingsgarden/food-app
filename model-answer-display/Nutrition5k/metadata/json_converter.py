import pandas as pd
import json
import os

def convert_nutrition5k_csv(csv_path, output_path):
    """
    专门处理Nutrition5k特殊格式的CSV文件
    """
    print("正在处理Nutrition5k特殊格式CSV...")
    
    # 手动读取CSV文件来分析结构
    with open(csv_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    print(f"CSV文件总行数: {len(lines)}")
    
    ground_truth_data = []
    successful_records = 0
    
    # 手动解析每一行
    for line_num, line in enumerate(lines):
        try:
            fields = line.strip().split(',')
            if len(fields) < 6:  # 至少需要dish_id和基本营养信息
                continue
                
            # 第一个字段是dish_id
            dish_id = fields[0].strip()
            
            # 跳过无效的dish_id
            if not dish_id or dish_id == 'dish_id' or not dish_id.startswith('dish_'):
                continue
            
            # 创建image_filename
            image_filename = f"{dish_id}_rgb.png"
            
            # 提取营养信息 (字段1-4)
            try:
                nutrition = {
                    "calories": float(fields[1]) if len(fields) > 1 and fields[1] else 0,
                    "protein": float(fields[3]) if len(fields) > 3 and fields[3] else 0,
                    "fat": float(fields[2]) if len(fields) > 2 and fields[2] else 0,
                    "carbohydrates": float(fields[4]) if len(fields) > 4 and fields[4] else 0
                }
            except (ValueError, IndexError):
                nutrition = {
                    "calories": 0,
                    "protein": 0,
                    "fat": 0,
                    "carbohydrates": 0
                }
            
            # 提取成分信息
            ingredients = []
            
            # 成分信息从第6个字段开始，每7个字段为一组成分
            # 格式: ingr_id, ingr_name, ingr_grams, calories, fat, carb, protein
            i = 6  # 从第6个字段开始是第一个成分
            while i + 6 < len(fields):
                try:
                    ingr_id = fields[i]
                    ingr_name = fields[i + 1] if i + 1 < len(fields) else ""
                    ingr_grams = fields[i + 2] if i + 2 < len(fields) else ""
                    
                    # 检查是否是有效的成分数据
                    if (ingr_id and ingr_id.startswith('ingr_') and 
                        ingr_name and ingr_name.strip() and 
                        ingr_grams and ingr_grams.strip()):
                        
                        try:
                            ingredient = {
                                "name": str(ingr_name).strip(),
                                "quantity": float(ingr_grams),
                                "unit": "g"
                            }
                            ingredients.append(ingredient)
                        except (ValueError, TypeError):
                            pass
                    
                    # 移动到下一组成分 (跳过7个字段)
                    i += 7
                except IndexError:
                    break
            
            # 构建数据项 - 使用你想要的格式
            record = {
                "image_filename": image_filename,
                "nutrition": nutrition,
                "ingredients": ingredients
            }
            
            ground_truth_data.append(record)
            successful_records += 1
            
            if successful_records <= 3:  # 打印前3条成功记录作为示例
                print(f"成功记录 {successful_records}: {image_filename}")
                print(f"  营养: {nutrition}")
                print(f"  成分数量: {len(ingredients)}")
                if ingredients:
                    print(f"  前2个成分: {[ing['name'] for ing in ingredients[:2]]}")
                
        except Exception as e:
            if line_num < 10:  # 只显示前10行的错误
                print(f"处理第 {line_num + 1} 行时出错: {e}")
            continue
    
    # 保存为JSON文件 - 现在是数组格式
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(ground_truth_data, f, indent=2, ensure_ascii=False)
    
    print(f"\n成功转换 {successful_records} 条记录到 {output_path}")
    
    # 显示一些生成的image_filename示例
    if successful_records > 0:
        sample_records = ground_truth_data[:3]
        print(f"\n前3条记录示例:")
        for i, record in enumerate(sample_records):
            print(f"记录 {i + 1}: {record['image_filename']}")
    
    return ground_truth_data

if __name__ == "__main__":
    csv_path = r"C:\Users\PC\OneDrive\Desktop\Nutrify\Nutrition5k\metadata\metadata\dish_metadata_cafe1.csv"
    output_path = r"C:\Users\PC\OneDrive\Desktop\Nutrify\Nutrition5k\metadata\dish_metadata_cafe1.json"
    
    # 确保输出目录存在
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    # 进行转换
    convert_nutrition5k_csv(csv_path, output_path)