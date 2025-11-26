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
import json
from pydantic import BaseModel, Field, field_validator, ValidationError
from typing import List, Optional

# ==================== PYDANTIC MODELS ====================

class Ingredient(BaseModel):
    """Universal ingredient model - works for both visible and hidden"""
    name: str = Field(description="Name of the ingredient")
    quantity: float = Field(description="Numeric quantity/amount")
    unit: str = Field(description="Unit of measurement (g, ml, tbsp, tsp, etc)")
    source: Optional[str] = Field(description="Which dish/purpose this ingredient is for")

    @field_validator('quantity')
    @classmethod
    def validate_quantity(cls, v):
        if v <= 0:
            raise ValueError('Quantity must be positive')
        return v

class DishAnalysis(BaseModel):
    """Complete dish analysis with all ingredients"""
    dish_names: Optional[str] = Field(description="Comma-separated list of all dishes/items")
    visible_ingredients: Optional[list] = Field(description="List of ingredient dicts with name, quantity, unit, source")

class HiddenIngredients(BaseModel):
    """Hidden/cooking ingredients not visible in image"""
    ingredients: Optional[list] = Field(description="List of ingredient dicts with name, quantity, unit")

class NutritionInfo(BaseModel):
    """Complete nutrition information - all fields optional and flat"""
    calories_value: Optional[float] = Field(description="Calorie value")
    calories_unit: Optional[str] = Field(description="Calorie unit (kcal)")
    
    protein_value: Optional[float] = Field(description="Protein value")
    protein_unit: Optional[str] = Field(description="Protein unit (g)")
    
    fat_value: Optional[float] = Field(description="Fat value")
    fat_unit: Optional[str] = Field(description="Fat unit (g)")
    
    carbohydrates_value: Optional[float] = Field(description="Carbohydrates value")
    carbohydrates_unit: Optional[str] = Field(description="Carbohydrates unit (g)")
    
    fiber_value: Optional[float] = Field(description="Fiber value")
    fiber_unit: Optional[str] = Field(description="Fiber unit (g)")
    
    sugar_value: Optional[float] = Field(description="Sugar value")
    sugar_unit: Optional[str] = Field(description="Sugar unit (g)")
    
    sodium_value: Optional[float] = Field(description="Sodium value")
    sodium_unit: Optional[str] = Field(description="Sodium unit (mg)")

# ==================== HELPER FUNCTIONS ====================

def fill_missing_fields(data: dict, context: str = "") -> dict:
    """Fill missing fields in API response before Pydantic validation"""
    
    if context == "ingredients":
        # Fill missing source fields in ingredient dicts
        if 'ingredients' in data and data['ingredients']:
            for ing in data['ingredients']:
                if 'source' not in ing:
                    ing['source'] = "For cooking"
        if 'visible_ingredients' in data and data['visible_ingredients']:
            for ing in data['visible_ingredients']:
                if 'source' not in ing:
                    ing['source'] = "Main dish"
    
    elif context == "nutrition":
        # Fill missing nutrition fields with defaults
        fields = ['calories', 'protein', 'fat', 'carbohydrates', 'fiber', 'sugar', 'sodium']
        units = {'calories': 'kcal', 'sodium': 'mg'}
        
        for field in fields:
            value_key = f"{field}_value"
            unit_key = f"{field}_unit"
            
            if value_key not in data or data[value_key] is None:
                data[value_key] = 0
            if unit_key not in data or data[unit_key] is None:
                data[unit_key] = units.get(field, 'g')
    
    return data

def dict_to_ingredient(ing_dict: dict) -> Ingredient:
    """Convert dict to Ingredient object"""
    return Ingredient(
        name=ing_dict.get('name', 'Unknown'),
        quantity=ing_dict.get('quantity', 0),
        unit=ing_dict.get('unit', 'g'),
        source=ing_dict.get('source')
    )

def ingredients_to_text(ingredients: List, show_source: bool = True) -> str:
    """Convert ingredients (dicts or Ingredient objects) to text format"""
    if not ingredients:
        return "No ingredients found"
    
    lines = []
    for i, ing in enumerate(ingredients, 1):
        # Handle both dict and Ingredient object
        if isinstance(ing, dict):
            name = ing.get('name', 'Unknown')
            quantity = ing.get('quantity', 0)
            unit = ing.get('unit', 'g')
            source = ing.get('source')
        else:
            name = ing.name
            quantity = ing.quantity
            unit = ing.unit
            source = ing.source
        
        if show_source and source:
            lines.append(f"{i}. {name}: {quantity}{unit} (from {source})")
        else:
            lines.append(f"{i}. {name}: {quantity}{unit}")
    
    return "\n".join(lines)

def nutrition_to_text(nutrition: NutritionInfo) -> str:
    """Convert flattened nutrition to text format"""
    lines = [
        f"Calories: {nutrition.calories_value or 0} {nutrition.calories_unit or 'kcal'}",
        f"Protein: {nutrition.protein_value or 0} {nutrition.protein_unit or 'g'}",
        f"Fat: {nutrition.fat_value or 0} {nutrition.fat_unit or 'g'}",
        f"Carbohydrates: {nutrition.carbohydrates_value or 0} {nutrition.carbohydrates_unit or 'g'}",
        f"Fiber: {nutrition.fiber_value or 0} {nutrition.fiber_unit or 'g'}",
        f"Sugar: {nutrition.sugar_value or 0} {nutrition.sugar_unit or 'g'}",
        f"Sodium: {nutrition.sodium_value or 0} {nutrition.sodium_unit or 'mg'}"
    ]
    return "\n".join(lines)

def safe_parse_response(response, model_class, context=""):
    """Safely parse Gemini response into Pydantic model"""
    try:
        if not response or not response.text:
            raise ValueError(f"Empty response from Gemini for {context}")
        
        # Parse JSON
        data = json.loads(response.text)
        
        # Fill missing fields before validation
        data = fill_missing_fields(data, context)
        
        # Validate with Pydantic
        return model_class(**data)
        
    except json.JSONDecodeError as e:
        print(f"JSON decode error in {context}: {e}")
        print(f"Raw response (first 500 chars): {response.text[:500]}...")
        return None
        
    except ValidationError as e:
        print(f"Pydantic validation error in {context}:")
        print(e)
        return None
        
    except Exception as e:
        print(f"Unexpected error parsing {context}: {e}")
        traceback.print_exc()
        return None

def parse_to_dict(ingredients: List) -> dict:
    """Convert ingredients (dicts or objects) to dictionary format"""
    data_dict = {}
    for ing in ingredients:
        # Handle both dict and Ingredient object
        if isinstance(ing, dict):
            name = ing.get('name', 'Unknown')
            quantity = ing.get('quantity', 0)
            unit = ing.get('unit', 'g')
            source = ing.get('source', 'Unknown')
        else:
            name = ing.name
            quantity = ing.quantity
            unit = ing.unit
            source = ing.source or "Unknown"
        
        data_dict[name] = {
            "Quantity Number/Value": quantity,
            "Unit": unit,
            "Reasoning": source
        }
    return data_dict

# ==================== API FUNCTIONS ====================

def call_gemini_with_retries(model, content, max_retries=3, base_delay=5, generation_config=None):
    """Call Gemini API with retries and exponential backoff"""
    for attempt in range(1, max_retries + 1):
        try:
            if generation_config:
                response = model.generate_content(content, generation_config=generation_config)
            else:
                response = model.generate_content(content)
                
            if response and response.text:
                return response
            else:
                raise Exception("Empty or invalid Gemini response")
        
        except Exception as e:
            error_text = str(e)
            print(f"Gemini request failed (attempt {attempt}/{max_retries}): {error_text}")

            if attempt < max_retries:
                # Parse retry delay from error message
                match = re.search(r"retry_delay\s*\{\s*seconds:\s*(\d+)", error_text)
                if not match:
                    match = re.search(r"Please retry in\s*([\d\.]+)s", error_text)
                
                if match:
                    retry_seconds = float(match.group(1)) + 1.0
                    print(f"API suggests retrying in {retry_seconds:.1f}s")
                else:
                    retry_seconds = base_delay * attempt + random.uniform(0, 2)
                    print(f"Using exponential backoff: {retry_seconds:.1f}s")

                time.sleep(retry_seconds)
            else:
                print("All Gemini retries failed.")
                raise

# ==================== ENVIRONMENT SETUP ====================

load_dotenv()

GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEN_API_KEY:
    raise ValueError("GEMINI_API_KEY is not set in environment variables.")

genai.configure(api_key=GEN_API_KEY)

mongo_uri = os.getenv("MONGO_URI")
mongo_db = os.getenv("MONGO_DB", "food-app-swift")
client = MongoClient(mongo_uri)
db = client[mongo_db]
meals_collection = db["meals"]

# ==================== DEFAULT VALUES ====================

def get_default_dish_analysis():
    """Return default dish analysis"""
    return DishAnalysis(
        dish_names="Unknown dish",
        visible_ingredients=[
            {"name": "Unknown", "quantity": 100, "unit": "g", "source": "Main dish"}
        ]
    )

def get_default_hidden_ingredients():
    """Return default hidden ingredients"""
    return HiddenIngredients(ingredients=[
        {"name": "Cooking oil", "quantity": 2, "unit": "tbsp", "source": "For cooking"},
        {"name": "Salt", "quantity": 1, "unit": "tsp", "source": "Seasoning"}
    ])

def get_default_nutrition():
    """Return default nutrition"""
    return NutritionInfo(
        calories_value=500, calories_unit="kcal",
        protein_value=20, protein_unit="g",
        fat_value=15, fat_unit="g",
        carbohydrates_value=60, carbohydrates_unit="g",
        fiber_value=5, fiber_unit="g",
        sugar_value=10, sugar_unit="g",
        sodium_value=800, sodium_unit="mg"
    )

# ==================== IMAGE PROCESSING ====================

def encode_image(image_path):
    """Encode image to base64"""
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def optimize_image(image_path):
    """Optimize image and return base64 data"""
    image = Image.open(image_path)
    
    # Resize if needed
    max_size = (1024, 1024)
    image.thumbnail(max_size, Image.Resampling.LANCZOS)
    
    # Convert to RGB if needed
    if image.mode not in ('RGB', 'L'):
        image = image.convert('RGB')
    
    # Save optimized version temporarily
    optimized_dir = os.path.join(os.path.dirname(image_path), "temp_optimized")
    os.makedirs(optimized_dir, exist_ok=True)
    base_name = os.path.basename(image_path)
    optimized_path = os.path.join(optimized_dir, f"opt_{base_name}.jpg")
    
    image.save(optimized_path, 'JPEG', quality=85)
    image_data = encode_image(optimized_path)
    
    # Clean up temp file
    try:
        if os.path.exists(optimized_path):
            os.remove(optimized_path)
    except Exception as e:
        print(f"Could not delete temp file: {e}")
    
    return image_data

# ==================== MAIN ANALYSIS FUNCTIONS ====================

def analyze_image_with_gemini(image_path, model_name='gemini-2.5-flash'):
    """Analyze image with Gemini"""
    try:
        print(f"Analyzing image with {model_name}...")
        
        gemini_model = genai.GenerativeModel(model_name)
        image_data = optimize_image(image_path)
        
        prompt = """Analyze this food image and identify ALL items present.

For dish_names: List all dishes/items as comma-separated text.

For visible_ingredients: List every ingredient you can SEE with:
- name: ingredient name
- quantity: estimated amount (numeric)
- unit: measurement unit (g, ml, pieces, tbsp, tsp, cup)
- source: which dish this belongs to (optional)

Include all visible components: main dishes, sides, toppings, garnishes, sauces, beverages.
DO NOT include hidden ingredients like cooking oil, salt, or spices."""
        
        generation_config = genai.GenerationConfig(
            response_mime_type="application/json",
            response_schema=DishAnalysis
        )
        
        response = call_gemini_with_retries(
            gemini_model,
            [prompt, {"mime_type": "image/jpeg", "data": image_data}],
            generation_config=generation_config
        )
        
        if response and response.text:
            print(f"{model_name} analysis successful")
            dish_analysis = safe_parse_response(response, DishAnalysis, "ingredients")
            
            if dish_analysis and dish_analysis.dish_names:
                print(f"Parsed dish: {dish_analysis.dish_names}")
                print(f"Ingredients count: {len(dish_analysis.visible_ingredients or [])}")
                return dish_analysis
            else:
                raise Exception("Failed to parse analysis response")
        else:
            raise Exception("Empty response from Gemini")
            
    except Exception as e:
        print(f"{model_name} analysis error: {str(e)}")
        traceback.print_exc()
        return get_default_dish_analysis()

def search_hidden_ingredients(dish_names, visible_ingredients_text, model_name='gemini-2.5-flash'):
    """Find hidden ingredients"""
    try:
        print(f"Searching for hidden ingredients with {model_name}...")
        
        gemini_model = genai.GenerativeModel(model_name)
        
        prompt = f"""Given these dishes: {dish_names}
With visible ingredients:
{visible_ingredients_text}

Identify hidden/cooking ingredients typically used but not visible.
Include: cooking oils, seasonings, marinades, spices, etc.

For each ingredient provide: name, quantity, unit."""
        
        generation_config = genai.GenerationConfig(
            response_mime_type="application/json",
            response_schema=HiddenIngredients
        )
        
        response = call_gemini_with_retries(gemini_model, prompt, generation_config=generation_config)
        
        if response and response.text:
            print(f"Hidden ingredients response received")
            hidden = safe_parse_response(response, HiddenIngredients, "ingredients")
            
            if hidden and hidden.ingredients:
                print(f"Found {len(hidden.ingredients)} hidden ingredients")
                return hidden
            else:
                raise Exception("Failed to parse hidden ingredients")
        else:
            raise Exception("Empty response")
            
    except Exception as e:
        print(f"Hidden ingredients error with {model_name}: {str(e)}")
        return get_default_hidden_ingredients()

def estimate_nutrition_from_ingredients(dish_names, all_ingredients_text, model_name='gemini-2.5-flash'):
    """Estimate nutrition"""
    try:
        print(f"Calculating nutrition with {model_name}...")
        
        gemini_model = genai.GenerativeModel(model_name)
        
        prompt = f"""Calculate total nutrition for: {dish_names}

All ingredients:
{all_ingredients_text}

Provide nutrition facts: calories (kcal), protein (g), fat (g), carbohydrates (g), fiber (g), sugar (g), sodium (mg)"""
        
        generation_config = genai.GenerationConfig(
            response_mime_type="application/json",
            response_schema=NutritionInfo
        )
        
        response = call_gemini_with_retries(gemini_model, prompt, generation_config=generation_config)
        
        if response and response.text:
            nutrition = safe_parse_response(response, NutritionInfo, "nutrition")
            
            if nutrition and nutrition.calories_value is not None:
                print(f"Nutrition calculated: {nutrition.calories_value} kcal")
                return nutrition
            else:
                raise Exception("Failed to parse nutrition response")
        else:
            raise Exception("Empty response")
            
    except Exception as e:
        print(f"Nutrition calculation error with {model_name}: {str(e)}")
        return get_default_nutrition()

# ==================== MAIN PIPELINE ====================

def full_image_analysis(image_path, user_id, model_name='gemini-2.5-flash'):
    """Complete image analysis pipeline"""
    try:
        start_time = time.time()
        
        # Step 1: Analyze image
        dish_analysis = analyze_image_with_gemini(image_path, model_name)
        dish_names = dish_analysis.dish_names or "Unknown dish"
        visible_ingredients = dish_analysis.visible_ingredients or []
        
        # Convert to text
        visible_text = ingredients_to_text(visible_ingredients, show_source=True)
        
        time.sleep(2)  # Rate limiting
        
        # Step 2: Find hidden ingredients
        hidden_analysis = search_hidden_ingredients(dish_names, visible_text, model_name)
        hidden_ingredients = hidden_analysis.ingredients or []
        hidden_text = ingredients_to_text(hidden_ingredients, show_source=False)
        
        time.sleep(2)  # Rate limiting
        
        # Step 3: Calculate nutrition
        all_ingredients = visible_ingredients + hidden_ingredients
        all_ingredients_text = ingredients_to_text(all_ingredients, show_source=False)
        nutrition = estimate_nutrition_from_ingredients(dish_names, all_ingredients_text, model_name)
        
        # Convert to text
        nutrition_text = nutrition_to_text(nutrition)
        
        # Parse for storage
        visible_dict = parse_to_dict(visible_ingredients)
        hidden_dict = parse_to_dict(hidden_ingredients)
        
        analysis_time = time.time() - start_time
        
        print(f"Analysis completed in {analysis_time:.2f} seconds with {model_name}")
        print(f"Dishes: {dish_names}")
        print(f"Visible: {len(visible_dict)} | Hidden: {len(hidden_dict)}")
        
        return {
            'dish_prediction': dish_names,
            'image_description': visible_text,
            'hidden_ingredients': hidden_text,
            'nutrition_info': nutrition_text,
            'analysis_time': analysis_time,
            'user_id': user_id,
            'model_name': model_name,
            'debug_info': {
                'visible_count': len(visible_dict),
                'hidden_count': len(hidden_dict),
                'has_hidden': bool(hidden_text and hidden_text.strip())
            }
        }
        
    except Exception as e:
        print(f"Full analysis error with {model_name}: {str(e)}")
        traceback.print_exc()
        
        default_nutrition = get_default_nutrition()
        return {
            'dish_prediction': "Unknown dish",
            'image_description': "Unknown ingredients",
            'hidden_ingredients': "Cooking oil: 2tbsp\nSalt: 1tsp",
            'nutrition_info': nutrition_to_text(default_nutrition),
            'analysis_time': 0,
            'user_id': user_id,
            'model_name': model_name,
            'error': str(e)
        }

# ==================== UTILITY FUNCTIONS ====================

def recalculate_nutrition_enhanced(ingredients_text, model_name='gemini-2.5-flash'):
    """Recalculate nutrition from ingredients text"""
    try:
        print(f"Recalculating nutrition with {model_name}...")
        
        gemini_model = genai.GenerativeModel(model_name)
        
        prompt = f"""Calculate nutrition for these ingredients:
{ingredients_text}

Provide accurate nutrition facts."""
        
        generation_config = genai.GenerationConfig(
            response_mime_type="application/json",
            response_schema=NutritionInfo
        )
        
        response = call_gemini_with_retries(gemini_model, prompt, generation_config=generation_config)
        
        if response and response.text:
            nutrition = safe_parse_response(response, NutritionInfo, "nutrition")
            
            if nutrition:
                result = nutrition_to_text(nutrition)
                print(f"Recalculated nutrition:\n{result}")
                return result
            else:
                print("Failed to parse response, using defaults")
                return nutrition_to_text(get_default_nutrition())
        else:
            print("No response, using defaults")
            return nutrition_to_text(get_default_nutrition())
            
    except Exception as e:
        print(f"Recalculation error with {model_name}: {str(e)}")
        return nutrition_to_text(get_default_nutrition())

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