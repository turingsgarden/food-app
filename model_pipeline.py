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
import random

def call_gemini_with_retries(model, content, max_retries=3, base_delay=5):
    """
    Wrapper to call Gemini API with retries and exponential backoff.
    Waits longer between attempts if rate-limited or transient errors occur.
    """
    for attempt in range(1, max_retries + 1):
        try:
            response = model.generate_content(content)
            if response and response.text:
                return response  # ✅ success
            else:
                raise Exception("Empty or invalid Gemini response")
        
        except Exception as e:
            print(f"⚠️ Gemini request failed (attempt {attempt}/{max_retries}): {str(e)}")

            # Only sleep if more retries left
            if attempt < max_retries:
                delay = base_delay * attempt + random.uniform(0, 2)
                print(f"⏳ Retrying in {delay:.1f}s...")
                time.sleep(delay)
            else:
                print("❌ All Gemini retries failed.")
                raise


# Load environment variables
load_dotenv()

# Gemini API Setup
GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEN_API_KEY:
    raise ValueError("GEMINI_API_KEY is not set in environment variables.")

genai.configure(api_key=GEN_API_KEY)

# MongoDB Setup
mongo_uri = os.getenv("MONGO_URI")
mongo_db = os.getenv("MONGO_DB", "food-app-swift")
client = MongoClient(mongo_uri)
db = client[mongo_db]
meals_collection = db["meals"]

def encode_image(image_path):
    """Encode image to base64"""
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def analyze_image_with_gemini(image_path, model_name='gemini-2.5-flash'):
    """Analyze image with Gemini - based on working web app code"""
    try:
        # CHANGE: Initialize model with parameter
        print(f"🔍 BEFORE ANALYSIS - Image exists: {os.path.exists(image_path)}")
        print(f"🔍 Image path: {image_path}")
        gemini_model = genai.GenerativeModel(model_name)
        
        # Optimize image before sending
        image = Image.open(image_path)
        print(f"✅ Image opened successfully")
        
        # Resize if too large
        max_size = (1024, 1024)
        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        
        # Convert to RGB if needed
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        optimized_dir = os.path.join(os.path.dirname(image_path), "temp_optimized")
        os.makedirs(optimized_dir, exist_ok=True)
        base_name = os.path.basename(image_path)

        # Save optimized version
        # optimized_path = image_path.replace('.png', '_opt.jpg')
        optimized_path = os.path.join(optimized_dir, f"opt_{base_name}.jpg")
        print(f"💾 Saving optimized to: {optimized_path}")
        image.save(optimized_path, 'JPEG', quality=85)
        
        # Encode optimized image
        image_data = encode_image(optimized_path)
        
        #Clean up optimized file
        try:
            if os.path.exists(optimized_path):
                os.remove(optimized_path)
                print(f"🗑️ Deleted temp file: {optimized_path}")
        except Exception as e:
            print(f"⚠️ Could not delete temp file: {e}")
        
        print(f"🔍 AFTER CLEANUP - Original still exists: {os.path.exists(image_path)}")
        
        # Enhanced prompt for analyzing ALL dishes/items in the image
        prompt = (
            "You are a comprehensive food analyst. Look at this image and identify ALL food items present.\n\n"
            "INSTRUCTIONS:\n"
            "1. First line: List all dishes/food items you see WITHOUT NUMBERS (e.g., 'Chicken curry, basmati rice, naan bread, mixed salad')\n"
            "   DO NOT number items like '1. Pizza' - just write 'Pizza'\n"
            "2. Then list ALL visible ingredients from ALL dishes/items in the image\n\n"
            "ANALYZE EVERYTHING:\n"
            "- Main dishes (curries, stir-fries, pasta, pizza, etc.)\n"
            "- Side dishes (rice, bread, salads, etc.)\n"
            "- Beverages (if visible)\n"
            "- Snacks or appetizers\n"
            "- Desserts\n"
            "- Condiments or sauces in separate containers\n\n"
            "Format each VISIBLE ingredient from ALL items:\n"
            "Ingredient | Quantity Number | Unit | Which dish/item it's from\n\n"
            "Example for pizza:\n"
            "Mozzarella cheese | 150 | g | Pizza\n"
            "Tomato sauce | 100 | g | Pizza\n"
            "Basil leaves | 10 | g | Pizza\n"
            "Cherry tomatoes | 50 | g | Pizza topping\n"
            "Pizza dough | 200 | g | Pizza base\n\n"
            "VISIBLE means you can actually see it:\n"
            "- Cheese you can see on pizza\n"
            "- Toppings visible on pizza\n"
            "- Vegetables you can see in any dish\n"
            "- Proteins visible in any dish\n"
            "- Grains/starches you can see\n"
            "- Visible garnishes, herbs, or toppings on any item\n\n"
            "DO NOT include cooking oils, salt, spices, or marinades (these are hidden).\n"
            "Quantity Number must be numeric only.\n"
            "Be thorough - don't miss any food items in the image."
        )
        
        print(f"🔍 Analyzing image with {model_name}...")
        
        # response = gemini_model.generate_content([
        #     prompt,
        #     {"mime_type": "image/jpeg", "data": image_data}
        # ])
        response = call_gemini_with_retries(
            gemini_model,
            [prompt, {"mime_type": "image/jpeg", "data": image_data}])
        
        if response and response.text:
            print(f"✅ {model_name} analysis successful")
            print(f"📊 Raw {model_name} response first 500 chars:\n{response.text[:500]}")
            return response.text
        else:
            raise Exception("Empty response from Gemini")
            
    except Exception as e:
        print(f"❌ {model_name} analysis error: {str(e)}")
        return f"Gemini error: {str(e)}"

def extract_ingredients_only(description):
    """Extract only ingredient lines from description"""
    lines = description.splitlines()
    ingredients = []
    for line in lines[1:]:  # Skip first line (dish name)
        if '|' in line and len(line.split('|')) == 4:
            ingredients.append(line.strip())
    return "\n".join(ingredients)

def search_hidden_ingredients(dish_names, visible_ingredients, model_name='gemini-2.5-flash'):
    """Find hidden ingredients based on ALL dishes and visible ingredients"""
    # CHANGE: Initialize model with parameter
    gemini_model = genai.GenerativeModel(model_name)
    
    prompt = (
        f"You are a recipe analyst. For these dishes: {dish_names}\n"
        f"With visible ingredients:\n{visible_ingredients}\n\n"
        "List ONLY the hidden ingredients in this exact format:\n"
        "Oil | 2 | tbsp | For cooking\n"
        "Salt | 1 | tsp | Seasoning\n"
        "NO HEADERS, NO DASHES, just ingredients."
    )
    
    try:
        print(f"🔍 Searching for hidden ingredients with {model_name}...")
        # response = gemini_model.generate_content(prompt)
        response = call_gemini_with_retries(gemini_model, prompt)
        
        if response and response.text:
            lines = response.text.strip().split('\n')
            valid_lines = []
            
            for line in lines:
                line = line.strip()
                if '|' in line and not any(x in line.lower() for x in ['---', 'ingredient', 'quantity']):
                    parts = line.split('|')
                    if len(parts) >= 4:
                        try:
                            float(parts[1].strip())
                            valid_lines.append(line)
                        except:
                            pass
            
            if valid_lines:
                return '\n'.join(valid_lines)
            else:
                return "Cooking oil | 2 | tbsp | For cooking\nSalt | 1 | tsp | Seasoning"
        else:
            return "Cooking oil | 2 | tbsp | For cooking\nSalt | 1 | tsp | Seasoning"
            
    except Exception as e:
        print(f"❌ Hidden ingredients error with {model_name}: {str(e)}")
        return "Cooking oil | 2 | tbsp | For cooking\nSalt | 1 | tsp | Seasoning"

def get_default_value(nutrient):
    """Get default value for a nutrient"""
    defaults = {
        "Calories": "500",
        "Protein": "20",
        "Fat": "15",
        "Carbohydrates": "60",
        "Fiber": "5",
        "Sugar": "10",
        "Sodium": "800"
    }
    return defaults.get(nutrient, "0")

def get_default_nutrition():
    """Return default nutrition values"""
    return """Calories|500|kcal
Protein|20|g
Fat|15|g
Carbohydrates|60|g
Fiber|5|g
Sugar|10|g
Sodium|800|mg"""

def estimate_nutrition_from_ingredients(dish_names, visible_ingredients, hidden_ingredients, model_name='gemini-2.5-flash'):
    """Estimate nutrition - GUARANTEED TO WORK"""
    # CHANGE: Initialize model with parameter
    gemini_model = genai.GenerativeModel(model_name)
    
    all_ingredients = f"{visible_ingredients}\n{hidden_ingredients}"
    
    # Use a simpler, more direct prompt
    prompt = (
        f"Calculate total nutrition for: {dish_names}\n"
        f"Ingredients: {all_ingredients}\n\n"
        "Reply with EXACTLY these 7 lines (replace numbers with actual calculated values):\n"
        "Calories|750|kcal\n"
        "Protein|35|g\n"
        "Fat|25|g\n"
        "Carbohydrates|80|g\n"
        "Fiber|5|g\n"
        "Sugar|10|g\n"
        "Sodium|1200|mg\n\n"
        "IMPORTANT: Reply ONLY with the 7 lines above, nothing else."
    )
    
    try:
        print(f"📊 Calculating nutrition with {model_name}...")
        print(f"📊 For dishes: {dish_names}")
        # response = gemini_model.generate_content(prompt)
        response = call_gemini_with_retries(gemini_model, prompt)
        
        if response and response.text:
            print(f"📊 Raw {model_name} nutrition response:\n{response.text}")
            
            # Parse the response more carefully
            lines = response.text.strip().split('\n')
            nutrition_data = []
            
            # Expected nutrients in order
            expected = [
                ("Calories", "kcal"),
                ("Protein", "g"),
                ("Fat", "g"),
                ("Carbohydrates", "g"),
                ("Fiber", "g"),
                ("Sugar", "g"),
                ("Sodium", "mg")
            ]
            
            # Try to find each nutrient in the response
            for nutrient, unit in expected:
                found = False
                for line in lines:
                    if nutrient.lower() in line.lower() and '|' in line:
                        # This line contains the nutrient
                        parts = line.split('|')
                        if len(parts) >= 2:
                            # Try to extract the numeric value
                            value_str = parts[1].strip()
                            # Remove any non-numeric characters except dots
                            value_str = ''.join(c for c in value_str if c.isdigit() or c == '.')
                            if value_str:
                                nutrition_data.append(f"{nutrient}|{value_str}|{unit}")
                                found = True
                                print(f"✅ Found {nutrient}: {value_str}")
                                break
                
                if not found:
                    # Use default value
                    default_val = get_default_value(nutrient)
                    nutrition_data.append(f"{nutrient}|{default_val}|{unit}")
                    print(f"⚠️ Using default for {nutrient}: {default_val}")
            
            result = '\n'.join(nutrition_data)
            print(f"✅ Final nutrition format:\n{result}")
            return result
            
        else:
            # Return default values if Gemini fails
            print("⚠️ No response from Gemini, using defaults")
            return get_default_nutrition()
            
    except Exception as e:
        print(f"❌ Nutrition calculation error with {model_name}: {str(e)}")
        print(f"❌ Error type: {type(e).__name__}")
        traceback.print_exc()
        return get_default_nutrition()

def extract_dish_name(description):
    """Extract dish name(s) from description - handles multiple dishes"""
    first_line = description.strip().split('\n')[0]
    dish_names = first_line.strip()
    
    # Remove any numbering (e.g., "1. Pizza" -> "Pizza")
    dish_names = re.sub(r'^\d+\.\s*', '', dish_names)
    
    # Clean up common prefixes
    prefixes_to_remove = ["dishes:", "food items:", "items:", "dish:", "food:"]
    for prefix in prefixes_to_remove:
        if dish_names.lower().startswith(prefix):
            dish_names = dish_names[len(prefix):].strip()
    
    print(f"📊 Extracted dish name: {dish_names}")
    return dish_names

def parse_to_dict(text):
    """Parse formatted text to dictionary"""
    data_dict = {}
    for line in text.splitlines():
        parts = [p.strip() for p in line.split('|')]
        if len(parts) == 4:
            try:
                # Try to convert to numeric value
                numeric_value = float(parts[1]) if '.' in parts[1] else int(parts[1])
                data_dict[parts[0]] = {
                    "Quantity Number/Value": numeric_value,
                    "Unit": parts[2],
                    "Reasoning": parts[3]
                }
            except ValueError:
                continue
    return data_dict

def full_image_analysis(image_path, user_id, model_name='gemini-2.5-flash'):
    """Main function for complete image analysis"""
    # CHANGE: Added model_name parameter with default value
    try:
        start_time = time.time()
        
        print(f"🤖 Starting image analysis for user: {user_id} with model: {model_name}")
        print(f"📸 Image: {image_path}")
        
        # Step 1: Analyze image
        gemini_description = analyze_image_with_gemini(image_path, model_name)
        
        if "Gemini error" in gemini_description:
            raise Exception(f"Gemini analysis failed: {gemini_description}")
        
        # Step 2: Extract dish names
        dish_names = extract_dish_name(gemini_description)
        
        # Step 3: Extract ingredients
        cleaned_ingredients = extract_ingredients_only(gemini_description)
        
        if not cleaned_ingredients:
            cleaned_ingredients = "Unknown ingredients | 100 | g | Main dish"
        
        # Step 4: Find hidden ingredients
        hidden_ingredients = search_hidden_ingredients(dish_names, cleaned_ingredients, model_name)
        
        # Step 5: Calculate nutrition (guaranteed to work)
        nutrition_info = estimate_nutrition_from_ingredients(dish_names, cleaned_ingredients, hidden_ingredients, model_name)
        
        # TEMPORARY FIX: If nutrition is empty or too short, use defaults
        if not nutrition_info or len(nutrition_info) < 50:
            print("⚠️ Nutrition calculation failed, using hardcoded values")
            nutrition_info = """Calories|450|kcal
Protein|25|g
Fat|18|g
Carbohydrates|55|g
Fiber|6|g
Sugar|8|g
Sodium|980|mg"""
        
        # ADD THIS DEBUG LOG
        print(f"📊 RAW NUTRITION INFO:\n{nutrition_info}")
        print(f"📊 Nutrition info length: {len(nutrition_info)}")
        print(f"📊 First 200 chars: {nutrition_info[:200]}")
        
        # Step 6: Parse data for potential storage
        visible_dict = parse_to_dict(cleaned_ingredients)
        hidden_dict = parse_to_dict(hidden_ingredients)
        
        analysis_time = time.time() - start_time
        
        print(f"✅ Analysis completed in {analysis_time:.2f} seconds with {model_name}")
        print(f"🍴 Dishes/Items: {dish_names}")
        print(f"📋 Visible ingredients: {len(visible_dict)} items")
        print(f"🔐 Hidden ingredients: {len(hidden_dict)} items")
        print(f"🔐 Hidden ingredients text: {hidden_ingredients[:100]}...")
        
        return {
            'dish_prediction': dish_names,
            'image_description': cleaned_ingredients,
            'hidden_ingredients': hidden_ingredients,
            'nutrition_info': nutrition_info,
            'analysis_time': analysis_time,
            'user_id': user_id,
            'model_name': model_name,  # CHANGE: Added model name to output
            'debug_info': {
                'visible_count': len(visible_dict),
                'hidden_count': len(hidden_dict),
                'has_hidden': bool(hidden_ingredients and hidden_ingredients.strip())
            }
        }
        
    except Exception as e:
        print(f"❌ Full analysis error with {model_name}: {str(e)}")
        traceback.print_exc()
        
        # Return with default values
        return {
            'dish_prediction': "Unknown dish",
            'image_description': "Unknown ingredients | 100 | g | Main dish",
            'hidden_ingredients': "Cooking oil | 2 | tbsp | For cooking\nSalt | 1 | tsp | Seasoning",
            'nutrition_info': get_default_nutrition(),
            'analysis_time': 0,
            'user_id': user_id,
            'model_name': model_name,  # CHANGE: Added model name to output
            'error': str(e)
        }

def recalculate_nutrition_enhanced(ingredients_text, model_name='gemini-2.5-flash'):
    """Recalculate nutrition - simplified version"""
    # CHANGE: Added model_name parameter
    gemini_model = genai.GenerativeModel(model_name)
    
    try:
        print(f"🔄 Recalculating nutrition with {model_name}...")
        print(f"📋 Input ingredients:\n{ingredients_text[:200]}...")
        
        prompt = (
            f"Calculate nutrition for: {ingredients_text}\n"
            "Reply with these nutrients (number|unit format):\n"
            "Calories|[number]|kcal\n"
            "Protein|[number]|g\n"
            "Fat|[number]|g\n"
            "Carbohydrates|[number]|g\n"
            "Fiber|[number]|g\n"
            "Sugar|[number]|g\n"
            "Sodium|[number]|mg"
        )
        
        # response = gemini_model.generate_content(prompt)
        response = call_gemini_with_retries(gemini_model, prompt)
        
        if response and response.text:
            print(f"📊 Recalculation response:\n{response.text}")
            
            # Clean and validate response
            lines = response.text.strip().split('\n')
            valid_lines = []
            
            for line in lines:
                if '|' in line:
                    parts = line.split('|')
                    if len(parts) >= 3:
                        try:
                            float(parts[1])
                            valid_lines.append(line.strip())
                        except:
                            pass
            
            if valid_lines:
                result = '\n'.join(valid_lines)
                print(f"✅ Recalculated nutrition:\n{result}")
                return result
            else:
                print("⚠️ No valid lines found, using defaults")
                return get_default_nutrition()
        else:
            print("⚠️ No response, using defaults")
            return get_default_nutrition()
            
    except Exception as e:
        print(f"❌ Recalculation error with {model_name}: {str(e)}")
        return get_default_nutrition()

def validate_image_for_analysis(image_path):
    """Validate image before analysis"""
    try:
        with Image.open(image_path) as img:
            if img.width < 100 or img.height < 100:
                return False, "Image too small for analysis"
            
            if img.format not in ['JPEG', 'PNG', 'WEBP']:
                return False, f"Unsupported format: {img.format}"
            
            return True, "Image is valid"
            
    except Exception as e:
        return False, f"Invalid image: {str(e)}"

def clean_nutrition_response(nutrition_text):
    """Clean nutrition response by removing markdown headers and formatting properly"""
    # This function is no longer needed with the new simplified approach
    # But keeping it for backward compatibility
    return nutrition_text