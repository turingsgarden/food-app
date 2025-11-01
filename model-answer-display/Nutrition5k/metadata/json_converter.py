import pandas as pd
import json
import os

def convert_nutrition5k_csv(csv_path, output_path):
    """
    Process Nutrition5k special format CSV file
    """
    print("Processing Nutrition5k special format CSV...")
    
    # Read CSV file manually to analyze structure
    with open(csv_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    print(f"Total lines in CSV file: {len(lines)}")
    
    ground_truth_data = []
    successful_records = 0
    
    # Parse each line manually
    for line_num, line in enumerate(lines):
        try:
            fields = line.strip().split(',')
            if len(fields) < 6:  # At least need dish_id and basic nutrition info
                continue
                
            # First field is dish_id
            dish_id = fields[0].strip()
            
            # Skip invalid dish_id
            if not dish_id or dish_id == 'dish_id' or not dish_id.startswith('dish_'):
                continue
            
            # Create image_filename
            image_filename = f"{dish_id}_rgb.png"
            
            # Correct field mapping:
            # According to your example, field order should be:
            # dish_id, total_calories, total_mass, total_fat, total_carb, total_protein, ...
            try:
                nutrition = {
                    "calories": float(fields[1]) if len(fields) > 1 and fields[1] else 0,  # total_calories
                    "fat": float(fields[3]) if len(fields) > 3 and fields[3] else 0,       # total_fat
                    "carbohydrates": float(fields[4]) if len(fields) > 4 and fields[4] else 0,  # total_carb
                    "protein": float(fields[5]) if len(fields) > 5 and fields[5] else 0    # total_protein
                }
            except (ValueError, IndexError) as e:
                print(f"Nutrition info parsing error (line {line_num + 1}): {e}")
                nutrition = {
                    "calories": 0,
                    "protein": 0,
                    "fat": 0,
                    "carbohydrates": 0
                }
            
            # Extract ingredient information
            ingredients = []
            
            # Ingredient info starts from field 6, every 7 fields form one ingredient
            # Format: ingr_id, ingr_name, ingr_grams, calories, fat, carb, protein
            i = 6  # Start from field 6 for first ingredient
            while i + 6 < len(fields):
                try:
                    ingr_id = fields[i]
                    ingr_name = fields[i + 1] if i + 1 < len(fields) else ""
                    ingr_grams = fields[i + 2] if i + 2 < len(fields) else ""
                    
                    # Check if valid ingredient data
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
                    
                    # Move to next ingredient (skip 7 fields)
                    i += 7
                except IndexError:
                    break
            
            # Build data item
            record = {
                "image_filename": image_filename,
                "nutrition": nutrition,
                "ingredients": ingredients
            }
            
            ground_truth_data.append(record)
            successful_records += 1
            
            if successful_records <= 3:  # Print first 3 successful records as examples
                print(f"Successful record {successful_records}: {image_filename}")
                print(f"  Nutrition: {nutrition}")
                print(f"  Number of ingredients: {len(ingredients)}")
                if ingredients:
                    print(f"  First 2 ingredients: {[ing['name'] for ing in ingredients[:2]]}")
                
        except Exception as e:
            if line_num < 10:  # Only show errors for first 10 lines
                print(f"Error processing line {line_num + 1}: {e}")
            continue
    
    # Save as JSON file
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(ground_truth_data, f, indent=2, ensure_ascii=False)
    
    print(f"\nSuccessfully converted {successful_records} records to {output_path}")
    
    # Display some generated image_filename examples
    if successful_records > 0:
        sample_records = ground_truth_data[:3]
        print(f"\nFirst 3 record examples:")
        for i, record in enumerate(sample_records):
            print(f"Record {i + 1}: {record['image_filename']}")
            print(f"  Nutrition info: {record['nutrition']}")
    
    return ground_truth_data

if __name__ == "__main__":
    csv_path = r"C:\Users\PC\OneDrive\Desktop\Nutrify\Nutrition5k\metadata\metadata\dish_metadata_cafe1.csv"
    output_path = r"C:\Users\PC\OneDrive\Desktop\Nutrify\Nutrition5k\metadata\dish_metadata_cafe1.json"
    
    # Ensure output directory exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    # Perform conversion
    convert_nutrition5k_csv(csv_path, output_path)
