# 🍽️ Food Recognizer App

A Flask-based web application that lets users upload food images to detect dish names, extract visible and hidden ingredients, and estimate nutritional values using the **Gemini Vision API**. Users can manage uploads through a personal profile, while a separate **Developer Mode** lets developers test Gemini analysis on a curated food image gallery — no login required.

---

## 🔧 Features

- 🧠 Gemini Vision API for dish + ingredient + nutrition inference
- 📝 User signup, login, logout with session-based auth
- 📁 Per-user upload history with timestamps
- 🧾 Dual ingredient detection: visible + inferred (hidden)
- 🍎 Nutrition table with quantified reasoning
- 💾 MongoDB backend for storing uploads and predictions
- 👨‍💻 **Developer Mode**: gallery of real food images, Gemini-on-click
- 💡 Minimal, clean UI using HTML + CSS + Jinja2

---

## 🖥️ Tech Stack

| Layer        | Technology            |
|--------------|------------------------|
| Backend      | Python, Flask          |
| Frontend     | HTML, CSS, Jinja2      |
| AI/ML        | Google Gemini API      |
| Database     | MongoDB (local or Atlas) |

---

## 🗂️ Project Structure

```
├── app.py                   # Main Flask app (routes for user + dev)
├── auth.py                  # Auth Blueprint (login/signup/logout)
├── model_pipeline.py        # Gemini prompts and MongoDB logic
├── templates/               # HTML templates
│   ├── index.html           # Upload + results (user mode)
│   ├── login.html
│   ├── signup.html
│   ├── profile.html         # Upload history
│   ├── developer.html       # Developer gallery page (25 images)
│   └── developer_result.html# Gemini result view (dev mode)
├── uploads/                 # User-uploaded images
├── requirements.txt         # Python dependencies
└── README.md
```

---

## ✅ Usage Flow

### 👤 User Mode
1. Sign up or log in
2. Upload a food image (JPEG/PNG)
3. View:
   - 🧾 Dish name
   - ✅ Ingredients (visible + hidden)
   - 🍎 Nutrition info
4. Visit your **Profile** to view all uploaded dishes and details

### 👨‍💻 Developer Mode
1. Click **"👨‍💻 Developer Mode"** on the login screen
2. Browse a gallery of 25 random food images from Foodish API
3. Click any image to:
   - Run Gemini vision model
   - View predicted dish, ingredients, and nutrition info
4. No login required, and no data is stored in MongoDB

---

## 🧠 Gemini AI Processing

Gemini is used in **3 steps** per image:
1. **Prompt 1**: Extracts visible ingredients in format  
   `Ingredient | Quantity | Unit | Reasoning`
2. **Prompt 2**: Infers hidden (non-visible) ingredients
3. **Prompt 3**: Estimates nutrition per serving

All results are formatted into structured tables for display.

---

## 📦 MongoDB Design

Database: `food_db`

| Collection         | Contents |
|--------------------|----------|
| `users`            | `{ _id, username, email, password (hashed) }` |
| `uploads`          | `{ user_id, filename, dish_prediction, nutrition_info, image_description, hidden_ingredients, timestamp }` |
| `ingredients_data` | `{ user_id, dish, image, timestamp, data: { structured ingredients } }` |
| `nutrition_data`   | `{ user_id, dish, image, timestamp, data: { structured nutrients } }` |

> 🔒 Developer Mode does **not** write to any database.

---

## 🚀 Local Setup Instructions

### 1. 🔐 Get Gemini API Key

Visit [Google AI Studio](https://makersuite.google.com/app)  
Paste your API key in `model_pipeline.py`:
```python
GEN_API_KEY = "your-key-here"
```

> ✅ Tip: For better security, use `python-dotenv` and load from `.env`

---

### 2. 🗃️ Install MongoDB Locally

On macOS (via Homebrew):
```bash
brew tap mongodb/brew
brew install mongodb-community@7.0
brew services start mongodb-community@7.0
```

On Linux or Windows: [Install MongoDB Docs](https://www.mongodb.com/docs/manual/installation/)

---

### 3. 📦 Install Python Dependencies

Run this in your project folder:

```bash
pip install -r requirements.txt
```

> *(Optional but recommended)*: Use a virtual environment  
```bash
python -m venv env
source env/bin/activate  # macOS/Linux
env\Scriptsctivate     # Windows
```

---

### 4. ▶️ Run the App

```bash
python app.py
```

Then open: [http://localhost:5000](http://localhost:5000)

---

## 🔐 Auth & Security Notes

- Passwords are hashed using `werkzeug.security.generate_password_hash`
- Flask session handles user state
- MongoDB stores user and upload info
- Gemini key is currently stored in code — migrate to `.env` for production

---

## 🌱 Roadmap & Future Enhancements

- [ ] Secure API key with `.env` + `python-dotenv`
- [ ] Allow users to delete/edit uploads
- [ ] Profile filtering and search
- [ ] Export nutrition reports to PDF
- [ ] YOLOv8 prefiltering before Gemini call
- [ ] Deploy on Render / Railway + MongoDB Atlas
- [ ] AI meal planning or health insights

---

## 👤 Author
Made with ❤️ by Utsav Doshi, Junyao Chen, Zhengyuan Zhou

