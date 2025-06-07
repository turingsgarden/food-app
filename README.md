# 🍽️ Food Recognizer App

A web application that lets users upload a food image, detects the dish using Gemini API, extracts ingredients (visible and hidden), estimates nutritional data, and allows user account management with uploads saved per user.

---

## 🔧 Features
- Gemini Vision API-powered dish and ingredient recognition
- Nutritional estimation with reasoning
- User signup/login/logout
- MongoDB as primary database (local)
- Individual user upload history
- Modern, minimal UI

---

## 🖥️ Tech Stack
- **Backend:** Python, Flask
- **Frontend:** HTML, Jinja2 templates, CSS (Poppins font)
- **AI:** Google Gemini API (`gemini-1.5-flash`)
- **Database:** MongoDB (local Compass or Atlas optional)

---

## 🗂️ Folder Structure
```
├── app.py               # Main Flask application
├── auth.py              # Authentication blueprint (signup/login/logout)
├── model_pipeline.py    # Gemini image analysis + MongoDB insertions
├── templates/           # HTML templates (index, login, signup, profile)
│   ├── index.html
│   ├── login.html
│   ├── signup.html
│   └── profile.html
├── uploads/             # Uploaded food images
├── requirements.txt
└── README.md            # Project readme
```

---

## 🚀 How to Run

### 1. 🔑 Gemini API Key
Make sure you have a Gemini API Key from Google AI Studio.
```python
# in model_pipeline.py
GEN_API_KEY = "<your-gemini-key>"
```

### 2. 🗃️ MongoDB
Ensure MongoDB is running locally (default: `mongodb://localhost:27017`). Use MongoDB Compass for UI.
```bash
brew services start mongodb-community@7.0  # or use mongod
```
> No setup required — app creates `food_db` with `users`, `ingredients_data`, and `nutrition_data` collections.

### 3. 🔧 Install dependencies
```bash
pip install -r requirements.txt
```

### 4. ▶️ Run Flask app
```bash
python app.py
```

---

## ✅ Usage Flow
1. **Sign Up / Login**
2. **Upload food image**
3. **See dish prediction, ingredients, nutritional info**
4. **Go to Profile** to see recent dish uploads

---

## 📦 MongoDB Structure
- **Database:** `food_db`
- **Collections:**
  - `users`: `{ _id, username, email, password }`
  - `ingredients_data`: `{ user_id, dish, image, timestamp, data: {ingredient details}}`
  - `nutrition_data`: `{ user_id, dish, image, timestamp, data: {nutrient details}}`

---

## 🔐 Authentication
- Passwords are stored as plaintext (🔒 improve later with hashing)
- Session-based login using Flask sessions

---

## 📌 Future Ideas
- Deploy on Render/Heroku + MongoDB Atlas
- Hash password storage (bcrypt)
- Allow image deletion
- Paginated profile history
- Dietary filters or calorie summary

---

## 👤 Author
Made with ❤️ by Utsav Doshi, Junyao Chen, Zhengyuan Zhou

