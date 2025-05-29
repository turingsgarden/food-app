import torch
from PIL import Image
from functools import lru_cache
import google.generativeai as genai
import base64
import os
import re

DEVICE = torch.device("mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu")

GEN_API_KEY = "AIzaSyAJn4e-AlCoFsgFOJvuc8QA2r2zQDBeBqg"
genai.configure(api_key=GEN_API_KEY)
gemini_model = genai.GenerativeModel('gemini-1.5-flash')

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def analyze_image_with_gemini(image_path):
    image_data = encode_image(image_path)
    prompt = (
        "Describe the food dish in this image. Give a clear name of the dish as the first line. "
        "Then list all ingredients that are visually visible, with approximate quantities. "
        "Ignore background, cutlery, or non-edible items."
    )
    try:
        response = gemini_model.generate_content([
            prompt,
            {"mime_type": "image/png", "data": image_data}
        ])
        return response.text
    except Exception as e:
        return f"Gemini error: {str(e)}"

def search_hidden_ingredients(dish_name, visible_ingredients):
    prompt = (
        f"For the dish '{dish_name}', given the following detected visible ingredients: {visible_ingredients},\n"
        f"what are the common hidden or non-visible ingredients (such as oils, spices, broth, sauces) that are likely used in most authentic recipes for this dish?\n"
        f"Return only the hidden ingredients with approximate quantities. Do not include optional or garnish items."
    )
    try:
        response = gemini_model.generate_content(prompt)
        return response.text
    except Exception as e:
        return f"Hidden ingredients lookup error: {str(e)}"

def extract_dish_name(description):
    match = re.search(r'(?i)(?:dish name[:\-]?)\s*(.*)', description)
    if match:
        return match.group(1).strip().capitalize()
    first_line = description.strip().split('\n')[0]
    return first_line.strip().capitalize()

def full_image_analysis(image_path):
    gemini_description = analyze_image_with_gemini(image_path)
    dish_name = extract_dish_name(gemini_description)
    hidden_ingredients = search_hidden_ingredients(dish_name, gemini_description)
    return {
        'image_description': gemini_description,
        'dish_prediction': dish_name,
        'hidden_ingredients': hidden_ingredients
    }
