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

# Load environment variables
load_dotenv()

# Gemini API Setup
GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEN_API_KEY:
    raise ValueError("GEMINI_API_KEY is not set in environment variables.")

genai.configure(api_key=GEN_API_KEY)
gemini_model = genai.GenerativeModel('gemini-1.5-flash')

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

def analyze_image_with_gemini(image_path):
    """Analyze image with Gemini - based on working web app code"""
    try:
        # Optimize image before sending
        image = Image.open(image_path)
        
        # Resize if too large
        max_size = (1024, 1024)
        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        
        # Convert to RGB if needed
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        # Save optimized version
        optimized_path = image_path.replace('.png', '_opt.jpg')
        image.save(optimized_path, 'JPEG', quality=85)
        
        # Encode optimized image
        image_data = encode_image(optimized_path)
        
        # Clean up optimized file
        try:
            os.remove(optimized_path)
        except:
            pass
        
        # Enhanced prompt for analyzing ALL dishes/items in the image
        prompt = (
            "You are a comprehensive food analyst. Look at this image and identify ALL food items present.\n\n"
            "INSTRUCTIONS:\n"
            "1. First line: List all dishes/food items you see (e.g., 'Chicken curry, basmati rice, naan bread, mixed salad')\n"
            "2. Then list ALL visible ingredients from ALL dishes/items in the image\n\n"
            "ANALYZE EVERYTHING:\n"
            "- Main dishes (curries, stir-fries, pasta, etc.)\n"
            "- Side dishes (rice, bread, salads, etc.)\n"
            "- Beverages (if visible)\n"
            "- Snacks or appetizers\n"
            "- Desserts\n"
            "- Condiments or sauces in separate containers\n\n"
            "Format each VISIBLE ingredient from ALL items:\n"
            "Ingredient | Quantity Number | Unit | Which dish/item it's from\n\n"
            "VISIBLE means you can actually see it:\n"
            "- Vegetables you can see in any dish\n"
            "- Proteins visible in any dish\n"
            "- Grains/starches you can see\n"
            "- Visible garnishes, herbs, or toppings on any item\n"
            "- Bread, naan, or other baked items\n"
            "- Salad ingredients you can identify\n\n"
            "DO NOT include cooking oils, salt, spices, or marinades (these are hidden).\n"
            "Quantity Number must be numeric only.\n"
            "Be thorough - don't miss any food items in the image.\n\n"
            "Example for multiple dishes:\n"
            "Chicken pieces | 150 | g | Main curry dish\n"
            "Basmati rice | 200 | g | Side dish\n"
            "Naan bread | 1 | piece | Bread item\n"
            "Lettuce | 50 | g | Salad\n"
            "Tomatoes | 30 | g | Salad"
        )
        
        print("🔍 Analyzing image with Gemini...")
        
        response = gemini_model.generate_content([
            prompt,
            {"mime_type": "image/jpeg", "data": image_data}
        ])
        
        if response and response.text:
            print("✅ Gemini analysis successful")
            return response.text
        else:
            raise Exception("Empty response from Gemini")
            
    except Exception as e:
        print(f"❌ Gemini analysis error: {str(e)}")
        return f"Gemini error: {str(e)}"

def extract_ingredients_only(description):
    """Extract only ingredient lines from description"""
    lines = description.splitlines()
    ingredients = []
    for line in lines[1:]:  # Skip first line (dish name)
        if '|' in line and len(line.split('|')) == 4:
            ingredients.append(line.strip())
    return "\n".join(ingredients)

def search_hidden_ingredients(dish_names, visible_ingredients):
    """Find hidden ingredients based on ALL dishes and visible ingredients"""
    prompt = (
        f"You are a recipe analyst identifying hidden/non-visible ingredients.\n\n"
        f"DISHES/ITEMS: {dish_names}\n"
        f"VISIBLE INGREDIENTS (what can be seen in the image):\n{visible_ingredients}\n\n"
        "Identify the HIDDEN ingredients likely used for ALL the dishes/items shown.\n"
        "Consider what would be needed to prepare each dish/item.\n\n"
        "HIDDEN INGREDIENTS are typically:\n"
        "- Cooking oils/fats (olive oil, butter, vegetable oil, ghee)\n"
        "- Basic seasonings (salt, black pepper, garlic powder)\n"
        "- Cooking liquids (water, broth, wine used in cooking)\n"
        "- Marinades or sauces that are absorbed/mixed in\n"
        "- Binding agents (eggs in batter, flour for coating)\n"
        "- Spices and herbs that are mixed in (not visible as garnish)\n"
        "- Yeast or baking powder (for bread items)\n\n"
        "For multiple dishes, consider what each would need:\n"
        "- Curries: oil, spices, salt, onions (if not visible)\n"
        "- Rice: water, salt, oil/butter\n"
        "- Bread: flour, yeast, oil, salt (if not visible)\n"
        "- Salads: dressing, oil, vinegar\n\n"
        "IMPORTANT FORMATTING RULES:\n"
        "- DO NOT include header lines\n"
        "- DO NOT include dashed lines (--- or ------)\n"
        "- DO NOT write 'Ingredient | Quantity Number | Unit | Used for which dish/purpose' as a header\n"
        "- Start DIRECTLY with the ingredient data\n\n"
        "Format each hidden ingredient:\n"
        "Ingredient | Quantity Number | Unit | Used for which dish/purpose\n\n"
        "Example OUTPUT (start exactly like this, no headers):\n"
        "Cooking oil | 3 | tbsp | Used for curry and rice preparation\n"
        "Salt | 2 | tsp | Seasoning for curry and rice\n"
        "Cumin powder | 1 | tsp | Spice for curry dish\n"
        "Olive oil | 1 | tbsp | Salad dressing\n\n"
        "Quantity Number must be numeric only.\n"
        "Include ingredients for ALL dishes mentioned."
    )
    
    try:
        print("🔍 Searching for hidden ingredients for all dishes...")
        response = gemini_model.generate_content(prompt)
        
        if response and response.text:
            # Clean up the response
            lines = response.text.strip().split('\n')
            formatted_lines = []
            
            for line in lines:
                line = line.strip()
                
                # Skip header and dashed lines
                if '------' in line or line.startswith('---'):
                    continue
                if line.lower().startswith('ingredient') and 'quantity' in line.lower():
                    continue
                    
                if '|' in line and len(line.split('|')) >= 4:
                    # Additional validation
                    parts = line.split('|')
                    try:
                        float(parts[1].strip())
                        formatted_lines.append(line)
                    except ValueError:
                        continue
            
            if formatted_lines:
                result = '\n'.join(formatted_lines)
                print(f"✅ Hidden ingredients found: {len(formatted_lines)} items for all dishes")
                return result
            else:
                print("⚠️ No properly formatted hidden ingredients found, using defaults")
                return "Cooking oil | 2 | tbsp | Used for cooking dishes\nSalt | 1 | tsp | Basic seasoning for dishes\nWater | 250 | ml | Used for cooking rice/grains"
        else:
            print("⚠️ Empty response for hidden ingredients")
            return "Cooking oil | 2 | tbsp | Used for cooking dishes\nSalt | 1 | tsp | Basic seasoning for dishes"
            
    except Exception as e:
        print(f"❌ Hidden ingredients error: {str(e)}")
        return "Cooking oil | 2 | tbsp | Used for cooking dishes\nSalt | 1 | tsp | Basic seasoning for dishes"
    
def estimate_nutrition_from_ingredients(dish_names, visible_ingredients, hidden_ingredients):
    """Estimate nutrition based on ALL dishes and ingredients"""
    
    # Combine both visible and hidden ingredients for nutrition calculation
    all_ingredients = f"DISHES/ITEMS: {dish_names}\n\nVISIBLE INGREDIENTS:\n{visible_ingredients}\n\nHIDDEN INGREDIENTS:\n{hidden_ingredients}"
    
    prompt = (
        f"You are a nutritionist calculating nutrition for ALL food items shown.\n\n"
        f"COMPLETE MEAL ANALYSIS:\n{all_ingredients}\n\n"
        "Calculate the TOTAL nutritional breakdown for the ENTIRE MEAL (all dishes combined).\n"
        "This represents what one person would consume if they ate all the food shown.\n\n"
        "Output each nutrient on a new line in this exact format:\n"
        "Nutrient | Value | Unit | Reasoning\n"
        "Value must be a numeric value only.\n\n"
        "IMPORTANT RULES:\n"
        "- DO NOT include any header lines\n"
        "- DO NOT include any dashed lines (--- or ------)\n"
        "- DO NOT include markdown formatting\n"
        "- DO NOT write 'Nutrient | Value | Unit | Reasoning' as a header\n"
        "- Start DIRECTLY with the actual nutrient data\n\n"
        "Example OUTPUT (start exactly like this, no headers):\n"
        "Calories | 850 | kcal | From cheese and dough\n"
        "Protein | 35 | g | From cheese and meat toppings\n"
        "Fat | 40 | g | From cheese and oil\n"
        "Carbohydrates | 95 | g | From pizza dough\n"
        "Fiber | 4 | g | From vegetables\n"
        "Sugar | 8 | g | From tomato sauce\n"
        "Sodium | 1800 | mg | From cheese and seasonings\n\n"
        "You MUST include ALL these nutrients: Calories, Protein, Fat, Carbohydrates, Fiber, Sugar, Sodium.\n"
        "Consider ALL items shown - main dishes, sides, beverages, etc.\n"
        "Account for both visible and hidden ingredients in your calculations.\n"
        "Provide realistic portion sizes for a typical meal."
    )
    
    try:
        print("📊 Calculating nutrition for complete meal...")
        response = gemini_model.generate_content(prompt)
        
        if response and response.text:
            # Clean the response before returning
            cleaned_nutrition = clean_nutrition_response(response.text)
            print("✅ Complete meal nutrition calculation done")
            return cleaned_nutrition
        else:
            return "Nutrition estimation failed"
            
    except Exception as e:
        print(f"❌ Nutrition estimation error: {str(e)}")
        return f"Nutrition estimation error: {str(e)}"

def extract_dish_name(description):
    """Extract dish name(s) from description - handles multiple dishes"""
    # Get first line which should contain all dishes
    first_line = description.strip().split('\n')[0]
    
    # Clean up the first line
    dish_names = first_line.strip()
    
    # Remove any prefixes like "Dishes:" or "Food items:"
    prefixes_to_remove = ["dishes:", "food items:", "items:", "dish:", "food:"]
    for prefix in prefixes_to_remove:
        if dish_names.lower().startswith(prefix):
            dish_names = dish_names[len(prefix):].strip()
    
    # If it's a single dish, capitalize properly
    if ',' not in dish_names and ' and ' not in dish_names:
        return dish_names.capitalize()
    
    # For multiple dishes, return as is (already formatted)
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

def full_image_analysis(image_path, user_id):
    """Main function for complete image analysis - based on working web app"""
    try:
        start_time = time.time()
        
        print(f"🤖 Starting image analysis for user: {user_id}")
        print(f"📸 Image: {image_path}")
        
        # Step 1: Get basic description and dish name
        gemini_description = analyze_image_with_gemini(image_path)
        
        if "Gemini error" in gemini_description:
            raise Exception(f"Gemini analysis failed: {gemini_description}")
        
        # Step 2: Extract dish names (could be multiple)
        dish_names = extract_dish_name(gemini_description)
        
        # Step 3: Extract clean ingredients list
        cleaned_ingredients = extract_ingredients_only(gemini_description)
        
        if not cleaned_ingredients:
            raise Exception("No ingredients could be identified from the image")
        
        # Step 4: Find hidden ingredients for all dishes
        hidden_ingredients = search_hidden_ingredients(dish_names, cleaned_ingredients)
        
        # Step 5: Estimate nutrition from ALL ingredients (visible + hidden) for all dishes
        nutrition_info = estimate_nutrition_from_ingredients(dish_names, cleaned_ingredients, hidden_ingredients)
        
        # Step 6: Parse data for potential storage
        visible_dict = parse_to_dict(cleaned_ingredients)
        hidden_dict = parse_to_dict(hidden_ingredients)
        
        analysis_time = time.time() - start_time
        
        print(f"✅ Analysis completed in {analysis_time:.2f} seconds")
        print(f"📍 Dishes/Items: {dish_names}")
        print(f"📍 Visible ingredients: {len(visible_dict)} items")
        print(f"📍 Hidden ingredients: {len(hidden_dict)} items")
        print(f"📍 Hidden ingredients text: {hidden_ingredients[:100]}...")
        
        # Return in format expected by Swift frontend
        return {
            'dish_prediction': dish_names,
            'image_description': cleaned_ingredients,
            'hidden_ingredients': hidden_ingredients,
            'nutrition_info': nutrition_info,
            'analysis_time': analysis_time,
            'user_id': user_id,
            'debug_info': {
                'visible_count': len(visible_dict),
                'hidden_count': len(hidden_dict),
                'has_hidden': bool(hidden_ingredients and hidden_ingredients.strip())
            }
        }
        
    except Exception as e:
        print(f"❌ Full analysis error: {str(e)}")
        
        # Return error response
        error_msg = str(e)
        return {
            'dish_prediction': f"Analysis failed: {error_msg}",
            'image_description': f"Could not identify ingredients | 0 | g | {error_msg}",
            'hidden_ingredients': f"Could not identify | 0 | g | {error_msg}",
            'nutrition_info': f"Calories | 0 | kcal | Analysis failed\nProtein | 0 | g | Analysis failed\nFat | 0 | g | Analysis failed\nCarbohydrates | 0 | g | Analysis failed\nFiber | 0 | g | Analysis failed\nSugar | 0 | g | Analysis failed\nSodium | 0 | mg | Analysis failed",
            'analysis_time': 0,
            'user_id': user_id,
            'error': error_msg
        }

def recalculate_nutrition_enhanced(ingredients_text):
    """Recalculate nutrition based on modified ingredients"""
    try:
        print(f"🔄 Recalculating nutrition...")
        
        prompt = (
            f"You are a nutritionist.\n"
            f"Calculate the exact nutritional values for these ingredients:\n\n{ingredients_text}\n\n"
            "Output each nutrient on a new line in this exact format:\n"
            "Nutrient | Value | Unit | Reasoning\n"
            "Value must be a numeric value only.\n"
            "Include at least: Calories, Protein, Fat, Carbohydrates, Fiber, Sugar, Sodium.\n"
            "Base calculations on the specific quantities provided.\n"
            "Be strict with the format."
        )
        
        response = gemini_model.generate_content(prompt)
        
        if response and response.text:
            # Clean the response before returning
            cleaned_nutrition = clean_nutrition_response(response.text)
            print("✅ Nutrition recalculated successfully")
            return cleaned_nutrition
        else:
            raise Exception("Empty response from Gemini")
            
    except Exception as e:
        print(f"❌ Nutrition recalculation error: {str(e)}")
        error_msg = str(e)
        return f"Calories | 0 | kcal | Recalculation failed: {error_msg}\nProtein | 0 | g | Recalculation failed: {error_msg}\nFat | 0 | g | Recalculation failed: {error_msg}\nCarbohydrates | 0 | g | Recalculation failed: {error_msg}\nFiber | 0 | g | Recalculation failed: {error_msg}\nSugar | 0 | g | Recalculation failed: {error_msg}\nSodium | 0 | mg | Recalculation failed: {error_msg}"


def validate_image_for_analysis(image_path):
    """Validate image before analysis"""
    try:
        with Image.open(image_path) as img:
            # Check minimum size
            if img.width < 100 or img.height < 100:
                return False, "Image too small for analysis"
            
            # Check format
            if img.format not in ['JPEG', 'PNG', 'WEBP']:
                return False, f"Unsupported format: {img.format}"
            
            return True, "Image is valid"
            
    except Exception as e:
        return False, f"Invalid image: {str(e)}"
    
def clean_nutrition_response(nutrition_text):
    lines = nutrition_text.strip().split('\n')
    cleaned_lines = []
    
    for line in lines:
        line = line.strip()
        # Skip problematic lines
        if not line or '------' in line or line.startswith('#') or line.startswith('**'):
            continue
        
        # Ensure proper pipe separation
        if '|' in line:
            parts = [part.strip() for part in line.split('|')]
            if len(parts) >= 3:
                # Ensure the value is numeric
                try:
                    float(parts[1])  # Test if it's a valid number
                    cleaned_lines.append(line)
                except ValueError:
                    print(f"⚠️ Skipping line with non-numeric value: {line}")
                    continue
    
    return '\n'.join(cleaned_lines)