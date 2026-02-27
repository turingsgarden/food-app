# model_pipeline.py
from PIL import Image
import google.generativeai as genai
import base64
import os
import re
import time
from datetime import datetime
from dotenv import load_dotenv
from pymongo import MongoClient
from io import BytesIO
import traceback
import json

# Load environment variables
load_dotenv()

# Gemini API Setup
GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEN_API_KEY:
    raise ValueError("GEMINI_API_KEY is not set in environment variables.")

genai.configure(api_key=GEN_API_KEY)
gemini_model = genai.GenerativeModel('gemini-2.5-pro')

# MongoDB Setup
mongo_uri = os.getenv("MONGO_URI")
mongo_db = os.getenv("MONGO_DB", "food-app-swift")
if mongo_uri:
    client = MongoClient(mongo_uri)
    db = client[mongo_db]
    meals_collection = db["meals"]
else:
    print("⚠️ MongoDB not configured")
    meals_collection = None

def encode_image(image_path):
    """Encode image to base64"""
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def analyze_image_with_gemini(image_path):
    """Enhanced analysis with validation to ensure REAL detection"""
    try:
        # Optimize image
        image = Image.open(image_path)
        
        # Resize if too large
        max_size = (1024, 1024)
        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        
        # Convert to RGB
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        # ✅ 修复1: 路径 bug 修复，正确处理所有文件格式
        base, _ = os.path.splitext(image_path)
        optimized_path = base + '_opt.jpg'
        image.save(optimized_path, 'JPEG', quality=85)
        
        # Encode image
        image_data = encode_image(optimized_path)
        
        # Clean up
        try:
            os.remove(optimized_path)
        except:
            pass
        
        # CRITICAL PROMPT - FORCE REAL ANALYSIS
        prompt = """CRITICAL: You MUST analyze the ACTUAL image provided. DO NOT use generic or default values.

Look at the ACTUAL food in this image and identify:

1. MAIN DISH NAME (what you actually see):
Write the specific dish name on the first line.

2. VISIBLE INGREDIENTS (what you can actually see in THIS image):
List EVERY ingredient you can SEE in the image:
- Main proteins (chicken, beef, fish, tofu, etc.)
- Vegetables (onions, tomatoes, peppers, etc.)
- Grains/carbs (rice, pasta, bread, etc.)
- ALL garnishes even tiny ones (herbs, seeds, nuts)
- ALL visible seasonings (pepper, paprika, sesame)
- Sauces you can identify
- ANY other visible component

Format EXACTLY as (use realistic quantities based on what you see):
Ingredient name | Quantity | Unit | Visible

IMPORTANT RULES:
- Only list ingredients you can ACTUALLY SEE in THIS specific image
- Use realistic quantities based on portion size
- Include even the smallest visible garnishes
- Do NOT use generic lists
- Do NOT use preset values
- Base everything on THIS SPECIFIC IMAGE

If you cannot clearly identify the food, say "Unable to identify food clearly"."""
        
        print("🔍 Analyzing actual image content...")
        
        response = gemini_model.generate_content([
            prompt,
            {"mime_type": "image/jpeg", "data": image_data}
        ])
        
        if response and response.text:
            # Validate response is not generic
            response_text = response.text.strip()
            
            # Check for actual analysis
            if "unable to identify" in response_text.lower():
                raise Exception("Could not identify food in image")
            
            # Validate we got real ingredients (not empty or too short)
            lines = response_text.split('\n')
            ingredient_lines = [l for l in lines if '|' in l]
            
            if len(ingredient_lines) < 2:
                raise Exception("Insufficient ingredients detected")
            
            print(f"✅ Detected {len(ingredient_lines)} real ingredients")
            print(f"📊 First few ingredients:\n{chr(10).join(ingredient_lines[:3])}")
            
            return response_text
        else:
            raise Exception("Empty response from Gemini")
            
    except Exception as e:
        print(f"❌ Gemini analysis error: {str(e)}")
        raise e  # Re-raise to handle upstream

def search_hidden_ingredients(dish_names, visible_ingredients):
    """Find ACTUAL hidden ingredients based on the specific dish"""
    
    # Only proceed if we have real visible ingredients
    if not visible_ingredients or len(visible_ingredients.split('\n')) < 2:
        return ""
    
    prompt = f"""Based on THIS SPECIFIC dish: {dish_names}
And THESE EXACT visible ingredients:
{visible_ingredients}

What hidden ingredients were ACTUALLY used to cook THIS specific dish?
Think about:
- What oil would be used for THIS dish?
- What seasonings are typical for THIS cuisine?
- What liquid (water/stock/milk) for THIS preparation?
- What thickeners or binders if any?

List ONLY ingredients that would ACTUALLY be used for THIS dish:
Format: Ingredient | Realistic quantity | Unit | Hidden

BE SPECIFIC - match the cuisine and cooking style of the actual dish."""
    
    try:
        print("🔍 Detecting actual hidden ingredients...")
        response = gemini_model.generate_content(prompt)
        
        if response and response.text:
            lines = response.text.strip().split('\n')
            valid_lines = []
            
            for line in lines:
                line = line.strip()
                if '|' in line and len(line.split('|')) >= 4:
                    # Validate it's not a header
                    if not any(x in line.lower() for x in ['ingredient', 'quantity', '---', 'example']):
                        valid_lines.append(line)
            
            if valid_lines:
                print(f"✅ Found {len(valid_lines)} actual hidden ingredients")
                return '\n'.join(valid_lines)
            
        return ""  # Return empty if nothing specific found
            
    except Exception as e:
        print(f"❌ Hidden ingredients error: {str(e)}")
        return ""

def calculate_actual_nutrition(dish_names, all_ingredients):
    """Calculate REAL nutrition based on ACTUAL ingredients"""
    
    if not all_ingredients or len(all_ingredients.split('\n')) < 2:
        raise Exception("Insufficient ingredients for nutrition calculation")
    
    prompt = f"""Calculate the ACTUAL nutritional values for THIS SPECIFIC meal:

Dish: {dish_names}

ACTUAL Ingredients detected:
{all_ingredients}

Instructions:
1. Calculate nutrition based on THESE EXACT ingredients and quantities
2. Sum up the nutritional contribution from EACH ingredient
3. Use real nutritional data (not estimates)
4. Account for cooking losses where applicable

Provide CALCULATED values in EXACTLY this format (no extra text):
Calories|ACTUAL_VALUE|kcal
Protein|ACTUAL_VALUE|g
Fat|ACTUAL_VALUE|g
Carbohydrates|ACTUAL_VALUE|g
Fiber|ACTUAL_VALUE|g
Sugar|ACTUAL_VALUE|g
Sodium|ACTUAL_VALUE|mg

IMPORTANT: Return ONLY the nutrition lines in the exact format above, no other text."""
    
    try:
        print("📊 Calculating actual nutrition from ingredients...")
        response = gemini_model.generate_content(prompt)
        
        if response and response.text:
            # Clean and validate the response
            lines = response.text.strip().split('\n')
            nutrition_data = []
            
            for line in lines:
                line = line.strip()
                if '|' in line:
                    parts = line.split('|')
                    if len(parts) >= 3:
                        nutrient = parts[0].strip()
                        value_str = re.sub(r'[^\d.]', '', parts[1].strip())
                        unit = parts[2].strip()
                        
                        # Validate we got real values
                        if value_str and float(value_str) >= 0:
                            # Ensure proper formatting
                            nutrition_data.append(f"{nutrient}|{value_str}|{unit}")
            
            # Ensure we have all required nutrients
            required_nutrients = {
                "Calories": "kcal",
                "Protein": "g",
                "Fat": "g",
                "Carbohydrates": "g",
                "Fiber": "g",
                "Sugar": "g",
                "Sodium": "mg"
            }
            
            # Create a dict of found nutrients
            found_nutrients = {}
            for line in nutrition_data:
                parts = line.split('|')
                if len(parts) >= 2:
                    nutrient_name = parts[0]
                    for req_nutrient in required_nutrients:
                        if req_nutrient.lower() in nutrient_name.lower():
                            found_nutrients[req_nutrient] = line
                            break
            
            # Build final nutrition with all required nutrients
            final_nutrition = []
            for nutrient, unit in required_nutrients.items():
                if nutrient in found_nutrients:
                    final_nutrition.append(found_nutrients[nutrient])
                else:
                    # Add with 0 value if not found
                    final_nutrition.append(f"{nutrient}|0|{unit}")
            
            result = '\n'.join(final_nutrition)
            print(f"✅ Calculated nutrition successfully")
            print(f"📊 Result:\n{result}")
            return result
        else:
            raise Exception("No response from nutrition calculation")
            
    except Exception as e:
        print(f"❌ Nutrition calculation error: {str(e)}")
        # Return proper format with zeros on error
        return "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"

def full_image_analysis(image_path, user_id):
    """Complete analysis - ✅ 修复2: 3次Gemini调用合并成1次"""
    try:
        start_time = time.time()
        
        print(f"🤖 Starting single-pass analysis for user: {user_id}")
        print(f"📸 Image: {image_path}")

        # ✅ 修复2: 单次调用完成所有分析
        image = Image.open(image_path)
        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')

        base, _ = os.path.splitext(image_path)
        optimized_path = base + '_opt.jpg'
        image.save(optimized_path, 'JPEG', quality=85)
        image_data = encode_image(optimized_path)
        try:
            os.remove(optimized_path)
        except:
            pass

        prompt = """Analyze this food image completely. Return ONLY the sections below, no extra text.

=== DISH NAME ===
[The specific dish name]

=== VISIBLE INGREDIENTS ===
[Each ingredient you can see, one per line:]
Ingredient name | Quantity | Unit | Visible

=== HIDDEN INGREDIENTS ===
[Ingredients used in cooking but not visible, e.g. oil, salt, stock:]
Ingredient name | Quantity | Unit | Hidden

=== NUTRITION ===
[Calculate based on ALL ingredients above:]
Calories|VALUE|kcal
Protein|VALUE|g
Fat|VALUE|g
Carbohydrates|VALUE|g
Fiber|VALUE|g
Sugar|VALUE|g
Sodium|VALUE|mg

Rules:
- Only include ingredients actually present or used
- Use realistic quantities based on portion size
- Nutrition must reflect actual ingredients listed
- No placeholder or example values
- If you cannot identify the food, write "Unable to identify" under DISH NAME"""

        print("🔍 Single-pass Gemini analysis starting...")
        response = gemini_model.generate_content([
            prompt,
            {"mime_type": "image/jpeg", "data": image_data}
        ])

        if not response or not response.text:
            raise Exception("Empty response from Gemini")

        raw = response.text.strip()

        # Check for failed identification
        if "unable to identify" in raw.lower():
            return {
                'dish_prediction': "Could not identify food",
                'image_description': "Analysis failed | 0 | items | Unable to detect",
                'hidden_ingredients': "",
                'nutrition_info': "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg",
                'analysis_time': time.time() - start_time,
                'user_id': user_id,
                'error': "Detection failed: unable to identify food",
                'analysis_confidence': 0
            }

        # Parse sections
        dish_name = ""
        visible_ingredients = []
        hidden_ingredients = []
        nutrition_lines = []
        current_section = None

        for line in raw.split('\n'):
            line = line.strip()
            if not line:
                continue
            if '=== DISH NAME ===' in line:
                current_section = 'dish'
            elif '=== VISIBLE INGREDIENTS ===' in line:
                current_section = 'visible'
            elif '=== HIDDEN INGREDIENTS ===' in line:
                current_section = 'hidden'
            elif '=== NUTRITION ===' in line:
                current_section = 'nutrition'
            elif current_section == 'dish' and not dish_name:
                dish_name = line
            elif current_section == 'visible' and '|' in line:
                parts = line.split('|')
                name = parts[0].strip()
                if len(parts) >= 3 and len(name) > 1 and not any(x in name.lower() for x in ['ingredient', 'quantity', '---']):
                    visible_ingredients.append(line)
            elif current_section == 'hidden' and '|' in line:
                parts = line.split('|')
                name = parts[0].strip()
                if len(parts) >= 3 and len(name) > 1 and not any(x in name.lower() for x in ['ingredient', 'quantity', '---']):
                    hidden_ingredients.append(line)
            elif current_section == 'nutrition' and '|' in line:
                parts = line.split('|')
                if len(parts) >= 3:
                    nutrient = parts[0].strip()
                    value_str = re.sub(r'[^\d.]', '', parts[1].strip())
                    unit = parts[2].strip()
                    if value_str and float(value_str) >= 0:
                        nutrition_lines.append(f"{nutrient}|{value_str}|{unit}")

        # Validate visible ingredients
        if len(visible_ingredients) < 2:
            raise Exception(f"Insufficient ingredients detected (only {len(visible_ingredients)})")

        # Ensure all required nutrients present
        required_nutrients = {
            "Calories": "kcal", "Protein": "g", "Fat": "g",
            "Carbohydrates": "g", "Fiber": "g", "Sugar": "g", "Sodium": "mg"
        }
        found_nutrients = {}
        for line in nutrition_lines:
            parts = line.split('|')
            if len(parts) >= 2:
                for req in required_nutrients:
                    if req.lower() in parts[0].lower():
                        found_nutrients[req] = line
                        break
        final_nutrition = []
        for nutrient, unit in required_nutrients.items():
            if nutrient in found_nutrients:
                final_nutrition.append(found_nutrients[nutrient])
            else:
                final_nutrition.append(f"{nutrient}|0|{unit}")

        nutrition_info = '\n'.join(final_nutrition)
        visible_text = '\n'.join(visible_ingredients)
        hidden_text = '\n'.join(hidden_ingredients)

        analysis_time = time.time() - start_time
        confidence = min(100, len(visible_ingredients) * 10)

        print(f"✅ Single-pass analysis completed in {analysis_time:.2f} seconds")
        print(f"📊 Detection summary:")
        print(f"   - Dish: {dish_name}")
        print(f"   - Visible ingredients: {len(visible_ingredients)}")
        print(f"   - Hidden ingredients: {len(hidden_ingredients)}")
        print(f"   - Confidence: {confidence}%")

        return {
            'dish_prediction': dish_name,
            'image_description': visible_text,
            'hidden_ingredients': hidden_text,
            'nutrition_info': nutrition_info,
            'analysis_time': analysis_time,
            'user_id': user_id,
            'analysis_confidence': confidence,
            'detection_stats': {
                'visible_count': len(visible_ingredients),
                'hidden_count': len(hidden_ingredients),
                'total_ingredients': len(visible_ingredients) + len(hidden_ingredients),
                'method': 'single_pass_v3'
            }
        }

    except Exception as e:
        print(f"❌ Analysis error: {str(e)}")
        traceback.print_exc()
        return {
            'dish_prediction': "Detection failed",
            'image_description': f"Error: {str(e)} | 0 | items | Failed",
            'hidden_ingredients': "",
            'nutrition_info': "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg",
            'analysis_time': 0,
            'user_id': user_id,
            'error': str(e),
            'analysis_confidence': 0
        }

def recalculate_nutrition_enhanced(ingredients_text):
    """Recalculate ACTUAL nutrition from edited ingredients"""
    try:
        if not ingredients_text or len(ingredients_text.split('\n')) < 1:
            raise Exception("No ingredients provided")
        
        print(f"🔄 Recalculating actual nutrition...")
        print(f"📝 Ingredients: {ingredients_text[:200]}...")
        
        prompt = f"""Calculate the ACTUAL nutritional values for these EXACT ingredients:

{ingredients_text}

Instructions:
1. Calculate based on THESE SPECIFIC ingredients and quantities
2. Use real nutritional databases
3. Sum up all contributions
4. DO NOT use generic values

Return CALCULATED values:
Calories|ACTUAL_VALUE|kcal
Protein|ACTUAL_VALUE|g
Fat|ACTUAL_VALUE|g
Carbohydrates|ACTUAL_VALUE|g
Fiber|ACTUAL_VALUE|g
Sugar|ACTUAL_VALUE|g
Sodium|ACTUAL_VALUE|mg"""
        
        response = gemini_model.generate_content(prompt)
        
        if response and response.text:
            # Validate we got real values
            lines = response.text.strip().split('\n')
            has_real_values = False
            
            for line in lines:
                if '|' in line:
                    parts = line.split('|')
                    if len(parts) >= 2:
                        value = re.sub(r'[^\d.]', '', parts[1])
                        if value and float(value) > 0:
                            has_real_values = True
                            break
            
            if has_real_values:
                print("✅ Recalculated real nutrition values")
                return response.text.strip()
            else:
                raise Exception("Failed to calculate real values")
        
        raise Exception("No response from calculation")
            
    except Exception as e:
        print(f"❌ Recalculation failed: {str(e)}")
        return "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"

def validate_image_for_analysis(image_path):
    """Validate image before analysis"""
    try:
        with Image.open(image_path) as img:
            # Check dimensions
            if img.width < 100 or img.height < 100:
                return False, "Image too small for analysis"
            
            # Check format
            if img.format not in ['JPEG', 'PNG', 'WEBP']:
                return False, f"Unsupported format: {img.format}"
            
            # Check if image is not blank
            extrema = img.convert("L").getextrema()
            if extrema == (0, 0) or extrema == (255, 255):
                return False, "Image appears to be blank"
            
            return True, "Image is valid"
            
    except Exception as e:
        return False, f"Invalid image: {str(e)}"





# model_pipeline.py
# from PIL import Image
# import google.generativeai as genai
# import base64
# import os
# import re
# import time
# from datetime import datetime
# from dotenv import load_dotenv
# from pymongo import MongoClient
# from io import BytesIO
# import traceback
# import json

# # Load environment variables
# load_dotenv()

# # Gemini API Setup
# GEN_API_KEY = os.getenv("GEMINI_API_KEY")
# if not GEN_API_KEY:
#     raise ValueError("GEMINI_API_KEY is not set in environment variables.")

# genai.configure(api_key=GEN_API_KEY)
# gemini_model = genai.GenerativeModel('gemini-2.0-flash')

# # MongoDB Setup
# mongo_uri = os.getenv("MONGO_URI")
# mongo_db = os.getenv("MONGO_DB", "food-app-swift")
# if mongo_uri:
#     client = MongoClient(mongo_uri)
#     db = client[mongo_db]
#     meals_collection = db["meals"]
# else:
#     print("⚠️ MongoDB not configured")
#     meals_collection = None

# def encode_image(image_path):
#     """Encode image to base64"""
#     with open(image_path, "rb") as image_file:
#         return base64.b64encode(image_file.read()).decode("utf-8")

# def analyze_image_with_gemini(image_path):
#     """Enhanced analysis with validation to ensure REAL detection"""
#     try:
#         # Optimize image
#         image = Image.open(image_path)
        
#         # Resize if too large
#         max_size = (1024, 1024)
#         image.thumbnail(max_size, Image.Resampling.LANCZOS)
        
#         # Convert to RGB
#         if image.mode not in ('RGB', 'L'):
#             image = image.convert('RGB')
        
#         # Save optimized version
#         optimized_path = image_path.replace('.png', '_opt.jpg')
#         image.save(optimized_path, 'JPEG', quality=85)
        
#         # Encode image
#         image_data = encode_image(optimized_path)
        
#         # Clean up
#         try:
#             os.remove(optimized_path)
#         except:
#             pass
        
#         # CRITICAL PROMPT - FORCE REAL ANALYSIS
#         prompt = """CRITICAL: You MUST analyze the ACTUAL image provided. DO NOT use generic or default values.

# Look at the ACTUAL food in this image and identify:

# 1. MAIN DISH NAME (what you actually see):
# Write the specific dish name on the first line.

# 2. VISIBLE INGREDIENTS (what you can actually see in THIS image):
# List EVERY ingredient you can SEE in the image:
# - Main proteins (chicken, beef, fish, tofu, etc.)
# - Vegetables (onions, tomatoes, peppers, etc.)
# - Grains/carbs (rice, pasta, bread, etc.)
# - ALL garnishes even tiny ones (herbs, seeds, nuts)
# - ALL visible seasonings (pepper, paprika, sesame)
# - Sauces you can identify
# - ANY other visible component

# Format EXACTLY as (use realistic quantities based on what you see):
# Ingredient name | Quantity | Unit | Visible

# IMPORTANT RULES:
# - Only list ingredients you can ACTUALLY SEE in THIS specific image
# - Use realistic quantities based on portion size
# - Include even the smallest visible garnishes
# - Do NOT use generic lists
# - Do NOT use preset values
# - Base everything on THIS SPECIFIC IMAGE

# If you cannot clearly identify the food, say "Unable to identify food clearly"."""
        
#         print("🔍 Analyzing actual image content...")
        
#         response = gemini_model.generate_content([
#             prompt,
#             {"mime_type": "image/jpeg", "data": image_data}
#         ])
        
#         if response and response.text:
#             # Validate response is not generic
#             response_text = response.text.strip()
            
#             # Check for actual analysis
#             if "unable to identify" in response_text.lower():
#                 raise Exception("Could not identify food in image")
            
#             # Validate we got real ingredients (not empty or too short)
#             lines = response_text.split('\n')
#             ingredient_lines = [l for l in lines if '|' in l]
            
#             if len(ingredient_lines) < 2:
#                 raise Exception("Insufficient ingredients detected")
            
#             print(f"✅ Detected {len(ingredient_lines)} real ingredients")
#             print(f"📊 First few ingredients:\n{chr(10).join(ingredient_lines[:3])}")
            
#             return response_text
#         else:
#             raise Exception("Empty response from Gemini")
            
#     except Exception as e:
#         print(f"❌ Gemini analysis error: {str(e)}")
#         raise e  # Re-raise to handle upstream

# def search_hidden_ingredients(dish_names, visible_ingredients):
#     """Find ACTUAL hidden ingredients based on the specific dish"""
    
#     # Only proceed if we have real visible ingredients
#     if not visible_ingredients or len(visible_ingredients.split('\n')) < 2:
#         return ""
    
#     prompt = f"""Based on THIS SPECIFIC dish: {dish_names}
# And THESE EXACT visible ingredients:
# {visible_ingredients}

# What hidden ingredients were ACTUALLY used to cook THIS specific dish?
# Think about:
# - What oil would be used for THIS dish?
# - What seasonings are typical for THIS cuisine?
# - What liquid (water/stock/milk) for THIS preparation?
# - What thickeners or binders if any?

# List ONLY ingredients that would ACTUALLY be used for THIS dish:
# Format: Ingredient | Realistic quantity | Unit | Hidden

# BE SPECIFIC - match the cuisine and cooking style of the actual dish."""
    
#     try:
#         print("🔍 Detecting actual hidden ingredients...")
#         response = gemini_model.generate_content(prompt)
        
#         if response and response.text:
#             lines = response.text.strip().split('\n')
#             valid_lines = []
            
#             for line in lines:
#                 line = line.strip()
#                 if '|' in line and len(line.split('|')) >= 4:
#                     # Validate it's not a header
#                     if not any(x in line.lower() for x in ['ingredient', 'quantity', '---', 'example']):
#                         valid_lines.append(line)
            
#             if valid_lines:
#                 print(f"✅ Found {len(valid_lines)} actual hidden ingredients")
#                 return '\n'.join(valid_lines)
            
#         return ""  # Return empty if nothing specific found
            
#     except Exception as e:
#         print(f"❌ Hidden ingredients error: {str(e)}")
#         return ""

# def calculate_actual_nutrition(dish_names, all_ingredients):
#     """Calculate REAL nutrition based on ACTUAL ingredients"""
    
#     if not all_ingredients or len(all_ingredients.split('\n')) < 2:
#         raise Exception("Insufficient ingredients for nutrition calculation")
    
#     prompt = f"""Calculate the ACTUAL nutritional values for THIS SPECIFIC meal:

# Dish: {dish_names}

# ACTUAL Ingredients detected:
# {all_ingredients}

# Instructions:
# 1. Calculate nutrition based on THESE EXACT ingredients and quantities
# 2. Sum up the nutritional contribution from EACH ingredient
# 3. Use real nutritional data (not estimates)
# 4. Account for cooking losses where applicable

# Provide CALCULATED values in EXACTLY this format (no extra text):
# Calories|ACTUAL_VALUE|kcal
# Protein|ACTUAL_VALUE|g
# Fat|ACTUAL_VALUE|g
# Carbohydrates|ACTUAL_VALUE|g
# Fiber|ACTUAL_VALUE|g
# Sugar|ACTUAL_VALUE|g
# Sodium|ACTUAL_VALUE|mg

# IMPORTANT: Return ONLY the nutrition lines in the exact format above, no other text."""
    
#     try:
#         print("📊 Calculating actual nutrition from ingredients...")
#         response = gemini_model.generate_content(prompt)
        
#         if response and response.text:
#             # Clean and validate the response
#             lines = response.text.strip().split('\n')
#             nutrition_data = []
            
#             for line in lines:
#                 line = line.strip()
#                 if '|' in line:
#                     parts = line.split('|')
#                     if len(parts) >= 3:
#                         nutrient = parts[0].strip()
#                         value_str = re.sub(r'[^\d.]', '', parts[1].strip())
#                         unit = parts[2].strip()
                        
#                         # Validate we got real values
#                         if value_str and float(value_str) >= 0:
#                             # Ensure proper formatting
#                             nutrition_data.append(f"{nutrient}|{value_str}|{unit}")
            
#             # Ensure we have all required nutrients
#             required_nutrients = {
#                 "Calories": "kcal",
#                 "Protein": "g",
#                 "Fat": "g",
#                 "Carbohydrates": "g",
#                 "Fiber": "g",
#                 "Sugar": "g",
#                 "Sodium": "mg"
#             }
            
#             # Create a dict of found nutrients
#             found_nutrients = {}
#             for line in nutrition_data:
#                 parts = line.split('|')
#                 if len(parts) >= 2:
#                     nutrient_name = parts[0]
#                     for req_nutrient in required_nutrients:
#                         if req_nutrient.lower() in nutrient_name.lower():
#                             found_nutrients[req_nutrient] = line
#                             break
            
#             # Build final nutrition with all required nutrients
#             final_nutrition = []
#             for nutrient, unit in required_nutrients.items():
#                 if nutrient in found_nutrients:
#                     final_nutrition.append(found_nutrients[nutrient])
#                 else:
#                     # Add with 0 value if not found
#                     final_nutrition.append(f"{nutrient}|0|{unit}")
            
#             result = '\n'.join(final_nutrition)
#             print(f"✅ Calculated nutrition successfully")
#             print(f"📊 Result:\n{result}")
#             return result
#         else:
#             raise Exception("No response from nutrition calculation")
            
#     except Exception as e:
#         print(f"❌ Nutrition calculation error: {str(e)}")
#         # Return proper format with zeros on error
#         return "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"

# def full_image_analysis(image_path, user_id):
#     """Complete analysis with REAL detection validation"""
#     try:
#         start_time = time.time()
        
#         print(f"🤖 Starting REAL analysis for user: {user_id}")
#         print(f"📸 Image: {image_path}")
        
#         # Step 1: Real image analysis
#         try:
#             gemini_description = analyze_image_with_gemini(image_path)
#         except Exception as e:
#             return {
#                 'dish_prediction': "Could not identify food",
#                 'image_description': "Analysis failed | 0 | items | Unable to detect",
#                 'hidden_ingredients': "",
#                 'nutrition_info': "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg",
#                 'analysis_time': time.time() - start_time,
#                 'user_id': user_id,
#                 'error': f"Detection failed: {str(e)}",
#                 'analysis_confidence': 0
#             }
        
#         # Step 2: Extract actual dish name
#         lines = gemini_description.strip().split('\n')
#         dish_names = lines[0].strip() if lines else "Unknown dish"
        
#         # Validate dish name
#         if len(dish_names) < 3 or "unknown" in dish_names.lower():
#             raise Exception("Could not identify dish")
        
#         print(f"✅ Identified dish: {dish_names}")
        
#         # Step 3: Extract REAL visible ingredients
#         visible_ingredients = []
#         for line in lines[1:]:
#             line = line.strip()
#             if '|' in line and len(line.split('|')) >= 3:
#                 parts = line.split('|')
#                 # Validate it's a real ingredient
#                 ingredient_name = parts[0].strip()
#                 if len(ingredient_name) > 1 and not any(x in ingredient_name.lower() for x in ['ingredient', 'quantity', '---']):
#                     visible_ingredients.append(line)
        
#         visible_text = '\n'.join(visible_ingredients)
        
#         if len(visible_ingredients) < 2:
#             raise Exception(f"Insufficient ingredients detected (only {len(visible_ingredients)})")
        
#         print(f"✅ Found {len(visible_ingredients)} real visible ingredients")
        
#         # Step 4: Find actual hidden ingredients
#         hidden_ingredients = search_hidden_ingredients(dish_names, visible_text)
        
#         # Step 5: Calculate REAL nutrition
#         all_ingredients = visible_text
#         if hidden_ingredients:
#             all_ingredients += '\n' + hidden_ingredients
        
#         try:
#             nutrition_info = calculate_actual_nutrition(dish_names, all_ingredients)
#         except Exception as e:
#             print(f"⚠️ Nutrition calculation failed: {e}")
#             # Still return the detected ingredients even if nutrition fails
#             nutrition_info = "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"
        
#         analysis_time = time.time() - start_time
        
#         # Calculate confidence based on detection quality
#         confidence = min(100, len(visible_ingredients) * 10)
        
#         print(f"✅ REAL analysis completed in {analysis_time:.2f} seconds")
#         print(f"📊 Detection summary:")
#         print(f"   - Dish: {dish_names}")
#         print(f"   - Visible ingredients: {len(visible_ingredients)}")
#         print(f"   - Hidden ingredients: {len(hidden_ingredients.split(chr(10))) if hidden_ingredients else 0}")
#         print(f"   - Confidence: {confidence}%")
        
#         return {
#             'dish_prediction': dish_names,
#             'image_description': visible_text,
#             'hidden_ingredients': hidden_ingredients,
#             'nutrition_info': nutrition_info,
#             'analysis_time': analysis_time,
#             'user_id': user_id,
#             'analysis_confidence': confidence,
#             'detection_stats': {
#                 'visible_count': len(visible_ingredients),
#                 'hidden_count': len(hidden_ingredients.split('\n')) if hidden_ingredients else 0,
#                 'total_ingredients': len(all_ingredients.split('\n')),
#                 'method': 'real_detection_v2'
#             }
#         }
        
#     except Exception as e:
#         print(f"❌ Analysis error: {str(e)}")
#         traceback.print_exc()
        
#         # Return error response - NO defaults
#         return {
#             'dish_prediction': "Detection failed",
#             'image_description': f"Error: {str(e)} | 0 | items | Failed",
#             'hidden_ingredients': "",
#             'nutrition_info': "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg",
#             'analysis_time': 0,
#             'user_id': user_id,
#             'error': str(e),
#             'analysis_confidence': 0
#         }

# def recalculate_nutrition_enhanced(ingredients_text):
#     """Recalculate ACTUAL nutrition from edited ingredients"""
#     try:
#         if not ingredients_text or len(ingredients_text.split('\n')) < 1:
#             raise Exception("No ingredients provided")
        
#         print(f"🔄 Recalculating actual nutrition...")
#         print(f"📝 Ingredients: {ingredients_text[:200]}...")
        
#         prompt = f"""Calculate the ACTUAL nutritional values for these EXACT ingredients:

# {ingredients_text}

# Instructions:
# 1. Calculate based on THESE SPECIFIC ingredients and quantities
# 2. Use real nutritional databases
# 3. Sum up all contributions
# 4. DO NOT use generic values

# Return CALCULATED values:
# Calories|ACTUAL_VALUE|kcal
# Protein|ACTUAL_VALUE|g
# Fat|ACTUAL_VALUE|g
# Carbohydrates|ACTUAL_VALUE|g
# Fiber|ACTUAL_VALUE|g
# Sugar|ACTUAL_VALUE|g
# Sodium|ACTUAL_VALUE|mg"""
        
#         response = gemini_model.generate_content(prompt)
        
#         if response and response.text:
#             # Validate we got real values
#             lines = response.text.strip().split('\n')
#             has_real_values = False
            
#             for line in lines:
#                 if '|' in line:
#                     parts = line.split('|')
#                     if len(parts) >= 2:
#                         value = re.sub(r'[^\d.]', '', parts[1])
#                         if value and float(value) > 0:
#                             has_real_values = True
#                             break
            
#             if has_real_values:
#                 print("✅ Recalculated real nutrition values")
#                 return response.text.strip()
#             else:
#                 raise Exception("Failed to calculate real values")
        
#         raise Exception("No response from calculation")
            
#     except Exception as e:
#         print(f"❌ Recalculation failed: {str(e)}")
#         # Return zeros to indicate failure - don't fake values
#         return "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"

# def validate_image_for_analysis(image_path):
#     """Validate image before analysis"""
#     try:
#         with Image.open(image_path) as img:
#             # Check dimensions
#             if img.width < 100 or img.height < 100:
#                 return False, "Image too small for analysis"
            
#             # Check format
#             if img.format not in ['JPEG', 'PNG', 'WEBP']:
#                 return False, f"Unsupported format: {img.format}"
            
#             # Check if image is not blank
#             extrema = img.convert("L").getextrema()
#             if extrema == (0, 0) or extrema == (255, 255):
#                 return False, "Image appears to be blank"
            
#             return True, "Image is valid"
            
#     except Exception as e:
#         return False, f"Invalid image: {str(e)}"
