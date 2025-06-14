#!/usr/bin/env python
# coding: utf-8

# In[ ]:


import os
import json
import random
import numpy as np
import torch
import cv2
from PIL import Image, ImageDraw, ImageFont
from transformers import pipeline, Mask2FormerForUniversalSegmentation, Mask2FormerImageProcessor
from huggingface_hub import hf_hub_download, snapshot_download
import albumentations as A

# ------------------ Load ViT Classifier ------------------
# Use snapshot_download to download from Hugging Face mirror
local_dir = snapshot_download(
    repo_id="Shresthadev403/food-image-classification",
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
    random.seed(seed)
    palette = []
    for _ in range(num_classes):
        color = [random.randint(0, 255) for _ in range(3)]
        palette.append(color)
    return palette


def load_model_and_processor(device):
    directory_path = "path_to_save_model"
    all_files = os.listdir(directory_path)
    sorted_files = sorted(all_files)
    saved_model_path = os.path.join(directory_path, sorted_files[-1])

    model = Mask2FormerForUniversalSegmentation.from_pretrained(saved_model_path).to(device)
    processor = Mask2FormerImageProcessor(
        ignore_index=0,
        reduce_labels=False,
        do_resize=False,
        do_rescale=False,
        do_normalize=False,
    )
    return model, processor


def visualize_panoptic_segmentation(original_image_np, segmentation_mask, segments_info, category_names):
    segmentation_image = np.zeros_like(original_image_np)
    num_classes = len(category_names)
    palette = color_palette(num_classes)

    for segment in segments_info:
        if segment["label_id"] == 0:
            continue
        color = palette[segment["label_id"]]
        mask = segmentation_mask == segment["id"]
        segmentation_image[mask] = color

    alpha = 0.5
    overlay_image = cv2.addWeighted(original_image_np, 1 - alpha, segmentation_image, alpha, 0)
    overlay_image_pil = Image.fromarray(overlay_image)
    draw = ImageDraw.Draw(overlay_image_pil)

    base_font_size = max(20, int(min(original_image_np.shape[0], original_image_np.shape[1]) * 0.015))

    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", base_font_size)
    except IOError:
        raise RuntimeError("Custom font not found. Please ensure the font file is available.")

    for segment in segments_info:
        label_id = segment.get("label_id")
        if label_id is not None and 0 <= label_id < len(category_names):
            category = category_names[label_id]
            mask = (segmentation_mask == segment["id"]).astype(np.uint8)
            num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
            if num_labels > 1:
                largest_component = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
                centroid_x = int(centroids[largest_component][0])
                centroid_y = int(centroids[largest_component][1])
                text_position = (
                    max(0, min(centroid_x, original_image_np.shape[1] - 1)),
                    max(0, min(centroid_y, original_image_np.shape[0] - 1)),
                )
                draw.text(text_position, category, fill=(0, 0, 0), font=font)

    return overlay_image_pil


def count_pixels_per_category(segmentation_mask, segments_info, id2label):
    pixel_counts = {}
    for segment in segments_info:
        segment_id = segment["id"]
        label_id = segment["label_id"]
        category_name = id2label[label_id]
        count = np.sum(segmentation_mask == segment_id)
        if category_name in pixel_counts:
            pixel_counts[category_name] += count
        else:
            pixel_counts[category_name] = count
    return pixel_counts


def get_energy_from_json(category, json_data):
    for item in json_data["FoundationFoods"]:
        description = item.get("description", "").lower()
        if category.lower() in description:
            for nutrient in item.get("foodNutrients", []):
                nutrient_info = nutrient.get("nutrient", {})
                if nutrient_info.get("name") == "Energy":
                    return nutrient.get("amount")
    return None


def predict_masks(input_image_path):
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model, processor = load_model_and_processor(device)

    repo_id = "EduardoPacheco/FoodSeg103"
    filename = "id2label.json"
    id2label = json.load(open(hf_hub_download(repo_id, filename, repo_type="dataset"), "r"))
    id2label = {int(k): v for k, v in id2label.items()}

    image_PIL = Image.open(input_image_path)
    original_image_np = np.array(image_PIL)

    transform = A.Compose([
        A.Resize(width=512, height=512),
        A.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])
    transformed = transform(image=original_image_np)
    image = transformed["image"].transpose(2, 0, 1)

    inputs = processor([image], return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = model(**inputs)

    result = processor.post_process_instance_segmentation(
        outputs, target_sizes=[image_PIL.size[::-1]]
    )[0]

    segmentation_mask = result["segmentation"].cpu().numpy()
    segments_info = result["segments_info"]

    output_result = visualize_panoptic_segmentation(
        original_image_np, segmentation_mask, segments_info, id2label
    )

    category_counts = {}
    for segment in segments_info:
        label_id = segment["label_id"]
        if label_id in id2label and label_id != 0:
            label = id2label[label_id]
            count = np.sum(segmentation_mask == segment["id"])
            category_counts[label] = count

    total_detected_pixels = sum(category_counts.values())
    pixel_percentages = {k: round((v / total_detected_pixels) * 100, 2) for k, v in category_counts.items()}

    with open("/root/FoodData_Central_foundation_food_json_2025-04-24.json", "r") as f:
        json_data = json.load(f)

    total_energy = 0.0
    for label, percentage in pixel_percentages.items():
        energy = get_energy_from_json(label, json_data)
        if energy is not None:
            total_energy += energy * (percentage / 100.0)

    detected_labels_list = list(pixel_percentages.keys())

    return output_result, detected_labels_list, pixel_percentages, total_energy

