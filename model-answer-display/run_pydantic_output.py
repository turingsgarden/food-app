# batch_pydantic_analysis.py
import os
import json
import io
import sys
import time
from tqdm import tqdm
from pathlib import Path
from datetime import datetime

# Import your Pydantic AI service
from model_pipeline_pydantic import FoodAnalysisService, FoodAnalysisResult
import google.api_core.exceptions as gcp_exceptions  

# -------------------- Configuration --------------------
dataset_dir = "food-101_100images_small"
output_dir = "output"
os.makedirs(output_dir, exist_ok=True)

output_json_path = os.path.join(output_dir, "ver4_Gemini-2.5-flash_pydantic_food_dataset_analysis.json")
user_id = "batch_user_pydantic"
supported_formats = (".jpg", ".jpeg", ".png", ".webp")
batch_size = 10  # Smaller batch size for Pydantic AI
sleep_time = 2  # Longer sleep time to avoid rate limits

# -------------------- Helper Function --------------------
def format_analysis_time(seconds):
    """Format analysis time in human-readable format: 1m30s, 40s, etc."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    else:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m{remaining_seconds:.1f}s"

# -------------------- Collect image paths --------------------
image_paths = []
for root, dirs, files in os.walk(dataset_dir):
    for file in files:
        if file.lower().endswith(supported_formats):
            image_paths.append(os.path.join(root, file))

print(f"Found {len(image_paths)} images to process.")

# -------------------- Initialize Food Analysis Service --------------------
print("Initializing Food Analysis Service...")
service = FoodAnalysisService()

# -------------------- Process images in batches --------------------
all_results = []
failed_images = []

def pydantic_result_to_dict(result: FoodAnalysisResult, image_path: str, console_output: str = "", analysis_time_seconds: float = None, analysis_time_formatted: str = None) -> dict:
    """Convert Pydantic result to serializable dictionary"""
    return {
        "image_path": image_path,
        "image_filename": os.path.basename(image_path),
        "dish_names": result.dish_names,
        "visible_ingredients": [
            {
                "name": ing.name,
                "quantity": ing.quantity_range,
                "unit": ing.unit
            } for ing in result.visible_ingredients
        ],
        "hidden_ingredients": [
            {
                "name": ing.name,
                "quantity": ing.quantity_range,
                "unit": ing.unit
            } for ing in result.hidden_ingredients
        ],
        "nutrition": {
            "calories": result.nutrition.calories,
            "protein": result.nutrition.protein,
            "fat": result.nutrition.fat,
            "carbohydrates": result.nutrition.carbohydrates,
            "fiber": result.nutrition.fiber,
            "sugar": result.nutrition.sugar,
            "sodium": result.nutrition.sodium
        },
        "analysis_timestamp": result.analysis_timestamp.isoformat(),
        "processing_timestamp": datetime.now().isoformat(),
        "analysis_time_seconds": analysis_time_seconds,  # Raw seconds for calculations
        "analysis_time": analysis_time_formatted,  # Formatted time for display
        "console_output": console_output,
        "success": True
    }

for i in range(0, len(image_paths), batch_size):
    batch_paths = image_paths[i:i+batch_size]
    batch_results = []

    for image_path in tqdm(batch_paths, desc=f"Processing batch {i//batch_size + 1}"):
        f = io.StringIO()
        analysis_time_seconds = None
        analysis_time_formatted = None
        try:
            # Redirect stdout to capture console output
            sys.stdout = f
            
            # Start timing the analysis
            analysis_start_time = time.time()
            analysis_result = service.full_analysis_pydantic(image_path, user_id)
            analysis_end_time = time.time()
            
            # Calculate analysis time
            analysis_time_seconds = analysis_end_time - analysis_start_time
            analysis_time_formatted = format_analysis_time(analysis_time_seconds)
            
            sys.stdout = sys.__stdout__
            console_text = f.getvalue()

            # Convert Pydantic result to dictionary with analysis time
            result_dict = pydantic_result_to_dict(
                analysis_result, 
                image_path, 
                console_text, 
                analysis_time_seconds,
                analysis_time_formatted
            )
            batch_results.append(result_dict)

            print(f"✅ Successfully processed: {os.path.basename(image_path)}")
            print(f"   Dishes: {', '.join(analysis_result.dish_names)}")
            print(f"   Calories: {analysis_result.nutrition.calories} kcal")
            print(f"   Analysis time: {analysis_time_formatted}")

        except gcp_exceptions.DeadlineExceeded:
            sys.stdout = sys.__stdout__
            console_text = f.getvalue()
            error_msg = f"Timeout for {image_path}"
            print(f"⏱ {error_msg}")
            
            error_result = {
                "image_path": image_path,
                "image_filename": os.path.basename(image_path),
                "error": "DeadlineExceeded",
                "console_output": console_text,
                "success": False,
                "processing_timestamp": datetime.now().isoformat(),
                "analysis_time_seconds": None,
                "analysis_time": None
            }
            batch_results.append(error_result)
            failed_images.append((image_path, "DeadlineExceeded"))

        except Exception as e:
            sys.stdout = sys.__stdout__
            console_text = f.getvalue()
            error_msg = f"Error processing {image_path}: {str(e)}"
            print(f"❌ {error_msg}")
            
            error_result = {
                "image_path": image_path,
                "image_filename": os.path.basename(image_path),
                "error": str(e),
                "console_output": console_text,
                "success": False,
                "processing_timestamp": datetime.now().isoformat(),
                "analysis_time_seconds": analysis_time_seconds if analysis_time_seconds else None,
                "analysis_time": analysis_time_formatted if analysis_time_formatted else None
            }
            batch_results.append(error_result)
            failed_images.append((image_path, str(e)))

        # Delay to reduce rate limit errors
        time.sleep(sleep_time)

    # Add batch results to all results
    all_results.extend(batch_results)

    # Save intermediate JSON after each batch
    with open(output_json_path, "w", encoding="utf-8") as f:
        json.dump(all_results, f, ensure_ascii=False, indent=4)

    print(f"✅ Batch {i//batch_size + 1} saved, total {len(all_results)} images processed.")
    

# -------------------- Save summary report --------------------
summary = {
    "processing_summary": {
        "total_images": len(image_paths),
        "successful_processing": len([r for r in all_results if r.get("success", False)]),
        "failed_processing": len(failed_images),
        "processing_date": datetime.now().isoformat(),
        "user_id": user_id
    },
    "performance_metrics": {
        "average_analysis_time_seconds": None,
        "average_analysis_time_formatted": None,
        "min_analysis_time_seconds": None,
        "min_analysis_time_formatted": None,
        "max_analysis_time_seconds": None,
        "max_analysis_time_formatted": None,
        "total_processing_time_seconds": None,
        "total_processing_time_formatted": None
    },
    "failed_images": [
        {
            "image_path": img_path,
            "error": error
        } for img_path, error in failed_images
    ],
    "statistics": {
        "average_calories": None,
        "most_common_dishes": None
    }
}

# Calculate performance metrics for successful results
successful_results = [r for r in all_results if r.get("success", False)]
if successful_results:
    # Analysis time statistics
    analysis_times_seconds = [r.get("analysis_time_seconds", 0) for r in successful_results if r.get("analysis_time_seconds") is not None]
    if analysis_times_seconds:
        avg_seconds = sum(analysis_times_seconds) / len(analysis_times_seconds)
        min_seconds = min(analysis_times_seconds)
        max_seconds = max(analysis_times_seconds)
        total_seconds = sum(analysis_times_seconds)
        
        summary["performance_metrics"]["average_analysis_time_seconds"] = avg_seconds
        summary["performance_metrics"]["average_analysis_time_formatted"] = format_analysis_time(avg_seconds)
        summary["performance_metrics"]["min_analysis_time_seconds"] = min_seconds
        summary["performance_metrics"]["min_analysis_time_formatted"] = format_analysis_time(min_seconds)
        summary["performance_metrics"]["max_analysis_time_seconds"] = max_seconds
        summary["performance_metrics"]["max_analysis_time_formatted"] = format_analysis_time(max_seconds)
        summary["performance_metrics"]["total_processing_time_seconds"] = total_seconds
        summary["performance_metrics"]["total_processing_time_formatted"] = format_analysis_time(total_seconds)
    
    # Nutrition statistics
    # calories = [r["nutrition"]["calories"] for r in successful_results if "nutrition" in r]
    # if calories:
    #     summary["statistics"]["average_calories"] = sum(calories) / len(calories)
    calorie_ranges = [
    r["nutrition"]["calories"]
    for r in successful_results
    if "nutrition" in r
]

    if calorie_ranges:
        midpoints = [(c[0] + c[1]) / 2 for c in calorie_ranges]
        summary["statistics"]["average_calories"] = sum(midpoints) / len(midpoints)
    # Most common dishes
    all_dishes = []
    for result in successful_results:
        if "dish_names" in result and result["dish_names"]:
            all_dishes.extend(result["dish_names"])
    
    from collections import Counter
    dish_counter = Counter(all_dishes)
    summary["statistics"]["most_common_dishes"] = dish_counter.most_common(10)

# Save summary
summary_path = os.path.join(output_dir, "processing_summary.json")
with open(summary_path, "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=4)

print(f"🎉 All batches complete!")
print(f"📊 Results saved to: {output_json_path}")
print(f"📈 Summary saved to: {summary_path}")
print(f"✅ Successful: {summary['processing_summary']['successful_processing']}")
print(f"❌ Failed: {summary['processing_summary']['failed_processing']}")
print(f"📋 Total: {summary['processing_summary']['total_images']}")

# Print performance metrics
if summary["performance_metrics"]["average_analysis_time_seconds"]:
    print(f"⏱ Performance Metrics:")
    print(f"   Average analysis time: {summary['performance_metrics']['average_analysis_time_formatted']}")
    print(f"   Min analysis time: {summary['performance_metrics']['min_analysis_time_formatted']}")
    print(f"   Max analysis time: {summary['performance_metrics']['max_analysis_time_formatted']}")
    print(f"   Total processing time: {summary['performance_metrics']['total_processing_time_formatted']}")

# Print failed images for review
if failed_images:
    print("\n⚠️ Failed images:")
    for img_path, error in failed_images:
        print(f"   {os.path.basename(img_path)}: {error}")


# # interactive_test.py
# import sys
# import os

# # Add current directory to Python path so we can import from other files
# sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# # Import FoodAnalysisService from your main file
# from model_pipeline_pydantic import FoodAnalysisService  # Replace with your actual filename
# # Interactive test script
# def interactive_test():
#     """Interactive testing - test your food analysis system like a conversation"""
    
#     service = FoodAnalysisService()
    
#     print("Food Analysis System - Interactive Test Mode")
#     print("=" * 50)
#     print("Welcome! You can test different food images at any time")
#     print("Enter 'quit' to exit the program")
#     print("=" * 50)
    
#     while True:
#         print("\n" + "-" * 30)
        
#         # 1. Get image path
#         image_path = input("Enter image path: ").strip()
        
#         if image_path.lower() in ['quit', 'exit', 'q']:
#             print("Thank you for using, goodbye!")
#             break
            
#         # 2. Check if image exists
#         if not os.path.exists(image_path):
#             print(f"Image does not exist: {image_path}")
#             print("Please check if the path is correct, or enter an absolute path")
#             continue
            
#         # 3. Get user ID (optional)
#         user_id = input("User ID (press Enter for default): ").strip()
#         if not user_id:
#             user_id = "interactive_user"
            
#         # 4. Start analysis
#         print(f"\nAnalyzing image: {os.path.basename(image_path)}")
#         print("This may take a few seconds...")
        
#         try:
#             # Call your analysis function
#             result = service.full_analysis_pydantic(image_path, user_id)
            
#             # 5. Display results
#             print("\n" + "="*40)
#             print("           Analysis Results")
#             print("="*40)
            
#             print(f"Main dish: {result.dish_names[0] if result.dish_names else 'Unknown'}")
            
#             print(f"\nVisible ingredients ({len(result.visible_ingredients)} items):")
#             for i, ing in enumerate(result.visible_ingredients[:5], 1):
#                 print(f"   {i}. {ing.name} - {ing.quantity}{ing.unit}")
#             if len(result.visible_ingredients) > 5:
#                 print(f"   ... and {len(result.visible_ingredients) - 5} more ingredients")
                
#             print(f"\nHidden ingredients ({len(result.hidden_ingredients)} items):")
#             for i, ing in enumerate(result.hidden_ingredients, 1):
#                 print(f"   {i}. {ing.name} - {ing.quantity}{ing.unit}")
            
#             print(f"\nNutrition Information:")
#             print(f"   Calories: {result.nutrition.calories} kcal")
#             print(f"   Protein: {result.nutrition.protein} g") 
#             print(f"   Fat: {result.nutrition.fat} g")
#             print(f"   Carbohydrates: {result.nutrition.carbohydrates} g")
#             print(f"   Fiber: {result.nutrition.fiber} g")
#             print(f"   Sugar: {result.nutrition.sugar} g")
#             print(f"   Sodium: {result.nutrition.sodium} mg")
            
#             # 6. Ask if save to database
#             save_choice = input(f"\nSave to database? (y/n): ").strip().lower()
#             if save_choice in ['y', 'yes']:
#                 try:
#                     doc_id = service.save_to_database(result, user_id)
#                     print(f"Save successful! Document ID: {doc_id}")
#                 except Exception as e:
#                     print(f"Save failed: {e}")
                    
#             # 7. Ask if continue testing
#             continue_choice = input(f"\nContinue testing other images? (y/n): ").strip().lower()
#             if continue_choice not in ['y', 'yes']:
#                 print("Thank you for using!")
#                 break
                
#         except Exception as e:
#             print(f"Error during analysis: {str(e)}")
#             print("Please check image format or network connection")

# if __name__ == "__main__":
#     interactive_test()
