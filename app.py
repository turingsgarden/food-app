from flask import Flask, request, render_template, send_from_directory, redirect, session, jsonify
import os, requests, random
from datetime import datetime
from tempfile import NamedTemporaryFile
from werkzeug.utils import secure_filename
from bson import ObjectId
from pymongo import MongoClient
from auth import auth_bp
import requests
from tempfile import NamedTemporaryFile
import kagglehub
import base64
from model_pipeline import full_image_analysis


app = Flask(__name__)  # ✅ Initialize the app first


from model_pipeline import (
    analyze_image_with_gemini,
    extract_dish_name,
    extract_ingredients_only,
    search_hidden_ingredients,
    estimate_nutrition_from_ingredients
)


app = Flask(__name__)
app.secret_key = 'your-secure-key'
app.config['UPLOAD_FOLDER'] = 'uploads'

# MongoDB
client = MongoClient("mongodb://localhost:27017/")
db = client['food_db']
users_collection = db['users']
uploads_collection = db['uploads']
app.register_blueprint(auth_bp)

# ---------- USER MODE ---------- #
@app.route('/')
def index():
    return render_template('index.html', username=session.get('username'))

@app.route('/upload', methods=['POST'])
def upload():
    if 'user_id' not in session:
        return render_template('index.html', error='Please log in.', username=None)

    image = request.files['image']
    filename = secure_filename(image.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    image.save(filepath)

    try:
        result = full_image_analysis(filepath, session['user_id'])
        result['image_path'] = filename
        result['username'] = session.get('username')

        uploads_collection.insert_one({
            'user_id': session['user_id'],
            'filename': filename,
            'dish_prediction': result['dish_prediction'],
            'nutrition_info': result['nutrition_info'],
            'image_description': result['image_description'],
            'hidden_ingredients': result['hidden_ingredients'],
            'timestamp': datetime.now()
        })

        return render_template('index.html', **result)
    except Exception as e:
        return render_template('index.html', error=str(e), username=session.get('username'))

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

@app.route('/profile')
def profile():
    if 'user_id' not in session:
        return redirect('/login')
    user = users_collection.find_one({'_id': ObjectId(session['user_id'])})
    uploads = uploads_collection.find({'user_id': session['user_id']}).sort('timestamp', -1)
    return render_template('profile.html', username=user['username'], uploads=list(uploads))


# ---------- DEVELOPER MODE ---------- #

@app.route("/developer")
def developer_gallery():
    image_urls = []

    for _ in range(20):
        try:
            res = requests.get("https://foodish-api.com/api/")
            if res.status_code == 200:
                image_urls.append(res.json()["image"])
        except:
            continue

    return render_template("developer.html", sample_images=image_urls)


@app.route("/developer/view")
def developer_view():
    image_url = request.args.get("image_url")
    if not image_url:
        return "Missing image URL", 400

    try:
        img_data = requests.get(image_url).content
        with NamedTemporaryFile(delete=False, suffix=".jpg") as temp_file:
            temp_file.write(img_data)
            temp_path = temp_file.name
    except Exception as e:
        return f"Image download error: {e}", 500

    try:
        gemini_description = analyze_image_with_gemini(temp_path)
        dish_name = extract_dish_name(gemini_description)
        cleaned_ingredients = extract_ingredients_only(gemini_description)
        hidden_ingredients = search_hidden_ingredients(dish_name, cleaned_ingredients)
        nutrition_info = estimate_nutrition_from_ingredients(dish_name, cleaned_ingredients)

        return render_template("developer_result.html",
                               image_url=image_url,
                               dish_prediction=dish_name,
                               image_description=gemini_description,
                               hidden_ingredients=hidden_ingredients,
                               nutrition_info=nutrition_info)
    except Exception as e:
        return f"Gemini processing error: {e}", 500


if __name__ == '__main__':
    os.makedirs('uploads', exist_ok=True)
    app.run(debug=True)
