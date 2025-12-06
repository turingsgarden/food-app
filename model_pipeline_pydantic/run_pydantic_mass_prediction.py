
import os
import json
import io
import sys
import time
from tqdm import tqdm
from pathlib import Path
from datetime import datetime
from PIL import Image
import numpy as np

# Import your Mass Estimation service
from model_pipeline_pydantic_mass import FoodMassEstimationService, MassEstimationOutput, calculate_volume_from_depth_and_mask
import google.api_core.exceptions as gcp_exceptions  

# -------------------- Configuration --------------------
dataset_dir = "model-answer-display/Nutrition5k/Nutrition5k-merged"
segmentation_dir = "/scratch/ht2604/food-app/segmentation/results"
metadata_path = "model-answer-display/Nutrition5k/metadata/metadata/dish_metadata_cafe1.json"
output_dir = "model_output_analysis/mass_prediction_data_and_result/mass_prediction.json"
os.makedirs(output_dir, exist_ok=True)

# 使用正确的原始深度图目录
raw_depth_dir = "/scratch/ht2604/food-app/Nutrition5k/Nutrition5k-merged/raw_depth"

output_json_path = os.path.join(output_dir, "Nutrition5k_mass_estimation_results_volume_based.json")
user_id = "batch_user_mass_estimation"
supported_formats = (".jpg", ".jpeg", ".png", ".webp")
batch_size = 5
sleep_time = 3

TEST_LIMIT = None 

# -------------------- Load Ground Truth Metadata --------------------
def load_ground_truth_metadata(metadata_path):

    print(f"📖 Loading ground truth metadata from: {metadata_path}")
    with open(metadata_path, "r", encoding="utf-8") as f:
        metadata = json.load(f)
    

    gt_mapping = {}
    for item in metadata:
        dish_id = extract_dish_id(item.get("image_filename", ""))
        if dish_id:

            nutrition = item.get("nutrition", {})
            true_mass = nutrition.get("mass")
            if true_mass is not None:
                gt_mapping[dish_id] = true_mass
            else:
                # 如果没有mass字段，计算ingredients的总和
                ingredients = item.get("ingredients", [])
                total_mass = sum(ing.get("quantity", 0) for ing in ingredients)
                if total_mass > 0:
                    gt_mapping[dish_id] = total_mass
    
    print(f"✅ Loaded ground truth masses for {len(gt_mapping)} dishes")
    

    if gt_mapping:
        masses = list(gt_mapping.values())
        print(f"📊 Ground truth mass statistics:")
        print(f"   Min: {min(masses):.1f}g")
        print(f"   Max: {max(masses):.1f}g")
        print(f"   Mean: {np.mean(masses):.1f}g")
        print(f"   Median: {np.median(masses):.1f}g")
    
    return gt_mapping

# -------------------- Helper Functions --------------------
def format_analysis_time(seconds):
    """Format analysis time in human-readable format: 1m30s, 40s, etc."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    else:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m{remaining_seconds:.1f}s"

def extract_dish_id(filename):
    """Extract dish ID from filename patterns"""
    parts = filename.split('_')
    for part in parts:
        if part.isdigit() and len(part) >= 9:
            return part
    return None

def find_depth_file_for_dish(dish_id, raw_depth_dir):

    exact_patterns = [
        f"dish_{dish_id}_depth_raw.png",
        f"{dish_id}_depth_raw.png",
        f"dish_{dish_id}_raw_depth.png", 
        f"{dish_id}_raw_depth.png"
    ]
    
    for pattern in exact_patterns:
        potential_path = os.path.join(raw_depth_dir, pattern)
        if os.path.exists(potential_path):
            return potential_path
    

    for filename in os.listdir(raw_depth_dir):
        if dish_id in filename and any(keyword in filename.lower() for keyword in ['depth_raw', 'raw_depth', 'depth']):
            if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
                return os.path.join(raw_depth_dir, filename)
    
    return None

# -------------------- Load Ground Truth Data --------------------
ground_truth_mapping = load_ground_truth_metadata(metadata_path)

# -------------------- Collect file triplets --------------------
print("Scanning dataset directory structure...")

rgb_dir = os.path.join(dataset_dir, "rgb")

rgb_files = {}
for file in os.listdir(rgb_dir):
    if file.lower().endswith(supported_formats):
        dish_id = extract_dish_id(file)
        if dish_id:
            rgb_files[dish_id] = os.path.join(rgb_dir, file)

print(f"Found {len(rgb_files)} RGB images")

# Find matching segmentation and depth files
file_triplets = []

for dish_id, rgb_path in rgb_files.items():

    if dish_id not in ground_truth_mapping:
        print(f"⚠️ No ground truth mass data for dish {dish_id}")
        continue
    
    # Find segmentation file
    seg_patterns = [
        f"mask_dish_{dish_id}_rgb.png",
        f"mask_{dish_id}.png",
        f"mask_dish_{dish_id}.png"
    ]
    
    seg_path = None
    for pattern in seg_patterns:
        potential_path = os.path.join(segmentation_dir, pattern)
        if os.path.exists(potential_path):
            seg_path = potential_path
            break
    
    if not seg_path:
        # Try to find by scanning all segmentation files
        for seg_file in os.listdir(segmentation_dir):
            if dish_id in seg_file and seg_file.lower().endswith(supported_formats):
                seg_path = os.path.join(segmentation_dir, seg_file)
                break
    
    if not seg_path:
        print(f"⚠️ No segmentation mask found for dish {dish_id}")
        continue
    
    # Find depth file - 
    depth_path = find_depth_file_for_dish(dish_id, raw_depth_dir)
    
    if not depth_path:
        print(f"⚠️ No raw depth image found for dish {dish_id} in {raw_depth_dir}")
        continue
    
    file_triplets.append({
        'dish_id': dish_id,
        'rgb': rgb_path,
        'segmentation': seg_path,
        'depth': depth_path,
        'true_mass_g': ground_truth_mapping[dish_id]
    })

if TEST_LIMIT:
    file_triplets = file_triplets[:TEST_LIMIT]
    print(f"🔬 TEST MODE: Only testing first {TEST_LIMIT} images")
else:
    print(f"🔍 PROCESSING ALL IMAGES: Found {len(file_triplets)} complete triplets")

print(f"Found {len(file_triplets)} complete triplets with ground truth data")

# -------------------- Initialize Mass Estimation Service --------------------
print("Initializing Food Mass Estimation Service...")
service = FoodMassEstimationService()

# -------------------- Process images in batches --------------------
all_results = []
failed_images = []

def mass_result_to_dict(result: MassEstimationOutput, file_triplet: dict, console_output: str = "", 
                       analysis_time_seconds: float = None, analysis_time_formatted: str = None,
                       calculated_volume: float = None) -> dict:
    """Convert MassEstimationOutput to serializable dictionary"""
    
    result_dict = {
        "dish_id": file_triplet['dish_id'],
        "file_paths": {
            "rgb": file_triplet['rgb'],
            "segmentation": file_triplet['segmentation'],
            "depth": file_triplet['depth']
        },
        "ground_truth_mass_g": file_triplet['true_mass_g'],
        "mass_estimation": {
            "total_mass_g": result.total_mass_g,
            "calculated_volume_cm3": calculated_volume,
            "food_items": [
                {
                    "name": item.name,
                    "predicted_mass_g": item.predicted_mass_g,
                    "confidence": item.confidence
                } for item in result.food_items
            ]
        },
        "analysis_timestamp": datetime.now().isoformat(),
        "processing_timestamp": datetime.now().isoformat(),
        "analysis_time_seconds": analysis_time_seconds,
        "analysis_time": analysis_time_formatted,
        "console_output": console_output,
        "success": True
    }
    
    return result_dict

def error_result_to_dict(file_triplet: dict, error_msg: str, console_output: str = "",
                        analysis_time_seconds: float = None, analysis_time_formatted: str = None) -> dict:
    """Create error result dictionary"""
    result_dict = {
        "dish_id": file_triplet['dish_id'],
        "file_paths": {
            "rgb": file_triplet['rgb'],
            "segmentation": file_triplet['segmentation'],
            "depth": file_triplet['depth']
        },
        "ground_truth_mass_g": file_triplet['true_mass_g'],
        "error": error_msg,
        "console_output": console_output,
        "success": False,
        "processing_timestamp": datetime.now().isoformat(),
        "analysis_time_seconds": analysis_time_seconds,
        "analysis_time": analysis_time_formatted
    }
    
    return result_dict

print(f"Starting mass estimation for {len(file_triplets)} dishes...")
print(f"🎯 Using VOLUME-BASED estimation with RAW DEPTH maps")
print(f"📦 Processing ALL available images")
print(f"📁 Raw depth directory: {raw_depth_dir}")

total_batches = (len(file_triplets) + batch_size - 1) // batch_size
print(f"📊 Total batches to process: {total_batches}")

for i in range(0, len(file_triplets), batch_size):
    batch_triplets = file_triplets[i:i+batch_size]
    batch_results = []

    for triplet in tqdm(batch_triplets, desc=f"Batch {i//batch_size + 1}/{total_batches}"):
        
        f = io.StringIO()
        analysis_time_seconds = None
        analysis_time_formatted = None
        calculated_volume = None
        
        try:
            sys.stdout = f
            
            # Load images
            rgb_img = Image.open(triplet['rgb'])
            segmentation_img = Image.open(triplet['segmentation'])
            depth_img = Image.open(triplet['depth'])
            

            if segmentation_img.mode != 'L':
                segmentation_img = segmentation_img.convert('L')
            

            print(f"🔍 Calculating volume for dish {triplet['dish_id']}...")
            calculated_volume = calculate_volume_from_depth_and_mask(depth_img, segmentation_img)
            print(f"📊 Calculated volume: {calculated_volume:.2f} cm³")
            
            analysis_start_time = time.time()
            

            mass_result = service.run_estimation(
                rgb_img=rgb_img,
                segmentation_img=segmentation_img,
                depth_img=depth_img,
                user_id=user_id
            )
            
            analysis_end_time = time.time()
            analysis_time_seconds = analysis_end_time - analysis_start_time
            analysis_time_formatted = format_analysis_time(analysis_time_seconds)
            
            sys.stdout = sys.__stdout__
            console_text = f.getvalue()

            result_dict = mass_result_to_dict(
                mass_result, 
                triplet, 
                console_text, 
                analysis_time_seconds,
                analysis_time_formatted,
                calculated_volume
            )
            batch_results.append(result_dict)

            true_mass = triplet['true_mass_g']
            pred_mass = mass_result.total_mass_g
            error = abs(pred_mass - true_mass)
            percentage_error = (error / true_mass) * 100 if true_mass > 0 else 0
            

            if len(file_triplets) <= 50:
                print(f"✅ dish_{triplet['dish_id']}: {pred_mass:.1f}g (True: {true_mass:.1f}g, Error: {error:.1f}g, {percentage_error:.1f}%), Volume: {calculated_volume:.1f}cm³, Time: {analysis_time_formatted}")
            else:
                if (i + batch_triplets.index(triplet)) % 10 == 0:
                    print(f"✅ Progress: {i + batch_triplets.index(triplet) + 1}/{len(file_triplets)} - dish_{triplet['dish_id']}: {pred_mass:.1f}g (Error: {error:.1f}g, Volume: {calculated_volume:.1f}cm³)")

        except gcp_exceptions.DeadlineExceeded:
            sys.stdout = sys.__stdout__
            console_text = f.getvalue()
            print(f"⏱ dish_{triplet['dish_id']}: Timeout")
            
            error_result = error_result_to_dict(
                triplet, "DeadlineExceeded", console_text,
                analysis_time_seconds, analysis_time_formatted
            )
            batch_results.append(error_result)
            failed_images.append((triplet['dish_id'], "DeadlineExceeded"))

        except Exception as e:
            sys.stdout = sys.__stdout__
            console_text = f.getvalue()
            print(f"❌ dish_{triplet['dish_id']}: {str(e)}")
            
            error_result = error_result_to_dict(
                triplet, str(e), console_text,
                analysis_time_seconds, analysis_time_formatted
            )
            batch_results.append(error_result)
            failed_images.append((triplet['dish_id'], str(e)))

        time.sleep(sleep_time)

    all_results.extend(batch_results)


    with open(output_json_path, "w", encoding="utf-8") as f:
        json.dump(all_results, f, ensure_ascii=False, indent=4)

    completed = min(i + batch_size, len(file_triplets))
    progress_percentage = (completed / len(file_triplets)) * 100
    print(f"✅ Batch {i//batch_size + 1}/{total_batches} saved - Progress: {completed}/{len(file_triplets)} ({progress_percentage:.1f}%)")

# -------------------- Enhanced Summary Report --------------------
summary = {
    "processing_summary": {
        "total_triplets": len(file_triplets),
        "successful_processing": len([r for r in all_results if r.get("success", False)]),
        "failed_processing": len(failed_images),
        "processing_date": datetime.now().isoformat(),
        "user_id": user_id,
        "service_type": "Food Mass Estimation with Volume Calculation",
        "dataset": "Nutrition5k-merged",
        "raw_depth_directory": raw_depth_dir,
        "test_limit": "ALL_IMAGES" if not TEST_LIMIT else f"FIRST_{TEST_LIMIT}_IMAGES"
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
    "accuracy_metrics": {
        "mean_absolute_error_g": None,
        "mean_absolute_percentage_error": None,
        "min_error_g": None,
        "max_error_g": None,
        "accuracy_distribution": None
    },
    "volume_metrics": {
        "average_volume_cm3": None,
        "min_volume_cm3": None,
        "max_volume_cm3": None,
        "volume_mass_correlation": None
    },
    "mass_statistics": {
        "true_mass_stats": {
            "average_true_mass_g": None,
            "min_true_mass_g": None,
            "max_true_mass_g": None
        },
        "predicted_mass_stats": {
            "average_predicted_mass_g": None,
            "min_predicted_mass_g": None,
            "max_predicted_mass_g": None
        },
        "most_common_foods": None
    },
    "failed_images": [
        {
            "dish_id": dish_id,
            "error": error
        } for dish_id, error in failed_images
    ]
}

# Calculate metrics
successful_results = [r for r in all_results if r.get("success", False)]
if successful_results:
    # Analysis time statistics
    analysis_times_seconds = [r.get("analysis_time_seconds", 0) for r in successful_results if r.get("analysis_time_seconds") is not None]
    if analysis_times_seconds:
        avg_seconds = sum(analysis_times_seconds) / len(analysis_times_seconds)
        min_seconds = min(analysis_times_seconds)
        max_seconds = max(analysis_times_seconds)
        total_seconds = sum(analysis_times_seconds)
        
        summary["performance_metrics"].update({
            "average_analysis_time_seconds": avg_seconds,
            "average_analysis_time_formatted": format_analysis_time(avg_seconds),
            "min_analysis_time_seconds": min_seconds,
            "min_analysis_time_formatted": format_analysis_time(min_seconds),
            "max_analysis_time_seconds": max_seconds,
            "max_analysis_time_formatted": format_analysis_time(max_seconds),
            "total_processing_time_seconds": total_seconds,
            "total_processing_time_formatted": format_analysis_time(total_seconds)
        })
    
    # Accuracy metrics
    errors = []
    percentage_errors = []
    true_masses = []
    predicted_masses = []
    volumes = []
    
    for result in successful_results:
        true_mass = result["ground_truth_mass_g"]
        pred_mass = result["mass_estimation"]["total_mass_g"]
        volume = result["mass_estimation"].get("calculated_volume_cm3", 0)
        error = abs(pred_mass - true_mass)
        percentage_error = (error / true_mass) * 100 if true_mass > 0 else 0
        
        errors.append(error)
        percentage_errors.append(percentage_error)
        true_masses.append(true_mass)
        predicted_masses.append(pred_mass)
        volumes.append(volume)
    
    if errors:
        summary["accuracy_metrics"].update({
            "mean_absolute_error_g": sum(errors) / len(errors),
            "mean_absolute_percentage_error": sum(percentage_errors) / len(percentage_errors),
            "min_error_g": min(errors),
            "max_error_g": max(errors)
        })
        
        # Accuracy distribution
        error_ranges = [0, 10, 20, 50, 100, 200, float('inf')]
        accuracy_distribution = {}
        for i in range(len(error_ranges)-1):
            count = len([e for e in errors if error_ranges[i] <= e < error_ranges[i+1]])
            range_name = f"{error_ranges[i]}-{error_ranges[i+1]}g" if error_ranges[i+1] != float('inf') else f">{error_ranges[i]}g"
            accuracy_distribution[range_name] = count
        summary["accuracy_metrics"]["accuracy_distribution"] = accuracy_distribution
    
    # Volume metrics
    if volumes:
        summary["volume_metrics"].update({
            "average_volume_cm3": sum(volumes) / len(volumes),
            "min_volume_cm3": min(volumes),
            "max_volume_cm3": max(volumes)
        })
        
       
        if len(volumes) > 1 and len(true_masses) > 1:
            try:
                volume_mass_corr = np.corrcoef(volumes, true_masses)[0, 1]
                summary["volume_metrics"]["volume_mass_correlation"] = round(volume_mass_corr, 4)
            except:
                summary["volume_metrics"]["volume_mass_correlation"] = "Could not calculate"
    
    # Mass statistics
    if true_masses:
        summary["mass_statistics"]["true_mass_stats"].update({
            "average_true_mass_g": sum(true_masses) / len(true_masses),
            "min_true_mass_g": min(true_masses),
            "max_true_mass_g": max(true_masses)
        })
    
    if predicted_masses:
        summary["mass_statistics"]["predicted_mass_stats"].update({
            "average_predicted_mass_g": sum(predicted_masses) / len(predicted_masses),
            "min_predicted_mass_g": min(predicted_masses),
            "max_predicted_mass_g": max(predicted_masses)
        })
    
    # Most common foods
    all_foods = []
    for result in successful_results:
        if "mass_estimation" in result and "food_items" in result["mass_estimation"]:
            for food_item in result["mass_estimation"]["food_items"]:
                all_foods.append(food_item["name"])
    
    from collections import Counter
    food_counter = Counter(all_foods)
    summary["mass_statistics"]["most_common_foods"] = food_counter.most_common(10)

# Save summary
summary_path = os.path.join(output_dir, "mass_estimation_summary_volume_based.json")
with open(summary_path, "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=4)

print(f"\n🎉 Mass estimation complete!")
print(f"📊 Results saved to: {output_json_path}")
print(f"📈 Summary saved to: {summary_path}")
print(f"✅ Successful: {summary['processing_summary']['successful_processing']}")
print(f"❌ Failed: {summary['processing_summary']['failed_processing']}")
print(f"📋 Total: {summary['processing_summary']['total_triplets']}")
print(f"🎯 Method: Volume-based estimation with raw depth maps")
print(f"📁 Raw depth directory: {raw_depth_dir}")

# Print accuracy metrics
if summary["accuracy_metrics"]["mean_absolute_error_g"]:
    print(f"\n🎯 Accuracy Metrics (Volume-based):")
    print(f"   Mean Absolute Error: {summary['accuracy_metrics']['mean_absolute_error_g']:.1f}g")
    print(f"   Mean Absolute Percentage Error: {summary['accuracy_metrics']['mean_absolute_percentage_error']:.1f}%")
    print(f"   Min Error: {summary['accuracy_metrics']['min_error_g']:.1f}g")
    print(f"   Max Error: {summary['accuracy_metrics']['max_error_g']:.1f}g")
    

    if summary["volume_metrics"]["average_volume_cm3"]:
        print(f"\n📊 Volume Statistics:")
        print(f"   Average Volume: {summary['volume_metrics']['average_volume_cm3']:.1f} cm³")
        print(f"   Volume Range: {summary['volume_metrics']['min_volume_cm3']:.1f} - {summary['volume_metrics']['max_volume_cm3']:.1f} cm³")
        if summary["volume_metrics"]["volume_mass_correlation"]:
            print(f"   Volume-Mass Correlation: {summary['volume_metrics']['volume_mass_correlation']}")
    
    if "accuracy_distribution" in summary["accuracy_metrics"]:
        print(f"\n📊 Error Distribution:")
        for range_name, count in summary["accuracy_metrics"]["accuracy_distribution"].items():
            percentage = (count / len(successful_results)) * 100
            print(f"   {range_name}: {count} dishes ({percentage:.1f}%)")

# Print failed images for review
if failed_images:
    print(f"\n⚠️ Failed dishes ({len(failed_images)} total):")
    for dish_id, error in failed_images[:10]:
        print(f"   dish_{dish_id}: {error}")
    if len(failed_images) > 10:
        print(f"   ... and {len(failed_images) - 10} more")

print(f"\n💡 Volume-Based Test Complete:")
print(f"   • Used volume calculation for ALL {len(file_triplets)} dishes")
print(f"   • No scale factor used - pure volume-based estimation")
print(f"   • Used raw depth maps from: {raw_depth_dir}")
print(f"   • Results include both mass estimates and calculated volumes")
