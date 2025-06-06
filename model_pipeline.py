import torch
import base64
import os
import re
import json
from datetime import datetime
import google.generativeai as genai
from pymongo import MongoClient
from PIL import Image


# Device check
DEVICE = torch.device("mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu")

# Gemini API setup
GEN_API_KEY = "AIzaSyAJn4e-AlCoFsgFOJvuc8QA2r2zQDBeBqg"
genai.configure(api_key=GEN_API_KEY)
gemini_model = genai.GenerativeModel('gemini-1.5-flash')

# MongoDB setup
client = MongoClient("mongodb://localhost:27017/")
db = client["food_db"]
ingredients_col = db["ingredients_data"]
nutrition_col = db["nutrition_data"]

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
    response = gemini_model.generate_content([
        prompt,
        {"mime_type": "image/png", "data": image_data}
    ])
    return response.text

def extract_ingredients_only(description):
    lines = description.splitlines()
    return "\n".join([line.strip() for line in lines[1:] if '|' in line and len(line.split('|')) == 4])

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
    return gemini_model.generate_content(prompt).text

def estimate_nutrition_from_ingredients(dish_name, visible_ingredients):
    prompt = (
        f"You are a nutritionist.\n"
        f"The user has provided the visible ingredients from a dish named '{dish_name}'.\n"
        f"Ingredients:\n{visible_ingredients}\n\n"
        "Your task is to output the nutritional breakdown per serving (based on image analysis).\n"
        "Output each nutrient on a new line in this exact format:\n"
        "Nutrient | Value | Unit | Reasoning\n"
        "Value must be a numeric value only.\n"
        "Avoid ranges (like 100–200) or vague statements.\n"
        "Include at least these nutrients: Calories, Protein, Fat, Carbohydrates, Fiber, Sugar, Sodium.\n"
        "Be strict with the format."
    )
    return gemini_model.generate_content(prompt).text

def extract_dish_name(description):
    first_line = description.strip().split('\n')[0]
    return first_line.strip().capitalize()

def parse_to_dict(text):
    result = {}
    for line in text.splitlines():
        parts = [p.strip() for p in line.split('|')]
        if len(parts) == 4:
            try:
                num_val = float(parts[1]) if '.' in parts[1] else int(parts[1])
                result[parts[0]] = {
                    "Quantity Number/Value": num_val,
                    "Unit": parts[2],
                    "Reasoning": parts[3]
                }
            except:
                continue
    return result

def insert_to_mongo(collection, data, image_name):
    timestamp = datetime.now().isoformat()
    doc = {
        "image": image_name,
        "timestamp": timestamp,
        "data": data
    }
    collection.insert_one(doc)

def full_image_analysis(image_path):
    image_name = os.path.basename(image_path)
    description = analyze_image_with_gemini(image_path)
    dish_name = extract_dish_name(description)
    visible = extract_ingredients_only(description)
    hidden = search_hidden_ingredients(dish_name, visible)
    nutrition = estimate_nutrition_from_ingredients(dish_name, visible)

    combined_ingredients = {**parse_to_dict(visible), **parse_to_dict(hidden)}
    insert_to_mongo(ingredients_col, combined_ingredients, image_name)
    insert_to_mongo(nutrition_col, parse_to_dict(nutrition), image_name)

    return {
        'image_description': description,
        'dish_prediction': dish_name,
        'hidden_ingredients': hidden,
        'nutrition_info': nutrition
    }
