from flask import Blueprint, render_template, request, redirect, url_for, session
from werkzeug.security import generate_password_hash, check_password_hash
from pymongo import MongoClient
from bson.objectid import ObjectId

auth_bp = Blueprint('auth', __name__)

# MongoDB setup
client = MongoClient("mongodb://localhost:27017")
db = client.food_db
users_collection = db.users

@auth_bp.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        username = request.form['username']
        email = request.form['email']
        password = request.form['password']

        if users_collection.find_one({'email': email}):
            return render_template('signup.html', error='Email already exists.')

        hashed_password = generate_password_hash(password)
        user_id = users_collection.insert_one({
            'username': username,
            'email': email,
            'password': hashed_password
        }).inserted_id

        session['user_id'] = str(user_id)
        return redirect(url_for('profile'))

    return render_template('signup.html')

@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        email = request.form['email']
        password = request.form['password']

        user = users_collection.find_one({'email': email})
        if user and check_password_hash(user['password'], password):
            session['user_id'] = str(user['_id'])
            return redirect(url_for('profile'))
        else:
            return render_template('login.html', error='Invalid email or password.')

    return render_template('login.html')

@auth_bp.route('/logout')
def logout():
    session.pop('user_id', None)
    return redirect(url_for('auth.login'))
