import torch
from PIL import Image
import google.generativeai as genai
import base64
import os
import re
from datetime import datetime
from pymongo import MongoClient

# Device config
DEVICE = torch.device("mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu")

# Gemini setup
GEN_API_KEY = "AIzaSyAJn4e-AlCoFsgFOJvuc8QA2r2zQDBeBqg"
genai.configure(api_key=os.getenv("GEMINI_API_KEY"))
gemini_model = genai.GenerativeModel('gemini-1.5-flash')

# MongoDB setup
client = MongoClient(os.getenv("MONGO_URI"))
db = client.food_db
users_collection = db.users
ingredients_collection = db.ingredients_data
nutrition_collection = db.nutrition_data

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def analyze_image_with_gemini(image_path):
    image_data = encode_image(image_path)
    prompt = (
        "Describe the food dish in this image.\n"
        "Return the dish name on the first line.\n"
        "Then list each visible ingredient on a new line in the format: Ingredient | Quantity Number | Unit | Reasoning.\n"
        "Quantity Number must be a numeric value only.\n"
        "Avoid vague ranges or approximations like 'a few' or 'some'.\n"
        "Be concise and avoid unnecessary descriptions.\n"
        "Skip any background or utensils."
    )
    try:
        response = gemini_model.generate_content([
            prompt,
            {"mime_type": "image/png", "data": image_data}
        ])
        return response.text
    except Exception as e:
        return f"Gemini error: {str(e)}"

def extract_ingredients_only(description):
    lines = description.splitlines()
    ingredients = []
    for line in lines[1:]:
        if '|' in line and len(line.split('|')) == 4:
            ingredients.append(line.strip())
    return "\n".join(ingredients)

def search_hidden_ingredients(dish_name, visible_ingredients):
    prompt = (
        f"You are a recipe analyst.\n"
        f"For the dish '{dish_name}', given the following visible ingredients:\n{visible_ingredients},\n"
        "list only the likely hidden ingredients used in traditional or common recipes for this dish.\n"
        "Format each hidden ingredient on a new line like this: Ingredient | Quantity Number | Unit | Reasoning.\n"
        "Quantity Number must be a numeric value only.\n"
        "Only include core items like oil, butter, sauces, or spices typically used. Avoid optional or garnish ingredients.\n"
        "Do NOT use any vague descriptions. Be clear and formatted strictly."
    )
    try:
        response = gemini_model.generate_content(prompt)
        return response.text
    except Exception as e:
        return f"Hidden ingredients lookup error: {str(e)}"

def estimate_nutrition_from_ingredients(dish_name, visible_ingredients):
    prompt = (
        f"You are a nutritionist.\n"
        f"The user has provided the visible ingredients from a dish named '{dish_name}'.\n"
        f"Ingredients:\n{visible_ingredients}\n\n"
        "Your task is to output the nutritional breakdown per serving (based on image analysis).\n"
        "Output each nutrient on a new line in this exact format:\n"
        "Nutrient | Value | Unit | Reasoning\n"
        "Value must be a numeric value only.\n"
        "Example:\n"
        "Calories | 720 | kcal | Estimated from rice and cheese.\n"
        "Protein | 32 | g | Chicken and beans contribute majorly.\n\n"
        "Avoid ranges (like 100–200) or vague statements.\n"
        "Include at least these nutrients: Calories, Protein, Fat, Carbohydrates, Fiber, Sugar, Sodium.\n"
        "Be strict with the format."
    )
    try:
        response = gemini_model.generate_content(prompt)
        return response.text
    except Exception as e:
        return f"Nutrition estimation error: {str(e)}"

def extract_dish_name(description):
    match = re.search(r'(?i)(?:dish name[:\-]?)\s*(.*)', description)
    if match:
        return match.group(1).strip().capitalize()
    first_line = description.strip().split('\n')[0]
    return first_line.strip().capitalize()

def parse_to_dict(text):
    data_dict = {}
    for line in text.splitlines():
        parts = [p.strip() for p in line.split('|')]
        if len(parts) == 4:
            try:
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
    gemini_description = analyze_image_with_gemini(image_path)
    dish_name = extract_dish_name(gemini_description)
    cleaned_ingredients = extract_ingredients_only(gemini_description)

    hidden_ingredients = search_hidden_ingredients(dish_name, cleaned_ingredients)
    nutrition_info = estimate_nutrition_from_ingredients(dish_name, cleaned_ingredients)

    visible_dict = parse_to_dict(cleaned_ingredients)
    hidden_dict = parse_to_dict(hidden_ingredients)
    combined_ingredients = {**visible_dict, **hidden_dict}

    ingredients_doc = {
        "user_id": user_id,
        "dish": dish_name,
        "image": os.path.basename(image_path),
        "timestamp": datetime.now().isoformat(),
        "data": combined_ingredients
    }
    nutrition_doc = {
        "user_id": user_id,
        "dish": dish_name,
        "image": os.path.basename(image_path),
        "timestamp": datetime.now().isoformat(),
        "data": parse_to_dict(nutrition_info)
    }

    ingredients_collection.insert_one(ingredients_doc)
    nutrition_collection.insert_one(nutrition_doc)

    return {
        'image_description': gemini_description,
        'dish_prediction': dish_name,
        'hidden_ingredients': hidden_ingredients,
        'nutrition_info': nutrition_info
    }
