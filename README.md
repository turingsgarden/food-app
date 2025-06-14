## Installation Instruction
1. Clone the Repository:
   ```
   git clone --branch YifanZhang https://github.com/turingsgarden/food-app.git
   cd food-app
   ```
2. Install Dependencies:
   ```
   pip install -r requirements.txt
   cd FoodSeg_mask2former
   ```
3. Run the Web:
   ```
   python -m gradio_app.app_with_tests_new_model
   ```
4. If running unsuccess, maybe need to train the model first (even though I include the trained model inside):
   ```
   python  -m scripts.run_training
   ```

## Issues
There are two main issues with the current system. 

First, the recognized ingredients are limited, and many actual food items cannot be identified. For example, in hot_and_sour_soup.jpg, the model fails to recognize wood ear mushroom (木耳), and in miso_soup.jpg, it does not detect mushroom. 

Second, some of the identified categories do not exist in the nutritional database, which prevents calorie calculation. For instance, gyoza.jpg is labeled as pie, but "pie" is not available in the database. Similarly, hot_and_sour_soup.jpg is recognized as soup, but no corresponding entry exists in the nutritional database for calorie lookup.
   
