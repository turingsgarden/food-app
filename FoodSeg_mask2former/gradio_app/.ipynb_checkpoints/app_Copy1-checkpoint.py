import gradio as gr
from gradio_app.model_inference_Copy1 import predict_masks, vit_food_classification_local

def combined_prediction(image_path):
    # 1️⃣ Main segmentation model
    output_image, detected_labels_list, pixel_percentages, total_energy = predict_masks(image_path)

    # 2️⃣ ViT-based classification model
    food_label = vit_food_classification_local(image_path)

    # 3️⃣ Return all outputs
    return output_image, detected_labels_list, pixel_percentages, total_energy, food_label

with gr.Blocks() as FoodSeg_GUI:
    # Centered title and subtitle
    gr.Markdown(
        "# **<p align='center'>Fine-Tuned Mask2Former & ViT-based Classifier for Food Images</p>**"
    )

    with gr.Group():
        with gr.Row():
            with gr.Column(scale=1.5):
                input_image = gr.Image(
                    type="filepath", label="Choose your image or drag and drop here:"
                )
            with gr.Column(scale=1.5):
                output_image = gr.Image(label="Mask2Former Output:")
                detected_labels = gr.JSON(label="Detected Labels")
                pixel_percentages = gr.JSON(label="Category Pixel Percentages")
                total_energy_output = gr.Number(label="Total Energy (kcal)")  # Energy output
                vit_prediction = gr.Textbox(label="ViT-based Top Food Label")  # ViT result

    with gr.Group():
        with gr.Row():
            with gr.Column(scale=1):
                start_run = gr.Button("Get the output")

    # Outputs updated to include the new ViT-based classification
    start_run.click(
        combined_prediction,
        inputs=input_image,
        outputs=[output_image, detected_labels, pixel_percentages, total_energy_output, vit_prediction]
    )

if __name__ == "__main__":
    FoodSeg_GUI.launch(share=True, debug=False)
