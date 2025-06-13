
# 🍽️ Food Recognizer App

A web application that lets users upload food images, recognizes the dish using the Gemini API, extracts visible + hidden ingredients, estimates nutrition info, and provides account-based upload history. A separate **Developer Mode** is also available to test Gemini image analysis on a curated gallery.

---

## 🔧 Features

- Gemini Vision API-powered dish and ingredient recognition
- Nutritional estimation with reasoning
- User signup/login/logout
- Upload history per user
- MongoDB backend for persistence
- 🔬 **Developer Mode**: Clickable food gallery with instant Gemini analysis
- Modern, minimal UI using HTML + Jinja2

---

## 🖥️ Tech Stack

- **Backend:** Python, Flask
- **Frontend:** HTML, CSS, Jinja2 templates
- **AI:** Google Gemini API (`gemini-1.5-flash`)
- **Database:** MongoDB (local via Compass or Atlas optional)

---

## 🗂️ Folder Structure

```
├── app.py                   # Main Flask app (user + dev mode routes)
├── auth.py                  # Signup/login/logout blueprint
├── model_pipeline.py        # Gemini prompt logic and MongoDB inserts
├── templates/
│   ├── index.html           # User homepage (upload + prediction)
│   ├── login.html
│   ├── signup.html
│   ├── profile.html         # User upload history
│   ├── developer.html       # Developer gallery page (50 images)
│   └── developer_result.html# Gemini output for clicked food image
├── static/js/dev.js         # JS to load 50 images and handle clicks
├── uploads/                 # Folder for storing uploaded user images
├── requirements.txt         # Pinned dependencies
└── README.md
```

---

## ✅ Usage Flow

### 👤 User Mode
1. Sign up / log in
2. Upload a food image
3. See predicted dish name, ingredients, and nutrition info
4. Go to **Profile** to view all past uploads

### 👨‍💻 Developer Mode
1. Click "👨‍💻 Developer Mode" on the login page (opens in new tab)
2. View 50 real food dish images (hardcoded and shuffled)
3. Click any dish → Gemini processes image → result shown in same layout as user side (dish + ingredients + nutrition)
4. No login required and no database storage

---

## 🧠 Gemini AI Features

- First Gemini prompt returns:
  - Dish Name (first line)
  - Ingredients in format: `Ingredient | Quantity | Unit | Reasoning`
- Then:
  - Prompt 2: estimates hidden ingredients
  - Prompt 3: calculates nutritional info per serving
- Final result shown with:
  - 🧾 Ingredient Table
  - 🍎 Nutrient Table

---

## 📦 MongoDB Structure

- **Database:** `food_db`
- **Collections:**
  - `users`: `{ _id, username, email, password }`
  - `ingredients_data`: `{ user_id, dish, image, timestamp, data: {ingredient details} }`
  - `nutrition_data`: `{ user_id, dish, image, timestamp, data: {nutrient details} }`

> Developer Mode does not write to MongoDB

---

## 🚀 Local Setup

### 1. 🔑 Get Gemini API Key
Create a key from [Google AI Studio](https://makersuite.google.com/app) and paste it in `model_pipeline.py`:
```python
GEN_API_KEY = "<your-api-key-here>"
```

---

### 2. 🗃️ Install MongoDB Locally
Install MongoDB using [brew](https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-os-x/) or direct from MongoDB's website.

```bash
brew tap mongodb/brew
brew install mongodb-community@7.0
brew services start mongodb-community@7.0
```

Or run:
```bash
mongod
```

Then check using Compass (optional GUI): [MongoDB Compass](https://www.mongodb.com/try/download/compass)

---

### 3. 🐍 Create & Activate Virtual Environment (Recommended - But Optional)
```bash
python -m venv env
source env/bin/activate  # macOS/Linux
env\Scripts\activate     # Windows
```

---

### 4. 📦 Install Dependencies
```bash
pip install -r requirements.txt
```

---

### 5. ▶️ Run the Flask App
```bash
python app.py
```

Then open: `http://127.0.0.1:5000`

---

## 🔐 Auth System

- Users sign up and log in using email/password
- Session-based Flask login
- Passwords currently stored in plaintext (⚠️ use hashing for production)

---

## 📂 Developer Mode Logic

- `GET /developer`: Loads `developer.html` with 50 food images
- JS (in `dev.js`) fetches images from `/developer/api/images`
- Clicking an image opens `/developer/view?image_url=...`
- Backend downloads image → runs Gemini model
- Output shown in `developer_result.html` (identical layout to user view)

---

## 🛠️ Developer Mode Customization

To add your own gallery images:
- Edit `app.py` → `/developer/api/images`
- Replace URLs with your dataset/CDN images
- Or load Food-101 dataset locally using KaggleHub

---

## 🌱 Future Enhancements

- Secure password storage with bcrypt
- Upload deletion + edit notes per dish
- Export nutrient info to PDF
- Searchable profile upload history
- Dietary recommendations and AI-based suggestions
- Image moderation & multi-dish detection
- Deploy on Render / Railway + MongoDB Atlas


---

## 👤 Author
Made with ❤️ by Utsav Doshi, Junyao Chen, Zhengyuan Zhou

