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

# Your full list of 100 URLs
food_image_urls = [
    "https://foodish-api.com/images/biryani/biryani12.jpg",
    "https://foodish-api.com/images/burger/burger4.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken17.jpg",
    "https://foodish-api.com/images/dessert/dessert8.jpg",
    "https://foodish-api.com/images/dosa/dosa19.jpg",
    "https://foodish-api.com/images/idly/idly11.jpg",
    "https://foodish-api.com/images/pasta/pasta7.jpg",
    "https://foodish-api.com/images/pizza/pizza15.jpg",
    "https://foodish-api.com/images/rice/rice13.jpg",
    "https://foodish-api.com/images/samosa/samosa3.jpg",

    "https://foodish-api.com/images/biryani/biryani3.jpg",
    "https://foodish-api.com/images/burger/burger16.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken1.jpg",
    "https://foodish-api.com/images/dessert/dessert20.jpg",
    "https://foodish-api.com/images/dosa/dosa6.jpg",
    "https://foodish-api.com/images/idly/idly2.jpg",
    "https://foodish-api.com/images/pasta/pasta11.jpg",
    "https://foodish-api.com/images/pizza/pizza8.jpg",
    "https://foodish-api.com/images/rice/rice5.jpg",
    "https://foodish-api.com/images/samosa/samosa11.jpg",

    "https://foodish-api.com/images/biryani/biryani6.jpg",
    "https://foodish-api.com/images/burger/burger20.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken3.jpg",
    "https://foodish-api.com/images/dessert/dessert1.jpg",
    "https://foodish-api.com/images/dosa/dosa18.jpg",
    "https://foodish-api.com/images/idly/idly19.jpg",
    "https://foodish-api.com/images/pasta/pasta15.jpg",
    "https://foodish-api.com/images/pizza/pizza5.jpg",
    "https://foodish-api.com/images/rice/rice17.jpg",
    "https://foodish-api.com/images/samosa/samosa1.jpg",

    "https://foodish-api.com/images/biryani/biryani15.jpg",
    "https://foodish-api.com/images/burger/burger11.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken7.jpg",
    "https://foodish-api.com/images/dessert/dessert16.jpg",
    "https://foodish-api.com/images/dosa/dosa10.jpg",
    "https://foodish-api.com/images/idly/idly6.jpg",
    "https://foodish-api.com/images/pasta/pasta2.jpg",
    "https://foodish-api.com/images/pizza/pizza13.jpg",
    "https://foodish-api.com/images/rice/rice10.jpg",
    "https://foodish-api.com/images/samosa/samosa20.jpg",

    "https://foodish-api.com/images/biryani/biryani7.jpg",
    "https://foodish-api.com/images/burger/burger13.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken19.jpg",
    "https://foodish-api.com/images/dessert/dessert12.jpg",
    "https://foodish-api.com/images/dosa/dosa3.jpg",
    "https://foodish-api.com/images/idly/idly1.jpg",
    "https://foodish-api.com/images/pasta/pasta8.jpg",
    "https://foodish-api.com/images/pizza/pizza3.jpg",
    "https://foodish-api.com/images/rice/rice4.jpg",
    "https://foodish-api.com/images/samosa/samosa5.jpg",

    "https://foodish-api.com/images/biryani/biryani20.jpg",
    "https://foodish-api.com/images/burger/burger3.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken12.jpg",
    "https://foodish-api.com/images/dessert/dessert5.jpg",
    "https://foodish-api.com/images/dosa/dosa2.jpg",
    "https://foodish-api.com/images/idly/idly13.jpg",
    "https://foodish-api.com/images/pasta/pasta14.jpg",
    "https://foodish-api.com/images/pizza/pizza10.jpg",
    "https://foodish-api.com/images/rice/rice9.jpg",
    "https://foodish-api.com/images/samosa/samosa8.jpg",

    "https://foodish-api.com/images/biryani/biryani9.jpg",
    "https://foodish-api.com/images/burger/burger7.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken8.jpg",
    "https://foodish-api.com/images/dessert/dessert9.jpg",
    "https://foodish-api.com/images/dosa/dosa14.jpg",
    "https://foodish-api.com/images/idly/idly17.jpg",
    "https://foodish-api.com/images/pasta/pasta18.jpg",
    "https://foodish-api.com/images/pizza/pizza18.jpg",
    "https://foodish-api.com/images/rice/rice18.jpg",
    "https://foodish-api.com/images/samosa/samosa14.jpg",

    "https://foodish-api.com/images/biryani/biryani1.jpg",
    "https://foodish-api.com/images/burger/burger6.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken5.jpg",
    "https://foodish-api.com/images/dessert/dessert2.jpg",
    "https://foodish-api.com/images/dosa/dosa13.jpg",
    "https://foodish-api.com/images/idly/idly8.jpg",
    "https://foodish-api.com/images/pasta/pasta9.jpg",
    "https://foodish-api.com/images/pizza/pizza1.jpg",
    "https://foodish-api.com/images/rice/rice8.jpg",
    "https://foodish-api.com/images/samosa/samosa10.jpg",

    "https://foodish-api.com/images/biryani/biryani19.jpg",
    "https://foodish-api.com/images/burger/burger14.jpg",
    "https://foodish-api.com/images/butter-chicken/butter-chicken4.jpg",
    "https://foodish-api.com/images/dessert/dessert18.jpg",
    "https://foodish-api.com/images/dosa/dosa16.jpg",
    "https://foodish-api.com/images/idly/idly14.jpg",
    "https://foodish-api.com/images/pasta/pasta5.jpg",
    "https://foodish-api.com/images/pizza/pizza20.jpg",
    "https://foodish-api.com/images/rice/rice6.jpg",
    "https://foodish-api.com/images/samosa/samosa17.jpg"
] 

@app.route('/developer')
def developer_gallery():
    selected_images = random.sample(food_image_urls, 25)
    return render_template('developer.html', images=selected_images)


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
