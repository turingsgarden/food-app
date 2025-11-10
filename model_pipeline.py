# model_pipeline.py
import sys
import os
import time
from datetime import datetime
from PIL import Image
from io import BytesIO
from dotenv import load_dotenv
from pymongo import MongoClient
from pydantic_ai import Agent
from pydantic_ai.models.gemini import GeminiModel
from pydantic import BaseModel, Field, field_validator
from typing import List, Optional
import traceback
import base64

# Load environment variables
load_dotenv()

# MongoDB Setup
mongo_uri = os.getenv("MONGO_URI")
mongo_db = os.getenv("MONGO_DB", "food-app-swift")
if mongo_uri:
    client = MongoClient(mongo_uri)
    db = client[mongo_db]
    meals_collection = db["meals"]
else:
    print("⚠️ MongoDB connection not available")
    meals_collection = None

# Define Pydantic Models
class Ingredient(BaseModel):
    name: str = Field(description="Ingredient name (e.g., 'tomato', 'olive oil', 'salt')")
    quantity: float = Field(description="Quantity as a number")
    unit: str = Field(description="Unit (g, ml, pieces, etc)")
    category: str = Field(default="visible", description="Either 'visible' or 'hidden'")

class NutritionInfo(BaseModel):
    calories: float = Field(description="Total calories in kcal", ge=0)
    protein: float = Field(description="Protein in grams", ge=0)
    fat: float = Field(description="Total fat in grams", ge=0)
    carbohydrates: float = Field(description="Carbohydrates in grams", ge=0)
    fiber: float = Field(description="Fiber in grams", ge=0)
    sugar: float = Field(description="Sugar in grams", ge=0)
    sodium: float = Field(description="Sodium in milligrams", ge=0)

class FoodAnalysisResult(BaseModel):
    dish_name: str = Field(description="Main dish name identified in the image")
    all_ingredients: List[Ingredient] = Field(description="ALL ingredients including smallest ones")
    nutrition: NutritionInfo = Field(description="Total nutrition information")
    confidence: float = Field(default=0.9, description="Analysis confidence score")

# Food Analysis Service with Pydantic
class FoodAnalysisService:
    def __init__(self):
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not set")
            
        # Initialize the Gemini model
        model = GeminiModel('gemini-2.0-flash', api_key=api_key)
        
        self.analysis_agent = Agent(
            model,
            result_type=FoodAnalysisResult,
            system_prompt=(
                "You are an expert food analyst with deep knowledge of ingredients and nutrition. "
                "Your task is to analyze food images with EXTREME attention to detail.\n\n"
                "CRITICAL INSTRUCTIONS:\n"
                "1. IDENTIFY EVERY SINGLE INGREDIENT - including the smallest garnishes, seasonings, herbs, spices\n"
                "2. Look for:\n"
                "   - Main ingredients (proteins, vegetables, grains)\n"
                "   - Small visible items (sesame seeds, pepper flakes, herb leaves)\n"
                "   - Sauces and dressings\n"
                "   - Garnishes (parsley, scallions, cilantro)\n"
                "   - Cooking ingredients (oil sheen, butter)\n"
                "   - Hidden ingredients (salt, sugar in sauces, stock/broth)\n"
                "3. For each ingredient, mark as 'visible' if you can see it, 'hidden' if likely used\n"
                "4. Use appropriate units: g for solids, ml for liquids, pieces for countable items\n"
                "5. Calculate accurate nutrition based on ALL ingredients\n"
                "6. Even tiny amounts matter - include them!\n"
                "7. If you see seeds, nuts, or small toppings - LIST THEM\n"
                "8. If there's a sauce - break down its likely ingredients"
            )
        )
    
    def analyze_image(self, image_path: str, user_id: str) -> dict:
        """Analyze food image and return structured results"""
        
        print(f"🔍 Starting Pydantic analysis for user: {user_id}")
        print(f"📸 Image: {image_path}")
        
        start_time = time.time()
        
        try:
            # Validate and preprocess image
            is_valid, message = self.validate_image(image_path)
            if not is_valid:
                raise ValueError(f"Invalid image: {message}")
            
            # Read and encode image
            image_data = self._prepare_image_data(image_path)
            
            # Run analysis with detailed prompt
            result = self.analysis_agent.run_sync(
                f"Analyze this food image comprehensively. "
                f"Remember to identify EVERY ingredient including:\n"
                f"- Smallest garnishes and herbs\n"
                f"- Seeds, nuts, and toppings\n"
                f"- All spices and seasonings visible\n"
                f"- Hidden cooking ingredients\n"
                f"- Sauce components\n"
                f"User ID for tracking: {user_id}",
                message_history=[
                    {"role": "user", "content": [
                        {"type": "text", "text": "Analyze this food image"},
                        {"type": "image", "data": image_data, "mime_type": "image/jpeg"}
                    ]}
                ]
            )
            
            analysis_time = time.time() - start_time
            print(f"✅ Analysis completed in {analysis_time:.2f} seconds")
            
            # Convert to legacy format for compatibility
            return self._convert_to_legacy_format(result.data)
            
        except Exception as e:
            print(f"❌ Analysis error: {str(e)}")
            traceback.print_exc()
            # Return default structure on error
            return self._get_default_result()
    
    def _prepare_image_data(self, image_path: str) -> str:
        """Prepare image data as base64"""
        try:
            image = Image.open(image_path)
            
            # Resize if too large
            max_size = (1024, 1024)
            image.thumbnail(max_size, Image.Resampling.LANCZOS)
            
            # Convert to RGB
            if image.mode not in ('RGB', 'L'):
                image = image.convert('RGB')
            
            # Save to bytes buffer
            buffer = BytesIO()
            image.save(buffer, 'JPEG', quality=85)
            buffer.seek(0)
            
            # Encode to base64
            image_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
            return image_base64
            
        except Exception as e:
            print(f"❌ Image preparation error: {str(e)}")
            raise
    
    def _convert_to_legacy_format(self, result: FoodAnalysisResult) -> dict:
        """Convert Pydantic result to legacy format for compatibility"""
        
        # Separate visible and hidden ingredients
        visible_ingredients = [i for i in result.all_ingredients if i.category == 'visible']
        hidden_ingredients = [i for i in result.all_ingredients if i.category == 'hidden']
        
        # Format ingredients as pipe-separated strings
        visible_text = '\n'.join([
            f"{ing.name} | {ing.quantity} | {ing.unit} | Visible in image"
            for ing in visible_ingredients
        ])
        
        hidden_text = '\n'.join([
            f"{ing.name} | {ing.quantity} | {ing.unit} | Likely used in cooking"
            for ing in hidden_ingredients
        ])
        
        # Format nutrition as pipe-separated
        nutrition_text = f"""Calories|{int(result.nutrition.calories)}|kcal
Protein|{result.nutrition.protein:.1f}|g
Fat|{result.nutrition.fat:.1f}|g
Carbohydrates|{result.nutrition.carbohydrates:.1f}|g
Fiber|{result.nutrition.fiber:.1f}|g
Sugar|{result.nutrition.sugar:.1f}|g
Sodium|{int(result.nutrition.sodium)}|mg"""
        
        return {
            'dish_prediction': result.dish_name,
            'image_description': visible_text,
            'hidden_ingredients': hidden_text,
            'nutrition_info': nutrition_text,
            'analysis_method': 'pydantic_structured',
            'ingredient_count': {
                'visible': len(visible_ingredients),
                'hidden': len(hidden_ingredients),
                'total': len(result.all_ingredients)
            }
        }
    
    def validate_image(self, image_path: str) -> tuple:
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
    
    def _get_default_result(self) -> dict:
        """Return default result on error"""
        return {
            'dish_prediction': 'Unable to analyze',
            'image_description': 'Analysis failed | 0 | items | Error',
            'hidden_ingredients': '',
            'nutrition_info': 'Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg',
            'error': True
        }

# Initialize service as singleton
_service_instance = None

def get_food_analysis_service():
    """Get or create the food analysis service instance"""
    global _service_instance
    if _service_instance is None:
        _service_instance = FoodAnalysisService()
    return _service_instance

# Main analysis function (replaces old one)
def full_image_analysis(image_path: str, user_id: str) -> dict:
    """Main entry point for image analysis - now using Pydantic"""
    try:
        service = get_food_analysis_service()
        result = service.analyze_image(image_path, user_id)
        
        # Add metadata
        result['user_id'] = user_id
        result['analysis_time'] = time.time()
        
        print(f"📊 Analysis complete:")
        print(f"  - Dish: {result.get('dish_prediction', 'Unknown')}")
        print(f"  - Ingredients: {result.get('ingredient_count', {})}")
        
        return result
        
    except Exception as e:
        print(f"❌ Full analysis error: {str(e)}")
        traceback.print_exc()
        
        return {
            'dish_prediction': 'Analysis failed',
            'image_description': 'Unable to process | 0 | items | Error',
            'hidden_ingredients': '',
            'nutrition_info': 'Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg',
            'user_id': user_id,
            'analysis_time': 0,
            'error': str(e)
        }

# Nutrition recalculation function
def recalculate_nutrition_enhanced(ingredients_text: str) -> str:
    """Recalculate nutrition from ingredients using Pydantic model"""
    try:
        service = get_food_analysis_service()
        
        # Parse ingredients from text
        ingredients = []
        for line in ingredients_text.split('\n'):
            if '|' in line:
                parts = line.split('|')
                if len(parts) >= 3:
                    ingredients.append({
                        'name': parts[0].strip(),
                        'quantity': parts[1].strip(),
                        'unit': parts[2].strip()
                    })
        
        if not ingredients:
            return "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"
        
        # Use agent to calculate nutrition
        ingredients_str = ', '.join([f"{i['quantity']} {i['unit']} {i['name']}" for i in ingredients])
        
        result = service.analysis_agent.run_sync(
            f"Calculate the total nutrition for these ingredients: {ingredients_str}. "
            f"Provide accurate nutrition values."
        )
        
        # Format nutrition response
        nutrition = result.data.nutrition
        return f"""Calories|{int(nutrition.calories)}|kcal
Protein|{nutrition.protein:.1f}|g
Fat|{nutrition.fat:.1f}|g
Carbohydrates|{nutrition.carbohydrates:.1f}|g
Fiber|{nutrition.fiber:.1f}|g
Sugar|{nutrition.sugar:.1f}|g
Sodium|{int(nutrition.sodium)}|mg"""
        
    except Exception as e:
        print(f"❌ Nutrition recalculation error: {str(e)}")
        return "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"

# Keep validate_image_for_analysis for backward compatibility
def validate_image_for_analysis(image_path: str) -> tuple:
    """Validate image before analysis - backward compatibility"""
    service = get_food_analysis_service()
    return service.validate_image(image_path)