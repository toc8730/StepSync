from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
import json

app = Flask(__name__)
CORS(app)

# Database config
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///users.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['JWT_SECRET_KEY'] = 'super-secret-key'  # 🔒 Change this in production!

db = SQLAlchemy(app)
jwt = JWTManager(app)


# Database model
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(100), unique=True, nullable=False)
    password = db.Column(db.String(200), nullable=False)
    profile_data = db.Column(db.Text) # text is just string w/o chr limit

with app.app_context():
    db.create_all()

# Register route
@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    username = data['username']
    password = data['password']

    default_profile_data = json.JSONEncoder().encode({'schedule_blocks': ''}) # change this later

    # Check if user already exists
    if User.query.filter_by(username=username).first():
        return jsonify({'error': 'Username already exists'}), 400

    # Hash the password
    hashed_pw = generate_password_hash(password)
    new_user = User(username=username, password=hashed_pw, profile_data=default_profile_data)
    db.session.add(new_user)
    db.session.commit()

    return jsonify({'message': 'User registered successfully'})

# Login route
@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data['username']
    password = data['password']

    user = User.query.filter_by(username=username).first()
    
    if user and check_password_hash(user.password, password):
        # Generate JWT token
        token = create_access_token(identity=user.username)
        return jsonify({'message': 'Login successful', 'token': token})
    else:
        return jsonify({'error': 'Invalid username or password'}), 401
    
# Protected route (requires JWT)
# Gets profile data (just schedule data for now)
@app.route('/profile', methods=['GET'])
@jwt_required()
def profile_get():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    return user.profile_data

# Appends schedule data with new block
@app.route ('/profile/block', methods=['POST'])
@jwt_required()
def profile_post():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    profile_data = json.JSONDecoder().decode(user.profile_data)
    
    # null-checking blocks (if this is the first block the user has added)
    if not profile_data.get('schedule_blocks'):
        profile_data['schedule_blocks'] = [ request.get_json()['block'] ]
        
    else:
        profile_data['schedule_blocks'].append(request.get_json()['block'])

    # save the change to database
    user.profile_data = json.JSONEncoder().encode(profile_data)
    db.session.commit()
    return jsonify({'message': 'Block post successful'})
    

if __name__ == '__main__':
    app.run(debug=True)