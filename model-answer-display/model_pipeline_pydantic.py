# model_pipeline_pydantic.py
import sys
import os
import time
from datetime import datetime
from PIL import Image
from io import BytesIO
from dotenv import load_dotenv
from pymongo import MongoClient
from pydantic_ai import Agent, BinaryContent
from pydantic import BaseModel, Field, validator
from typing import List
import re
from typing import Tuple

# Load environment variables
load_dotenv()

# MongoDB Setup
mongo_uri = os.getenv("MONGO_URI")
mongo_db = os.getenv("MONGO_DB", "food-app-swift")
client = MongoClient(mongo_uri)
db = client[mongo_db]
meals_collection = db["meals"]

# Define Pydantic Models
class Ingredient(BaseModel):
    name: str = Field(description="Ingredient name")
    # quantity: float = Field(description="Quantity")
    quantity_range: Tuple[float, float] = Field(description="Estimated quantity range (min, max)")
    unit: str = Field(description="Unit - use 'g' for solids, 'ml' for liquids")
    _original_unit: str = None  # Internal field to store original unit

    @validator('unit', pre=True)
    def validate_and_store_unit(cls, v, values):
        """Validate and normalize units, store original unit for conversion"""
        original_unit = v.lower().strip()
        
        # Solid units mapping to grams
        solid_units = {'g', 'gram', 'grams', 'gr', 'gm', 'kg', 'kilogram', 'kilograms'}
        
        # Liquid units mapping to ml
        liquid_units = {'ml', 'milliliter', 'milliliters', 'l', 'liter', 'liters', 'cup', 'cups', 'tsp', 'teaspoon', 'teaspoons', 'tbsp', 'tablespoon', 'tablespoons'}
        
        # Store original unit in the instance
        if hasattr(cls, '_original_unit'):
            cls._original_unit = original_unit
        
        if original_unit in solid_units:
            return 'g'
        elif original_unit in liquid_units:
            return 'ml'
        else:
            # Default to grams for unknown units
            return 'g'

    @validator('quantity_range', always=True)
    def convert_quantity(cls, v, values):
        """Convert quantity to standardized units (g or ml)"""
        if 'unit' not in values:
            return v
            
        # Get the original unit that was passed in
        original_unit = getattr(cls, '_original_unit', None)
        if not original_unit:
            return v
            
        # Solid unit conversions to grams
        solid_conversion = {
            'kg': 1000, 'kilogram': 1000, 'kilograms': 1000,
            'g': 1, 'gram': 1, 'grams': 1, 'gr': 1, 'gm': 1
        }
        
        # Liquid unit conversions to ml
        liquid_conversion = {
            'l': 1000, 'liter': 1000, 'liters': 1000,
            'ml': 1, 'milliliter': 1, 'milliliters': 1,
            'cup': 240, 'cups': 240,
            'tsp': 5, 'teaspoon': 5, 'teaspoons': 5,
            'tbsp': 15, 'tablespoon': 15, 'tablespoons': 15
        }
        
        # # Apply conversion based on original unit
        # if original_unit in solid_conversion:
        #     converted_quantity = v * solid_conversion[original_unit]
        #     print(f"Converted {v} {original_unit} to {converted_quantity} g")
        #     return converted_quantity
        # elif original_unit in liquid_conversion:
        #     converted_quantity = v * liquid_conversion[original_unit]
        #     print(f"Converted {v} {original_unit} to {converted_quantity} ml")
        #     return converted_quantity
        
        # return v
        # Apply conversion to BOTH numbers in the tuple (min, max)
        if original_unit in solid_conversion:
            mult = solid_conversion[original_unit]
            return (v[0] * mult, v[1] * mult) # v is a tuple (min, max)
            
        elif original_unit in liquid_conversion:
            mult = liquid_conversion[original_unit]
            return (v[0] * mult, v[1] * mult)
        
        return v

# class NutritionInfo(BaseModel):
#     calories: float = Field(description="Calories in kcal", ge=0)
#     protein: float = Field(description="Protein in grams", ge=0)
#     fat: float = Field(description="Fat in grams", ge=0)
#     carbohydrates: float = Field(description="Carbohydrates in grams", ge=0)
#     fiber: float = Field(description="Fiber in grams", ge=0)
#     sugar: float = Field(description="Sugar in grams", ge=0)
#     sodium: float = Field(description="Sodium in milligrams", ge=0)

class NutritionInfo(BaseModel):
    calories: Tuple[float, float] = Field(description="Calories range in kcal", min_items=2, max_items=2)
    protein: Tuple[float, float] = Field(description="Protein range in grams")
    fat: Tuple[float, float] = Field(description="Fat range in grams")
    carbohydrates: Tuple[float, float] = Field(description="Carbohydrates range in grams")
    fiber: Tuple[float, float] = Field(description="Fiber range in grams")
    sugar: Tuple[float, float] = Field(description="Sugar range in grams")
    sodium: Tuple[float, float] = Field(description="Sodium range in milligrams")

class FoodAnalysisResult(BaseModel):
    dish_names: List[str] = Field(description="Identified dish names - only the main dish")
    visible_ingredients: List[Ingredient] = Field(description="Visible ingredients")
    hidden_ingredients: List[Ingredient] = Field(description="Hidden ingredients")
    nutrition: NutritionInfo = Field(description="Nutrition information")
    analysis_timestamp: datetime = Field(default_factory=datetime.now)

    @validator('dish_names')
    def validate_dish_names(cls, v):
        """Ensure only the main dish is returned"""
        if v:
            # Return only the first (main) dish
            return [v[0]]
        return v

# Helper function
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

class FoodAnalysisService:
    def __init__(self):
        # self.analysis_agent = Agent(
        #     'google-gla:gemini-2.5-flash',
        #     output_type=FoodAnalysisResult,
        #     system_prompt=(
        #         "You are a professional food analysis expert. "
        #         "Analyze food images to identify dishes, ingredients, and estimate nutrition. "
        #         "Be thorough and accurate in your analysis. "
        #         "IMPORTANT INSTRUCTIONS:\n"
        #         "1. For units: use 'g' for solid ingredients, 'ml' for liquid ingredients\n"
        #         "2. For nutrition information: use kcal for calories, g for protein/fat/carbs/fiber/sugar, mg for sodium\n"
        #         "3. For dish names: identify ONLY the main dish (the most prominent food item in the image)\n"
        #         "4. For ingredients: DO NOT include source dish names in the ingredient list\n"
        #         "5. Estimate quantities and nutrition based on standard portion sizes\n"
        #         "Identify all visible ingredients with quantities using correct units, "
        #         "estimate hidden cooking ingredients, and calculate nutrition information."
        #     )
        # )
        self.analysis_agent = Agent(
    'google-gla:gemini-2.5-flash',
    output_type=FoodAnalysisResult,
    system_prompt=(
        "You are a professional food analysis expert. "
        "Analyze food images to identify dishes, ingredients, and estimate nutrition. "
        "For all ingredients, provide quantity ranges (e.g., 80-120g for solids, 150-250ml for liquids). "
        "For nutrition, provide estimated ranges (e.g., calories: 500-600 kcal). "
        "Use 'g' for solids, 'ml' for liquids. "
        "Return ONLY the main dish. "
        "Do NOT include source dish names."
    )
)

    def full_analysis_pydantic(self, image_path: str, user_id: str) -> FoodAnalysisResult:
        """Complete Pydantic version analysis using BinaryContent"""
        
        print(f"Starting Pydantic analysis for user: {user_id}")
        print(f"Image: {image_path}")
        
        start_time = time.time()
        
        # Validate image first
        is_valid, message = validate_image_for_analysis(image_path)
        if not is_valid:
            raise ValueError(f"Invalid image: {message}")
        
        try:
            # Preprocess image and get bytes
            image_bytes = self._preprocess_image(image_path)
            
            # Use BinaryContent to pass the image
            # result = self.analysis_agent.run_sync(
            #     [
            #         f"Comprehensively analyze this food image. User ID: {user_id}\n"
            #         "IMPORTANT: Follow these exact formats:\n"
            #         "- Use 'g' for solids, 'ml' for liquids\n" 
            #         "- Nutrition: calories(kcal), protein(g), fat(g), carbs(g), fiber(g), sugar(g), sodium(mg)\n"
            #         "- Return ONLY the main dish name\n"
            #         "- For ingredients: List only name, quantity, unit - NO source dish names\n"
            #         "- Be precise with quantities and nutrition estimates",
            #         BinaryContent(data=image_bytes, media_type='image/jpeg')
            #     ]
            # )
            result = self.analysis_agent.run_sync(
    [
        f"Comprehensively analyze this food image. User ID: {user_id}\n"
        "IMPORTANT: Follow these exact formats:\n"
        "- Use 'g' for solids, 'ml' for liquids\n"
        "- For quantities: Provide a realistic RANGE (e.g., 80-120g, 150-250ml)\n"
        "- Do NOT give exact single numbers\n"
        "- Nutrition: Provide estimated RANGE values in this format,formatted as [min, max]:\n"
        "  calories(kcal), protein(g), fat(g), carbs(g), fiber(g), sugar(g), sodium(mg)\n"
        "- Return ONLY the main dish name\n"
        "- For ingredients: List only name, quantity_range, unit - NO source dish names\n"
        "- Use reasonable uncertainty based on visual estimation",
        BinaryContent(data=image_bytes, media_type='image/jpeg')
    ]
)
            
            analysis_time = time.time() - start_time
            print(f"Pydantic analysis completed in {analysis_time:.2f} seconds")
            
            return result.output
            
        except Exception as e:
            print(f"Pydantic analysis error: {str(e)}")
            raise Exception(f"Food analysis failed: {str(e)}")
    
    def _preprocess_image(self, image_path: str) -> bytes:
        """Image preprocessing - using your original optimization logic but returning bytes"""
        try:
            image = Image.open(image_path)
            
            # Resize if too large
            max_size = (1024, 1024)
            image.thumbnail(max_size, Image.Resampling.LANCZOS)
            
            # Convert to RGB if needed
            if image.mode not in ('RGB', 'L'):
                image = image.convert('RGB')
            
            # Save to bytes buffer
            output_buffer = BytesIO()
            image.save(output_buffer, 'JPEG', quality=85)
            output_buffer.seek(0)
            
            print(f"Image preprocessed: {image.size[0]}x{image.size[1]}")
            return output_buffer.getvalue()
            
        except Exception as e:
            print(f"Image preprocessing failed: {str(e)}")
            # Fallback to original image
            with open(image_path, "rb") as f:
                return f.read()
    
    # def save_to_database(self, analysis_result: FoodAnalysisResult, user_id: str):
    #     """Save analysis result to MongoDB"""
    #     try:
    #         document = {
    #             'user_id': user_id,
    #             'dish_names': analysis_result.dish_names,
    #             'visible_ingredients': [
    #                 {
    #                     'name': ing.name,
    #                     'quantity': ing.quantity,
    #                     'unit': ing.unit
    #                 } for ing in analysis_result.visible_ingredients
    #             ],
    #             'hidden_ingredients': [
    #                 {
    #                     'name': ing.name,
    #                     'quantity': ing.quantity,
    #                     'unit': ing.unit
    #                 } for ing in analysis_result.hidden_ingredients
    #             ],
    #             'nutrition': {
    #                 'calories': analysis_result.nutrition.calories,
    #                 'protein': analysis_result.nutrition.protein,
    #                 'fat': analysis_result.nutrition.fat,
    #                 'carbohydrates': analysis_result.nutrition.carbohydrates,
    #                 'fiber': analysis_result.nutrition.fiber,
    #                 'sugar': analysis_result.nutrition.sugar,
    #                 'sodium': analysis_result.nutrition.sodium
    #             },
    #             'analysis_timestamp': analysis_result.analysis_timestamp,
    #             'created_at': datetime.now()
    #         }
            
    #         result = meals_collection.insert_one(document)
    #         print(f"Analysis saved to database with ID: {result.inserted_id}")
    #         return result.inserted_id
            
    #     except Exception as e:
    #         print(f"Database save error: {str(e)}")
    #         raise
    
    def save_to_database(self, analysis_result: FoodAnalysisResult, user_id: str):
        """Save analysis result to MongoDB"""
        try:
            document = {
                'user_id': user_id,
                'dish_names': analysis_result.dish_names,
                'visible_ingredients': [
                    {
                        'name': ing.name,
                        # Changed from ing.quantity to ing.quantity_range
                        'quantity_range': ing.quantity_range, 
                        'unit': ing.unit
                    } for ing in analysis_result.visible_ingredients
                ],
                'hidden_ingredients': [
                    {
                        'name': ing.name,
                        # Changed from ing.quantity to ing.quantity_range
                        'quantity_range': ing.quantity_range,
                        'unit': ing.unit
                    } for ing in analysis_result.hidden_ingredients
                ],
                'nutrition': {
                    'calories': analysis_result.nutrition.calories,
                    'protein': analysis_result.nutrition.protein,
                    'fat': analysis_result.nutrition.fat,
                    'carbohydrates': analysis_result.nutrition.carbohydrates,
                    'fiber': analysis_result.nutrition.fiber,
                    'sugar': analysis_result.nutrition.sugar,
                    'sodium': analysis_result.nutrition.sodium
                },
                'analysis_timestamp': analysis_result.analysis_timestamp,
                'created_at': datetime.now()
            }
            
            result = meals_collection.insert_one(document)
            print(f"Analysis saved to database with ID: {result.inserted_id}")
            return result.inserted_id
            
        except Exception as e:
            print(f"Database save error: {str(e)}")
            raise














 #========================================================================================================================================



#show all food name in one prediction
#run_pydantix_output.py
# import sys
# import os
# import time
# from datetime import datetime
# from PIL import Image
# from io import BytesIO
# from dotenv import load_dotenv
# from pymongo import MongoClient
# from pydantic_ai import Agent, BinaryContent
# from pydantic import BaseModel, Field
# from typing import List

# # Load environment variables
# load_dotenv()

# # MongoDB Setup
# mongo_uri = os.getenv("MONGO_URI")
# mongo_db = os.getenv("MONGO_DB", "food-app-swift")
# client = MongoClient(mongo_uri)
# db = client[mongo_db]
# meals_collection = db["meals"]

# # Define Pydantic Models
# class Ingredient(BaseModel):
#     name: str = Field(description="Ingredient name")
#     quantity: float = Field(description="Quantity")
#     unit: str = Field(description="Unit")
#     source_dish: str = Field(description="Source dish")

# class NutritionInfo(BaseModel):
#     calories: float = Field(description="Calories", ge=0)
#     protein: float = Field(description="Protein(g)", ge=0)
#     fat: float = Field(description="Fat(g)", ge=0)
#     carbohydrates: float = Field(description="Carbohydrates(g)", ge=0)
#     fiber: float = Field(description="Fiber(g)", ge=0)
#     sugar: float = Field(description="Sugar(g)", ge=0)
#     sodium: float = Field(description="Sodium(mg)", ge=0)

# class FoodAnalysisResult(BaseModel):
#     dish_names: List[str] = Field(description="Identified dish names")
#     visible_ingredients: List[Ingredient] = Field(description="Visible ingredients")
#     hidden_ingredients: List[Ingredient] = Field(description="Hidden ingredients")
#     nutrition: NutritionInfo = Field(description="Nutrition information")
#     analysis_timestamp: datetime = Field(default_factory=datetime.now)

# # Helper function
# def validate_image_for_analysis(image_path):
#     """Validate image before analysis"""
#     try:
#         with Image.open(image_path) as img:
#             if img.width < 100 or img.height < 100:
#                 return False, "Image too small for analysis"
            
#             if img.format not in ['JPEG', 'PNG', 'WEBP']:
#                 return False, f"Unsupported format: {img.format}"
            
#             return True, "Image is valid"
            
#     except Exception as e:
#         return False, f"Invalid image: {str(e)}"

# class FoodAnalysisService:
#     def __init__(self):
#         self.analysis_agent = Agent(
#             'google-gla:gemini-2.5-pro',
#             output_type=FoodAnalysisResult,
#             system_prompt=(
#                 "You are a professional food analysis expert. "
#                 "Analyze food images to identify dishes, ingredients, and estimate nutrition. "
#                 "Be thorough and accurate in your analysis. "
#                 "Identify all visible dishes, list visible ingredients with quantities, "
#                 "estimate hidden cooking ingredients, and calculate nutrition information."
#             )
#         )
    
#     def full_analysis_pydantic(self, image_path: str, user_id: str) -> FoodAnalysisResult:
#         """Complete Pydantic version analysis using BinaryContent"""
        
#         print(f"Starting Pydantic analysis for user: {user_id}")
#         print(f"Image: {image_path}")
        
#         start_time = time.time()
        
#         # Validate image first
#         is_valid, message = validate_image_for_analysis(image_path)
#         if not is_valid:
#             raise ValueError(f"Invalid image: {message}")
        
#         try:
#             # Preprocess image and get bytes
#             image_bytes = self._preprocess_image(image_path)
            
#             # Use BinaryContent to pass the image
#             result = self.analysis_agent.run_sync(
#                 [
#                     f"Comprehensively analyze this food image. User ID: {user_id}",
#                     BinaryContent(data=image_bytes, media_type='image/jpeg')
#                 ]
#             )
            
#             analysis_time = time.time() - start_time
#             print(f"Pydantic analysis completed in {analysis_time:.2f} seconds")
            
#             return result.output
            
#         except Exception as e:
#             print(f"Pydantic analysis error: {str(e)}")
#             raise Exception(f"Food analysis failed: {str(e)}")
    
#     def _preprocess_image(self, image_path: str) -> bytes:
#         """Image preprocessing - using your original optimization logic but returning bytes"""
#         try:
#             image = Image.open(image_path)
            
#             # Resize if too large
#             max_size = (1024, 1024)
#             image.thumbnail(max_size, Image.Resampling.LANCZOS)
            
#             # Convert to RGB if needed
#             if image.mode not in ('RGB', 'L'):
#                 image = image.convert('RGB')
            
#             # Save to bytes buffer
#             output_buffer = BytesIO()
#             image.save(output_buffer, 'JPEG', quality=85)
#             output_buffer.seek(0)
            
#             print(f"Image preprocessed: {image.size[0]}x{image.size[1]}")
#             return output_buffer.getvalue()
            
#         except Exception as e:
#             print(f"Image preprocessing failed: {str(e)}")
#             # Fallback to original image
#             with open(image_path, "rb") as f:
#                 return f.read()
    
#     def save_to_database(self, analysis_result: FoodAnalysisResult, user_id: str):
#         """Save analysis result to MongoDB"""
#         try:
#             document = {
#                 'user_id': user_id,
#                 'dish_names': analysis_result.dish_names,
#                 'visible_ingredients': [
#                     {
#                         'name': ing.name,
#                         'quantity': ing.quantity,
#                         'unit': ing.unit,
#                         'source_dish': ing.source_dish
#                     } for ing in analysis_result.visible_ingredients
#                 ],
#                 'hidden_ingredients': [
#                     {
#                         'name': ing.name,
#                         'quantity': ing.quantity,
#                         'unit': ing.unit,
#                         'source_dish': ing.source_dish
#                     } for ing in analysis_result.hidden_ingredients
#                 ],
#                 'nutrition': {
#                     'calories': analysis_result.nutrition.calories,
#                     'protein': analysis_result.nutrition.protein,
#                     'fat': analysis_result.nutrition.fat,
#                     'carbohydrates': analysis_result.nutrition.carbohydrates,
#                     'fiber': analysis_result.nutrition.fiber,
#                     'sugar': analysis_result.nutrition.sugar,
#                     'sodium': analysis_result.nutrition.sodium
#                 },
#                 'analysis_timestamp': analysis_result.analysis_timestamp,
#                 'created_at': datetime.now()
#             }
            
#             result = meals_collection.insert_one(document)
#             print(f"Analysis saved to database with ID: {result.inserted_id}")
#             return result.inserted_id
            
#         except Exception as e:
#             print(f"Database save error: {str(e)}")
#             raise

