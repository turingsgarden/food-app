import os
import json
import random
import numpy as np
import torch
import cv2
from PIL import Image, ImageDraw, ImageFont
from transformers import Mask2FormerForUniversalSegmentation, Mask2FormerImageProcessor
from huggingface_hub import hf_hub_download
import albumentations as A

# In gradio_app/model_inference.py

import os
from PIL import Image
from transformers import pipeline
from huggingface_hub import snapshot_download

# Load the classifier once (so it’s reused across calls)
local_dir = snapshot_download(
    repo_id="ashaduzzaman/vit-finetuned-food101",
    repo_type="model",
    endpoint="https://hf-mirror.com"
)
food_classifier = pipeline(
    "image-classification",
    model=local_dir
)

def vit_food_classification_local(image_path):
    """
    Classify a food image using the ViT-based classifier.
    Returns the predicted label.
    """
    image = Image.open(image_path).convert("RGB")
    result = food_classifier(image)
    # Get the top prediction
    if result:
        top_label = result[0]['label']
        return top_label
    return "No prediction"


def color_palette(num_classes=150, seed=85):
    """
    Generates a consistent color palette for a given number of classes by setting a random seed.

    Args:
        num_classes (int): Number of classes/colors to generate.
        seed (int): Seed for the random number generator.

    Returns:
        list: A list of RGB values.
    """
    random.seed(seed)
    palette = []
    for _ in range(num_classes):
        color = [random.randint(0, 255) for _ in range(3)]
        palette.append(color)
    return palette


def load_model_and_processor(device):
    """
    Loads the Mask2Former model and processor from the latest checkpoint in the specified directory.

    Args:
        device (str): Device to load the model onto (e.g., 'cpu' or 'cuda').

    Returns:
        tuple: A tuple containing the loaded model and processor.
    """
    directory_path = "path_to_save_model"
    all_files = os.listdir(directory_path)
    sorted_files = sorted(all_files)
    saved_model_path = os.path.join(directory_path, sorted_files[-1])

    model = Mask2FormerForUniversalSegmentation.from_pretrained(saved_model_path).to(
        device
    )
    processor = Mask2FormerImageProcessor(
        ignore_index=0,
        reduce_labels=False,
        do_resize=False,
        do_rescale=False,
        do_normalize=False,
    )
    return model, processor


def visualize_panoptic_segmentation(
    original_image_np, segmentation_mask, segments_info, category_names
):
    """
    Visualizes the segmentation mask overlaid on the original image with category labels.

    Args:
        original_image_np (np.ndarray): The original image in NumPy array format.
        segmentation_mask (np.ndarray): The segmentation mask.
        segments_info (list): Information about the segments.
        category_names (list): List of category names corresponding to segment IDs.

    Returns:
        PIL.Image.Image: The overlayed image with segmentation mask and labels.
    """
    # Create a blank image for the segmentation mask
    segmentation_image = np.zeros_like(original_image_np)

    num_classes = len(category_names)
    palette = color_palette(num_classes)

    # Apply colors to the segmentation mask
    for segment in segments_info:
        if segment["label_id"] == 0:
            continue
        color = palette[segment["label_id"]]
        mask = segmentation_mask == segment["id"]
        segmentation_image[mask] = color

    # Overlay the segmentation mask on the original image
    alpha = 0.5  # Transparency for the overlay
    overlay_image = cv2.addWeighted(
        original_image_np, 1 - alpha, segmentation_image, alpha, 0
    )

    # Convert to PIL image for text drawing
    overlay_image_pil = Image.fromarray(overlay_image)
    draw = ImageDraw.Draw(overlay_image_pil)

    # Set up font size
    base_font_size = max(
        20, int(min(original_image_np.shape[0], original_image_np.shape[1]) * 0.015)
    )

    # Optional: Load custom font
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", base_font_size)
    except IOError:
        raise RuntimeError(
            "Custom font not found. Please ensure the font file is available."
        )

    # Draw category labels on the image
    for segment in segments_info:
        label_id = segment.get("label_id")
        if label_id is not None and 0 <= label_id < len(category_names):
            category = category_names[label_id]
            mask = (segmentation_mask == segment["id"]).astype(np.uint8)
            num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(
                mask, connectivity=8
            )

            if num_labels > 1:
                largest_component = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
                centroid_x = int(centroids[largest_component][0])
                centroid_y = int(centroids[largest_component][1])

                # Ensure text is within image bounds
                text_position = (
                    max(0, min(centroid_x, original_image_np.shape[1] - 1)),
                    max(0, min(centroid_y, original_image_np.shape[0] - 1)),
                )
                draw.text(text_position, category, fill=(0, 0, 0), font=font)

    return overlay_image_pil


def count_pixels_per_category(segmentation_mask, segments_info, id2label):
    """
    Count the number of pixels for each detected category.
    """
    pixel_counts = {}
    for segment in segments_info:
        segment_id = segment["id"]
        label_id = segment["label_id"]
        category_name = id2label[label_id]

        # Count how many pixels in the mask have this segment_id
        count = np.sum(segmentation_mask == segment_id)

        # Add to the dictionary
        if category_name in pixel_counts:
            pixel_counts[category_name] += count
        else:
            pixel_counts[category_name] = count

    return pixel_counts

def get_energy_from_json(category, json_data):
    """
    For a given category (like 'onion'), find the corresponding energy value
    in the JSON data (by checking if category is in description).
    Returns energy in kcal if found, otherwise None.
    """
    for item in json_data["FoundationFoods"]:
        description = item.get("description", "").lower()
        if category.lower() in description:
            for nutrient in item.get("foodNutrients", []):
                nutrient_info = nutrient.get("nutrient", {})
                if nutrient_info.get("name") == "Energy":
                    return nutrient.get("amount")
    return None

def predict_masks(input_image_path):
    """
    Predicts and visualizes segmentation masks for a given image.
    Returns the image, the list of detected category names,
    pixel percentage per category (summing to 100%), and total energy estimate.
    """
    # Determine device to use
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model, processor = load_model_and_processor(device)

    # Load category labels
    repo_id = "EduardoPacheco/FoodSeg103"
    filename = "id2label.json"
    id2label = json.load(open(hf_hub_download(repo_id, filename, repo_type="dataset"), "r"))
    id2label = {int(k): v for k, v in id2label.items()}

    # Load and preprocess image
    image_PIL = Image.open(input_image_path)
    original_image_np = np.array(image_PIL)

    transform = A.Compose([
        A.Resize(width=512, height=512),
        A.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])
    transformed = transform(image=original_image_np)
    image = transformed["image"].transpose(2, 0, 1)

    # Predict
    inputs = processor([image], return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = model(**inputs)
    result = processor.post_process_instance_segmentation(
        outputs, target_sizes=[image_PIL.size[::-1]]
    )[0]
    segmentation_mask = result["segmentation"].cpu().numpy()
    segments_info = result["segments_info"]

    # Visualization
    output_result = visualize_panoptic_segmentation(
        original_image_np, segmentation_mask, segments_info, id2label
    )

    # Calculate pixel counts for detected categories
    category_counts = {}
    for segment in segments_info:
        label_id = segment["label_id"]
        if label_id in id2label and label_id != 0:  # Exclude background
            label = id2label[label_id]
            count = np.sum(segmentation_mask == segment["id"])
            category_counts[label] = count

    # Compute percentages relative to detected pixel counts (sum=100%)
    total_detected_pixels = sum(category_counts.values())
    pixel_percentages = {k: round((v / total_detected_pixels) * 100, 2) for k, v in category_counts.items()}

    # Load your JSON dataset
    with open("/root/FoodData_Central_foundation_food_json_2025-04-24.json", "r") as f:
        json_data = json.load(f)

    # Calculate energy contribution per category
    total_energy = 0.0
    for label, percentage in pixel_percentages.items():
        energy = get_energy_from_json(label, json_data)
        if energy is not None:
            total_energy += energy * (percentage / 100.0)

    # Detected labels list
    detected_labels_list = list(pixel_percentages.keys())

    # Return final results
    return output_result, detected_labels_list, pixel_percentages, total_energy
