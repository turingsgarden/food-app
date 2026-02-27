from model_pipeline import full_image_analysis

if __name__ == "__main__":
    image_path = "test_food.jpg"   # put your image path here
    user_id = "test_user"

    result = full_image_analysis(image_path, user_id)

    print("\n=== ANALYSIS RESULT ===")
    for key, value in result.items():
        print(f"{key}: {value}")