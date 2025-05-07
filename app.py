from flask import Flask, render_template, request, redirect, url_for, flash, session
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from cryptography.fernet import Fernet
import os
import base64
from datetime import timedelta
import secrets

# Initialize Flask app
app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY') or secrets.token_hex(16)
app.permanent_session_lifetime = timedelta(minutes=30)  # Session timeout after 30 minutes

# Configure database
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///password_manager.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Generate or load encryption key
def get_encryption_key():
    key_file = 'encryption_key.key'
    if os.path.exists(key_file):
        with open(key_file, 'rb') as file:
            key = file.read()
    else:
        key = Fernet.generate_key()
        with open(key_file, 'wb') as file:
            file.write(key)
    return key

# Create encryption object
key = get_encryption_key()
cipher = Fernet(key)

# Database models
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(128), nullable=False)
    
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

class PasswordEntry(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    service = db.Column(db.String(100), nullable=False)
    username = db.Column(db.String(100), nullable=False)
    encrypted_password = db.Column(db.LargeBinary, nullable=False)
    url = db.Column(db.String(200))
    notes = db.Column(db.Text)
    
    def set_password(self, password):
        self.encrypted_password = cipher.encrypt(password.encode())
    
    def get_password(self):
        return cipher.decrypt(self.encrypted_password).decode()

# Ensure database exists
with app.app_context():
    db.create_all()

# Authentication decorator
def login_required(view_func):
    def wrapped_view(*args, **kwargs):
        if 'user_id' not in session:
            flash('Please log in to access this page', 'error')
            return redirect(url_for('login'))
        return view_func(*args, **kwargs)
    wrapped_view.__name__ = view_func.__name__
    return wrapped_view

# Routes
@app.route('/')
def index():
    if 'user_id' in session:
        return redirect(url_for('dashboard'))
    return render_template('index.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        confirm_password = request.form['confirm_password']
        
        # Validation
        if not username or not password:
            flash('Username and password are required', 'error')
            return redirect(url_for('register'))
        
        if password != confirm_password:
            flash('Passwords do not match', 'error')
            return redirect(url_for('register'))
        
        # Check if user already exists
        existing_user = User.query.filter_by(username=username).first()
        if existing_user:
            flash('Username already exists', 'error')
            return redirect(url_for('register'))
        
        # Create new user
        new_user = User(username=username)
        new_user.set_password(password)
        
        db.session.add(new_user)
        db.session.commit()
        
        flash('Registration successful! Please log in.', 'success')
        return redirect(url_for('login'))
    
    return render_template('register.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        
        user = User.query.filter_by(username=username).first()
        
        if user and user.check_password(password):
            session.permanent = True
            session['user_id'] = user.id
            session['username'] = user.username
            flash('Logged in successfully!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('Invalid username or password', 'error')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.pop('user_id', None)
    session.pop('username', None)
    flash('Logged out successfully', 'success')
    return redirect(url_for('index'))

@app.route('/dashboard')
@login_required
def dashboard():
    user_id = session['user_id']
    passwords = PasswordEntry.query.filter_by(user_id=user_id).all()
    return render_template('dashboard.html', passwords=passwords)

@app.route('/add', methods=['GET', 'POST'])
@login_required
def add_password():
    if request.method == 'POST':
        service = request.form['service']
        username = request.form['username']
        password = request.form['password']
        url = request.form['url']
        notes = request.form['notes']
        
        # Validation
        if not service or not username or not password:
            flash('Service, username, and password are required', 'error')
            return redirect(url_for('add_password'))
        
        # Create new password entry
        new_entry = PasswordEntry(
            user_id=session['user_id'],
            service=service,
            username=username,
            url=url,
            notes=notes
        )
        new_entry.set_password(password)
        
        db.session.add(new_entry)
        db.session.commit()
        
        flash('Password added successfully!', 'success')
        return redirect(url_for('dashboard'))
    
    return render_template('add_password.html')

@app.route('/edit/<int:id>', methods=['GET', 'POST'])
@login_required
def edit_password(id):
    entry = PasswordEntry.query.get_or_404(id)
    
    # Ensure user owns this password entry
    if entry.user_id != session['user_id']:
        flash('Access denied', 'error')
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        entry.service = request.form['service']
        entry.username = request.form['username']
        entry.url = request.form['url']
        entry.notes = request.form['notes']
        
        # Update password if provided
        if request.form['password']:
            entry.set_password(request.form['password'])
        
        db.session.commit()
        flash('Password updated successfully!', 'success')
        return redirect(url_for('dashboard'))
    
    return render_template('edit_password.html', entry=entry, password=entry.get_password())

@app.route('/delete/<int:id>')
@login_required
def delete_password(id):
    entry = PasswordEntry.query.get_or_404(id)
    
    # Ensure user owns this password entry
    if entry.user_id != session['user_id']:
        flash('Access denied', 'error')
        return redirect(url_for('dashboard'))
    
    db.session.delete(entry)
    db.session.commit()
    
    flash('Password deleted successfully!', 'success')
    return redirect(url_for('dashboard'))

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
