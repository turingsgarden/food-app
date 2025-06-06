
# 🍽️ AI-Powered Food Ingredient & Nutrition Recognizer

This Flask-based web app allows users to upload a food image, analyzes the image using Google's Gemini API to extract:
- Dish name
- Visible & hidden ingredients with quantities and reasoning
- Estimated nutritional information

All extracted data is stored in MongoDB for traceability and further analysis.

---

## 🔧 Project Structure

```
├── app.py                  # Flask backend
├── index.html              # Frontend interface
├── model_pipeline.py       # Gemini image + text analysis + MongoDB integration
├── uploads/                # Uploaded food images
├── requirements.txt        # Dependencies
└── README.md               # Project instructions
```

---

## ⚙️ Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/food-image-nutrition.git
cd food-image-nutrition
```

### 2. Create and Activate Virtual Environment

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Add Your Gemini API Key

Edit `model_pipeline.py`:
```python
GEN_API_KEY = "your_gemini_api_key_here"
```

You can get a free API key from https://makersuite.google.com/app/apikey

---

## 🔌 MongoDB Setup (Local)

1. Make sure MongoDB is installed and running locally (Compass or CLI).
2. Default URI used: `mongodb://localhost:27017/`
3. The database used is: `food_app`
4. Collections:
   - `ingredients`: stores parsed ingredients from images.
   - `nutrition`: stores parsed nutrition estimates.

---

## 🚀 Run the App

```bash
python app.py
```

Then open `http://127.0.0.1:5000/` in your browser.

---

## 💾 Data Storage Format

Each dish's data is stored in MongoDB under a unique key like:

```json
{
  "vada-pav.jpg - 2025-06-05T21:23:38.827694": {
    "Potato": {
      "Quantity Number/Value": 2,
      "Unit": "medium",
      "Reasoning": "Base for the vada"
    },
    ...
  }
}
```

---

## ✅ Features Summary

- Gemini-powered image-to-text parsing
- Visible + hidden ingredients detection
- Nutrition estimation per serving
- Automatic JSON structure parsing
- MongoDB integration
- Web UI for uploading and analysis

---

## 📌 Notes

- Gemini API quota may limit excessive use.
- Ensure MongoDB is running locally for persistence.

---

## 🧠 Future Tasks

- [ ] Add user accounts
- [ ] Enable search by ingredient
- [ ] Deploy online (e.g. Render, Fly.io, etc.)

---

Made with ❤️ for foodies and AI enthusiasts.
