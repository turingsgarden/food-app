from flask import Flask, request, render_template, send_from_directory, redirect, url_for, session
import os
from werkzeug.utils import secure_filename
from model_pipeline import full_image_analysis
from auth import auth_bp  # auth blueprint (login, signup, logout)

app = Flask(__name__)
app.secret_key = 'your-secure-key'  # Use os.urandom(24) in production for security
app.config['UPLOAD_FOLDER'] = 'uploads'

# Register the authentication blueprint
app.register_blueprint(auth_bp)

@app.route('/')
def index():
    return render_template('index.html', username=session.get('username'))

@app.route('/upload', methods=['POST'])
def upload():
    if 'user_id' not in session:
        return render_template('index.html', error='Please log in to analyze an image.', username=None)

    if 'image' not in request.files:
        return render_template('index.html', error='No image uploaded.', username=session.get('username'))

    image = request.files['image']
    filename = secure_filename(image.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    image.save(filepath)

    try:
        result = full_image_analysis(filepath, session['user_id'])
        result['image_path'] = filename
        result['username'] = session.get('username')
        return render_template('index.html', **result)
    except Exception as e:
        return render_template('index.html', error=str(e), username=session.get('username'))

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

@app.route('/profile')
def profile():
    if 'user_id' not in session:
        return redirect(url_for('auth.login'))

    from pymongo import MongoClient
    client = MongoClient("mongodb://localhost:27017")
    db = client.food_db
    ingredients_collection = db.ingredients_data

    user_id = session['user_id']
    dishes = ingredients_collection.find({'user_id': user_id}).sort('timestamp', -1)

    return render_template('profile.html', username=session.get('username'), dishes=dishes)

if __name__ == '__main__':
    if not os.path.exists('uploads'):
        os.makedirs('uploads')
    app.run(debug=True)
