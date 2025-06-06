from flask import Flask, request, render_template, send_from_directory
import os
from werkzeug.utils import secure_filename
from model_pipeline import full_image_analysis

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'uploads'

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload():
    if 'image' not in request.files:
        return render_template('index.html', error='No image uploaded')

    image = request.files['image']
    filename = secure_filename(image.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    image.save(filepath)

    try:
        result = full_image_analysis(filepath)
        result['image_path'] = filename
        return render_template('index.html', **result)
    except Exception as e:
        return render_template('index.html', error=str(e))

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

if __name__ == '__main__':
    if not os.path.exists('uploads'):
        os.makedirs('uploads')
    app.run(debug=True)