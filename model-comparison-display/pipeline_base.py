"""
pipeline_base.py
----------------
Shared prompts and parsing utilities used by all model pipelines.
"""

import base64
import json
import os
from PIL import Image
from io import BytesIO

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

IMAGE_DIR = "food-101_100images"
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}

# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------

def load_and_optimize_image(image_path: str):
    """Resize + convert image, return (base64_string, mime_type, size_string)."""
    image = Image.open(image_path)
    max_size = (1024, 1024)
    image.thumbnail(max_size, Image.Resampling.LANCZOS)
    if image.mode not in ("RGB", "L"):
        image = image.convert("RGB")
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=85)
    buffer.seek(0)
    b64 = base64.b64encode(buffer.read()).decode("utf-8")
    return b64, "image/jpeg", f"{image.size[0]}x{image.size[1]}"


# ---------------------------------------------------------------------------
# Prompts — identical to original Gemini pipeline
# ---------------------------------------------------------------------------

VISION_PROMPT = (
    "You are a comprehensive food analyst. Look at this image and identify ALL food items present.\n\n"
    "INSTRUCTIONS:\n"
    "1. First line: List all dishes/food items you see WITHOUT NUMBERS "
    "(e.g., 'Chicken curry, basmati rice, naan bread, mixed salad')\n"
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

HIDDEN_INGREDIENTS_PROMPT_TEMPLATE = (
    "You are a recipe analyst. For these dishes: {dish_names}\n"
    "With visible ingredients:\n{visible_ingredients}\n\n"
    "List ONLY the hidden ingredients in this exact format:\n"
    "Oil | 2 | tbsp | For cooking\n"
    "Salt | 1 | tsp | Seasoning\n"
    "NO HEADERS, NO DASHES, just ingredients."
)

NUTRITION_PROMPT_TEMPLATE = (
    "Calculate total nutrition for: {dish_names}\n"
    "Ingredients: {all_ingredients}\n\n"
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


# ---------------------------------------------------------------------------
# Parsing helpers — output matches Gemini pydantic format exactly
# ---------------------------------------------------------------------------

def parse_vision_response(raw: str):
    lines = [l.strip() for l in raw.strip().splitlines() if l.strip()]
    if not lines:
        return [], []

    # Words that indicate a header line, not a dish name
    skip_phrases = [
        "food items", "items present", "dishes", "dish:", "food:",
        "ingredients", "present:", "following", "image contains",
        "i can see", "visible"
    ]

    dish_line = ""
    ingredient_start = 0
    for i, line in enumerate(lines):
        clean = line.lstrip("#•*- ").rstrip(":").strip()
        if not clean:
            continue
        if "|" in clean:
            continue
        # Skip if it looks like a header
        if any(phrase in clean.lower() for phrase in skip_phrases):
            continue
        # This is our dish name line
        dish_line = clean
        ingredient_start = i + 1
        break

    dish_names = [d.strip() for d in dish_line.split(",") if d.strip()]

    visible_ingredients = []
    for line in lines[ingredient_start:]:
        if "|" in line:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 3:
                try:
                    visible_ingredients.append({
                        "name": parts[0].lstrip("-•*# "),
                        "quantity": float(parts[1]),
                        "unit": parts[2]
                    })
                except ValueError:
                    continue

    return dish_names, visible_ingredients

def parse_hidden_ingredients(raw: str) -> list:
    """Returns list of {name, quantity, unit} dicts."""
    result = []
    for line in raw.strip().splitlines():
        line = line.strip()
        if "|" in line and not any(x in line.lower() for x in ["---", "ingredient", "quantity"]):
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 3:
                try:
                    result.append({
                        "name": parts[0],
                        "quantity": float(parts[1]),
                        "unit": parts[2]
                    })
                except ValueError:
                    continue
    if not result:
        result = [
            {"name": "Cooking oil", "quantity": 2.0, "unit": "tbsp"},
            {"name": "Salt",        "quantity": 1.0, "unit": "tsp"}
        ]
    return result


NUTRITION_DEFAULTS = {
    "calories": 500.0, "protein": 20.0, "fat": 15.0,
    "carbohydrates": 60.0, "fiber": 5.0, "sugar": 10.0, "sodium": 800.0
}


def parse_nutrition(raw: str) -> dict:
    """Returns {calories, protein, fat, carbohydrates, fiber, sugar, sodium} dict."""
    result = dict(NUTRITION_DEFAULTS)
    key_map = {
        "calories": "calories", "protein": "protein", "fat": "fat",
        "carbohydrates": "carbohydrates", "fiber": "fiber",
        "sugar": "sugar", "sodium": "sodium",
    }
    for line in raw.strip().splitlines():
        if "|" in line:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 2:
                key = parts[0].lower()
                if key in key_map:
                    val_str = "".join(c for c in parts[1] if c.isdigit() or c == ".")
                    if val_str:
                        result[key_map[key]] = float(val_str)
    return result


def ingredients_to_text(ingredients: list) -> str:
    """Convert ingredient dicts to pipe format for prompts."""
    return "\n".join(
        f"{i['name']} | {i['quantity']} | {i['unit']}" for i in ingredients
    )


# ---------------------------------------------------------------------------
# Dataset + output helpers
# ---------------------------------------------------------------------------

def collect_images(image_dir: str = IMAGE_DIR) -> list:
    """Return sorted list of {image_path, image_filename} dicts."""
    if not os.path.exists(image_dir):
        raise FileNotFoundError(
            f"Image directory not found: {image_dir}\n"
            f"Make sure you are running this script from inside model-answer-display/"
        )
    entries = []
    for fname in sorted(os.listdir(image_dir)):
        if os.path.splitext(fname)[1].lower() in IMAGE_EXTENSIONS:
            entries.append({
                "image_path": os.path.join(image_dir, fname),
                "image_filename": fname,
            })
    return entries


def save_output(results: list, output_path: str):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"✅ Saved {len(results)} records → {output_path}")


def load_existing_output(output_path: str) -> dict:
    """Returns {image_filename: record} dict for already-processed images."""
    if not os.path.exists(output_path):
        return {}
    with open(output_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {item["image_filename"]: item for item in data}
