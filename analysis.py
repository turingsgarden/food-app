from PIL import Image
import os
import google.generativeai as genai

# Configure Gemini key
genai.configure(api_key="AIzaSyB3DmBpSnfXHvd0N6LBDIGCgyIwMLUE1yI")

models = genai.list_models()

# print("Available models:")
# for m in models:
#     print(m.name)


def encode_image(image_path):
    """Helper to encode image for Gemini"""
    with open(image_path, "rb") as f:
        return f.read()


def analyze_image_gemini_1(image_path: str) -> dict:
    """Analyze image with gemini-2.5-pro using enhanced prompt"""
    # model = genai.GenerativeModel("gemini-1.5-flash")
    model = genai.GenerativeModel("models/gemini-2.5-pro")
    print(f"Model used is {model}")

    # Optimize image
    img = Image.open(image_path)
    max_size = (1024, 1024)
    img.thumbnail(max_size, Image.Resampling.LANCZOS)
    if img.mode not in ('RGB', 'L'):
        img = img.convert('RGB')
    import tempfile
    # Save optimized image to a temporary file
    suffix = os.path.splitext(image_path)[1]  # preserves .png/.jpg/.jpeg
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
        img.save(tmp_file.name, 'JPEG', quality=85)
        tmp_path = tmp_file.name

    # Encode optimized image
    image_data = encode_image(tmp_path)

    # Clean up temp file
    try:
        os.remove(tmp_path)
    except:
        pass


    # Enhanced prompt from your working app
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

    # Generate content
    response = model.generate_content([
        prompt,
        {"mime_type": "image/jpeg", "data": image_data}
    ])

    return {
        "model": "gemini-2.5-pro",
        "calories_estimate": response.text if response and response.text else "Error or empty response"
    }


def analyze_image_gemini_2(image_path: str) -> dict:
    """Analyze image with gemini-2.5-flash using same enhanced prompt"""
    # model = genai.GenerativeModel("gemini-1.5-pro")
    model = genai.GenerativeModel("models/gemini-2.5-flash")
    print(f"Model used is {model}")
    # Optimize image
    img = Image.open(image_path)
    max_size = (1024, 1024)
    img.thumbnail(max_size, Image.Resampling.LANCZOS)
    if img.mode not in ('RGB', 'L'):
        img = img.convert('RGB')
    import tempfile

    # Save optimized image to a temporary file
    suffix = os.path.splitext(image_path)[1]  # preserves .png/.jpg/.jpeg
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
        img.save(tmp_file.name, 'JPEG', quality=85)
        tmp_path = tmp_file.name

    # Encode optimized image
    image_data = encode_image(tmp_path)

    # Clean up temp file
    try:
        os.remove(tmp_path)
    except:
        pass


    # Same enhanced prompt
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

    response = model.generate_content([
        prompt,
        {"mime_type": "image/jpeg", "data": image_data}
    ])

    return {
        "model": "gemini-2.5-flash",
        "calories_estimate": response.text if response and response.text else "Error or empty response"
    }

def analyze_image_gemini_3(image_path: str) -> dict:
    """Analyze image with gemini-2.5-pro-preview-03-25"""
    model = genai.GenerativeModel("models/gemini-2.5-pro-preview-03-25")
    print(f"Model used is {model}")

    # Optimize image
    img = Image.open(image_path)
    max_size = (1024, 1024)
    img.thumbnail(max_size, Image.Resampling.LANCZOS)
    if img.mode not in ('RGB', 'L'):
        img = img.convert('RGB')
    import tempfile
    suffix = os.path.splitext(image_path)[1]
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
        img.save(tmp_file.name, 'JPEG', quality=85)
        tmp_path = tmp_file.name

    image_data = encode_image(tmp_path)

    try:
        os.remove(tmp_path)
    except:
        pass

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

    response = model.generate_content([
        prompt,
        {"mime_type": "image/jpeg", "data": image_data}
    ])

    return {
        "model": "gemini-2.5-pro-preview-03-25",
        "calories_estimate": response.text if response and response.text else "Error or empty response"
    }


def analyze_image_gemini_4(image_path: str) -> dict:
    """Analyze image with gemini-2.5-flash-preview-05-20"""
    model = genai.GenerativeModel("models/gemini-2.5-flash-preview-05-20")
    print(f"Model used is {model}")

    # Optimize image
    img = Image.open(image_path)
    max_size = (1024, 1024)
    img.thumbnail(max_size, Image.Resampling.LANCZOS)
    if img.mode not in ('RGB', 'L'):
        img = img.convert('RGB')
    import tempfile
    suffix = os.path.splitext(image_path)[1]
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
        img.save(tmp_file.name, 'JPEG', quality=85)
        tmp_path = tmp_file.name

    image_data = encode_image(tmp_path)

    try:
        os.remove(tmp_path)
    except:
        pass

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

    response = model.generate_content([
        prompt,
        {"mime_type": "image/jpeg", "data": image_data}
    ])

    return {
        "model": "gemini-2.5-flash-preview-05-20",
        "calories_estimate": response.text if response and response.text else "Error or empty response"
    }
