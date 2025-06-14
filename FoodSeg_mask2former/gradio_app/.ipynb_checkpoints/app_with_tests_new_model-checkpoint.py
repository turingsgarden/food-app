#!/usr/bin/env python
# coding: utf-8

# In[5]:

import os
os.environ["LANG"] = "en_US.UTF-8"

import os
import json
import gradio as gr
from PIL import Image
from gradio_app.model_inference_classification2 import predict_masks, vit_food_classification_local

# ------------------ Configuration ------------------
TEST_IMAGE_DIR = "/root/FoodSeg_mask2former/FoodSeg_mask2former/test_images"
BATCH_RESULTS_PATH = "/root/FoodSeg_mask2former/FoodSeg_mask2former/batch_results_by_name.json"
VISUAL_OUTPUT_DIR = "/root/FoodSeg_mask2former/FoodSeg_mask2former/visualized_outputs"

with open(BATCH_RESULTS_PATH, "r") as f:
    batch_results_by_name = json.load(f)

# Get sorted image paths
test_image_paths = sorted([
    os.path.join(TEST_IMAGE_DIR, fname)
    for fname in os.listdir(TEST_IMAGE_DIR)
    if fname.lower().endswith(('.jpg', '.jpeg', '.png'))
])

# ------------------ Precomputed Viewer ------------------
def show_cached_results(all_items, evt: gr.SelectData):
    selected_index = evt.index
    selected_image_path = all_items[selected_index][0]  # (path, label)
    print(f"Selected image path: {selected_image_path}")

    filename = os.path.basename(selected_image_path)
    result = batch_results_by_name.get(filename)

    if result is None:
        return None, [], {}, 0.0, "No result found"

    vis_path = os.path.join(VISUAL_OUTPUT_DIR, f"vis_{filename}")
    return (
        vis_path,
        result["detected_labels"],
        result["pixel_percentages"],
        result["total_energy_kcal"],
        result["vit_prediction"]
    )

# ------------------ Inference Function ------------------
def combined_prediction(image_path):
    output_image, detected_labels_list, pixel_percentages, total_energy = predict_masks(image_path)
    food_label = vit_food_classification_local(image_path)
    return output_image, detected_labels_list, pixel_percentages, total_energy, food_label

# ------------------ Gradio Interface ------------------
with gr.Blocks() as FoodSeg_GUI:
    gr.Markdown("# **<p align='center'>Fine-Tuned Mask2Former & ViT-based Classifier for Food Images</p>**")

    with gr.Row():
        with gr.Column(scale=1):
            image_items = [(p, os.path.basename(p)) for p in test_image_paths]
            gallery = gr.Gallery(
                label="Select a test image",
                value=image_items,  # List of (filepath, label)
                columns=3,
                rows=3,
                allow_preview=True
            )
        with gr.Column(scale=1.3):
            input_image = gr.Image(type="filepath", label="Selected / Uploaded Image")
            output_image = gr.Image(label="Segmentation Result")
            detected_labels = gr.JSON(label="Detected Labels")
            gr.Markdown("Note: Model from https://github.com/NimaVahdat/FoodSeg_mask2former")
            pixel_percentages = gr.JSON(label="Category Pixel Percentages")
            gr.Markdown("Note: Ingredient pixel percentage = ingredient category pixel / total pixels")
            total_energy_output = gr.Number(label="Total Energy (kcal)")
            gr.Markdown("Note: Suppose the weight of the dish is 100g, then total energy = sum (ingredient pixel percentage × ingredient unit calorie per 100g).")
            vit_prediction = gr.Textbox(label="ViT-based Top Food Label")
            gr.Markdown("Note: Model from https://huggingface.co/Shresthadev403/food-image-classification")
            

    with gr.Row():
        upload_button = gr.Button("Run on Uploaded Image")

    # ✅ Use select with evt.index and all items
    gallery.select(
        fn=show_cached_results,
        inputs=[gallery],
        outputs=[output_image, detected_labels, pixel_percentages, total_energy_output, vit_prediction]
    )

    upload_button.click(
        fn=combined_prediction,
        inputs=input_image,
        outputs=[output_image, detected_labels, pixel_percentages, total_energy_output, vit_prediction]
    )


if __name__ == "__main__":
    FoodSeg_GUI.launch(
        share=True,
        debug=False,
        allowed_paths=[TEST_IMAGE_DIR, VISUAL_OUTPUT_DIR]
    )


# In[ ]:




