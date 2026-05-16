"""
run_pipeline_gpt.py
-------------------
Run from inside model-answer-display/:
    cd model-answer-display
    OPENAI_API_KEY=sk-... python3 run_pipeline_gpt.py

Output: output/GPT-5.4_food-101_analysis.json
"""

import os
import time
import traceback
from datetime import datetime
from openai import OpenAI
from pipeline_base import (
    load_and_optimize_image, VISION_PROMPT,
    HIDDEN_INGREDIENTS_PROMPT_TEMPLATE, NUTRITION_PROMPT_TEMPLATE,
    parse_vision_response, parse_hidden_ingredients, parse_nutrition,
    ingredients_to_text, NUTRITION_DEFAULTS,
    collect_images, save_output, load_existing_output,
)

MODEL_NAME  = "gpt-5.4"
OUTPUT_PATH = "output/GPT-5.4_food-101_analysis.json"
DELAY_SECS  = 1.0

api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    raise ValueError("OPENAI_API_KEY is not set. Export it before running.")
client = OpenAI(api_key=api_key)


def call_vision(b64: str, mime: str, prompt: str) -> str:
    response = client.chat.completions.create(
        model=MODEL_NAME, max_completion_tokens=2048,
        messages=[{"role": "user", "content": [
            {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}},
            {"type": "text", "text": prompt}
        ]}]
    )
    return response.choices[0].message.content


def call_text(prompt: str) -> str:
    response = client.chat.completions.create(
        model=MODEL_NAME, max_completion_tokens=1024,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.choices[0].message.content


def analyze_image(image_path: str, image_filename: str) -> dict:
    start = time.time()
    print(f"  🔍 {image_filename}")
    try:
        b64, mime, size = load_and_optimize_image(image_path)

        raw_vision = call_vision(b64, mime, VISION_PROMPT)
        dish_names, visible_ingredients = parse_vision_response(raw_vision)
        if not dish_names:
            dish_names = [os.path.splitext(image_filename)[0]]

        raw_hidden = call_text(HIDDEN_INGREDIENTS_PROMPT_TEMPLATE.format(
            dish_names=", ".join(dish_names),
            visible_ingredients=ingredients_to_text(visible_ingredients)
        ))
        hidden_ingredients = parse_hidden_ingredients(raw_hidden)

        all_ingredients_text = (
            ingredients_to_text(visible_ingredients) + "\n" +
            ingredients_to_text(hidden_ingredients)
        )
        raw_nutrition = call_text(NUTRITION_PROMPT_TEMPLATE.format(
            dish_names=", ".join(dish_names),
            all_ingredients=all_ingredients_text
        ))
        nutrition = parse_nutrition(raw_nutrition)

        elapsed = time.time() - start
        print(f"     ✅ {', '.join(dish_names)} ({elapsed:.1f}s)")

        return {
            "image_path": f"food-101_100images/{image_filename}",
            "image_filename": image_filename,
            "dish_names": dish_names,
            "visible_ingredients": visible_ingredients,
            "hidden_ingredients": hidden_ingredients,
            "nutrition": nutrition,
            "processing_timestamp": datetime.now().isoformat(),
            "analysis_time_seconds": round(elapsed, 3),
            "analysis_time": f"{elapsed:.1f}s",
            "model_name": MODEL_NAME,
            "success": True,
            "error": None,
        }

    except Exception as e:
        elapsed = time.time() - start
        print(f"     ❌ Error: {e}")
        traceback.print_exc()
        return {
            "image_path": f"food-101_100images/{image_filename}",
            "image_filename": image_filename,
            "dish_names": [],
            "visible_ingredients": [],
            "hidden_ingredients": [],
            "nutrition": dict(NUTRITION_DEFAULTS),
            "processing_timestamp": datetime.now().isoformat(),
            "analysis_time_seconds": round(elapsed, 3),
            "analysis_time": f"{elapsed:.1f}s",
            "model_name": MODEL_NAME,
            "success": False,
            "error": str(e),
        }


def main():
    print(f"🚀 GPT pipeline — {MODEL_NAME}")
    print(f"📁 Output: {OUTPUT_PATH}\n")

    images   = collect_images()
    existing = load_existing_output(OUTPUT_PATH)
    print(f"📸 {len(images)} images found | {len(existing)} already done\n")

    results = list(existing.values())

    for i, entry in enumerate(images, 1):
        fname = entry["image_filename"]
        if fname in existing:
            print(f"  ⏭  [{i}/{len(images)}] {fname} — skipping")
            continue
        print(f"[{i}/{len(images)}]")
        result = analyze_image(entry["image_path"], fname)
        results.append(result)
        save_output(results, OUTPUT_PATH)
        if i < len(images):
            time.sleep(DELAY_SECS)

    print(f"\n🎉 Done! {len(results)} records saved to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
