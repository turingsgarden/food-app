# Summary of Food Datasets with Ingredient and Nutrition Information

--

### FoodSeg-103
- **Included Information:** Visible ingredients
- **Image Source:** Recipe1M
- **Annotation Source:** 
  - Initial annotation:
    1. Identified ingredient categories
    2. Tagged each ingredient
    3. Drew precise masks
  - Refinement:
    1. Correct mislabeled data
    2. Remove categories appearing in fewer than 5 images
    3. Merge visually similar categories
- **Source / Dataset Link:** [FoodSeg-103](https://arxiv.org/pdf/2105.05409)
- **Paper:** [PDF](https://arxiv.org/pdf/2105.05409)

---

### FoodSeg-154
- **Included Information:** Visible ingredients
- **Image Source:** Recipe1M
- **Annotation Source:** Same as FoodSeg-103

---

### Nutrition5k
- **Included Information:** 
  1. Total food mass  
  2. Macronutrients (fat, carbs, protein)  
  3. Total calories  
  *Information for both whole dish & each ingredient*
- **Image Source:** Google cafeterias using a custom scanning rig / robotic sensor array
- **Annotation Source:** 
  1. Ingredients added incrementally to a plate
  2. Robot weighs the plate and captures RGB + RGB-D images in real time
  3. Nutrition (calories, fat, carbs, protein) computed using USDA database
  4. Synchronized recording of four 360° RGB videos, one depth image, and incremental weights
- **Source / Dataset Link:** [Nutrition5k](https://github.com/google-research-datasets/Nutrition5k)
- **Paper:** [PDF](https://arxiv.org/pdf/2103.03375)

---

### MyFoodRepo-273
- **Included Information:** Instance segmentation for each ingredient (polygon masks per food region)
- **Image Source:** User-uploaded real meal photos via MyFoodRepo app
- **Annotation Source:** 
  1. Algorithm generates initial instance segmentation and food class predictions
  2. Humans verify and correct segmentations and class labels as needed
- **Paper:** [PDF](https://arxiv.org/pdf/2106.14977)

---

### VireoFood-172
- **Included Information:** Visible ingredients
- **Image Source:** 
  1. Compiled 172 food classes from “Go Cooking” and “Meishi”
  2. Images crawled from Baidu and Google based on food classes
- **Annotation Source:** 
  1. Make an ingredient list based on the recipe for 172 dish classes
  2. 10 experienced homemakers for ingredient labeling
  3. Researcher verification
- **Source / Dataset Link:** [Vireo-Food 172 dataset](https://fvl.fudan.edu.cn/dataset/vireofood172/list.htm)
- **Paper:** [PDF](https://ink.library.smu.edu.sg/cgi/viewcontent.cgi?params=/context/sis_research/article/7501/&path_info=2964284.2964315.pdf)

---

### Recipe1M
- **Included Information:** 
  1. Recipe text:
     - Dishname
     - Ingredient
     - Nutrition information
  2. Images
- **Image Source:** 20+ popular recipe websites
- **Annotation Source:** 
  1. Recipes collected from 20+ popular websites
  2. Words tagged with NLTK; 20 measurable units identified (e.g., cup, g, ml)
  3. Ingredients matched with the USDA nutrient database
- **Source / Dataset Link:** [Recipe1M / Recipe1M+](https://arxiv.org/pdf/1810.06553)
- **Paper / Website:** [Link](https://im2recipe.csail.mit.edu/tpami19.pdf)
