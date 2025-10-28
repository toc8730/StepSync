from __future__ import annotations
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import (
    JWTManager, create_access_token, jwt_required, get_jwt_identity
)
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import timedelta
import json
import os
import secrets
import string

app = Flask(__name__)
CORS(app)

# -------------------- Config --------------------
BASEDIR = os.path.abspath(os.path.dirname(__file__))
DB_URI = "sqlite:///users.db"  # lives next to where you run the app
app.config["SQLALCHEMY_DATABASE_URI"] = DB_URI
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# JWT
app.config["JWT_SECRET_KEY"] = os.environ.get("JWT_SECRET_KEY", "super-secret-key")
app.config["JWT_ACCESS_TOKEN_EXPIRES"] = timedelta(days=7)

db = SQLAlchemy(app)
jwt = JWTManager(app)

# -------------------- Models --------------------
class User(db.Model):
    __tablename__ = "users"
    id           = db.Column(db.Integer, primary_key=True)
    username     = db.Column(db.String(100), unique=True, nullable=False)
    password     = db.Column(db.String(200), nullable=False)  # hashed
    account_type = db.Column(db.Text, nullable=False)         # "parent" | "child"
    profile_data = db.Column(db.Text)                         # JSON string (dict)
    family_id    = db.Column(db.String(20), nullable=True)    # FK-ish to Family.family_id

class Family(db.Model):
    __tablename__ = "families"
    id               = db.Column(db.Integer, primary_key=True)
    family_id        = db.Column(db.String(20), unique=True, nullable=False)  # public identifier
    name             = db.Column(db.String(100), nullable=False)
    password         = db.Column(db.String(200), nullable=False)              # hashed
    creator_username = db.Column(db.String(100), nullable=False)              # who created it

with app.app_context():
    db.create_all()

# -------------------- Helpers --------------------
def _safe_profile_dict(text_json: str | None) -> dict:
    """Return a dict with at least {'schedule_blocks': []}."""
    if not text_json:
        return {"schedule_blocks": []}
    try:
        data = json.loads(text_json)
        if not isinstance(data, dict):
            return {"schedule_blocks": []}
        if "schedule_blocks" not in data or not isinstance(data.get("schedule_blocks"), list):
            data["schedule_blocks"] = []
        return data
    except Exception:
        return {"schedule_blocks": []}

def _rand_family_id(n: int = 10) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))

# -------------------- Auth --------------------
@app.route("/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    # Accept multiple keys for compatibility with your client
    raw_role = (data.get("account_type") or data.get("type") or data.get("role") or "parent").strip().lower()
    account_type = "child" if raw_role == "child" else "parent"

    if not username:
        return jsonify({"error": "Username required"}), 400
    if not (8 <= len(password) <= 20):
        return jsonify({"error": "Password must be 8–20 characters"}), 400
    if User.query.filter_by(username=username).first():
        return jsonify({"error": "Username already exists"}), 400

    hashed_pw = generate_password_hash(password)
    # Always start with normalized profile payload
    default_profile_data = json.dumps({"schedule_blocks": []})
    new_user = User(
        username=username,
        password=hashed_pw,
        account_type=account_type,
        profile_data=default_profile_data
    )
    db.session.add(new_user)
    db.session.commit()
    return jsonify({"message": "User registered successfully", "username": username, "role": account_type}), 200

@app.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    user = User.query.filter_by(username=username).first()
    if not user or not check_password_hash(user.password, password):
        return jsonify({"error": "Invalid username or password"}), 401

    token = create_access_token(identity=user.username)
    return jsonify({
        "message": "Login successful",
        "token": token,
        "username": user.username,
        "role": user.account_type
    }), 200

# -------------------- Profile / Me --------------------
@app.route("/profile", methods=["GET"])
@jwt_required()
def profile_get():
    """Return schedule data as proper JSON {schedule_blocks: [...]}."""
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404
    return jsonify(_safe_profile_dict(user.profile_data)), 200

@app.route("/me", methods=["GET"])
@jwt_required()
def me():
    """Return user + family info for your Profile tile."""
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    fam_entry = None
    if user.family_id:
        fam = Family.query.filter_by(family_id=user.family_id).first()
        if fam:
            role = "owner" if fam.creator_username == user.username else "member"
            fam_entry = {
                "family": {
                    "name": fam.name,
                    "identifier": fam.family_id
                },
                "role": role
            }

    return jsonify({
        "user": {"username": user.username, "role": user.account_type},
        "families": [fam_entry] if fam_entry else []
    }), 200

# -------------------- Schedule Blocks --------------------
@app.route("/profile/block/add", methods=["POST"])
@jwt_required()
def block_add():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    payload = request.get_json(silent=True) or {}
    if "block" not in payload:
        return jsonify({"error": "Missing 'block'"}), 400

    prof = _safe_profile_dict(user.profile_data)
    prof["schedule_blocks"].append(payload["block"])
    user.profile_data = json.dumps(prof)
    db.session.commit()
    return jsonify({"message": "Block add successful"}), 200

@app.route("/profile/block/edit", methods=["POST"])
@jwt_required()
def block_edit():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    payload = request.get_json(silent=True) or {}
    old_block = payload.get("old_block")
    new_block = payload.get("new_block")
    if old_block is None or new_block is None:
        return jsonify({"error": "Missing 'old_block' or 'new_block'"}), 400

    prof = _safe_profile_dict(user.profile_data)
    try:
        idx = prof["schedule_blocks"].index(old_block)
        prof["schedule_blocks"][idx] = new_block
    except ValueError:
        return jsonify({"error": "Old block not found"}), 404

    user.profile_data = json.dumps(prof)
    db.session.commit()
    return jsonify({"message": "Block edit successful"}), 200

# -------------------- Families --------------------
@app.route("/family/create", methods=["POST"])
@jwt_required()
def create_family():
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    password = data.get("password") or ""
    # client may provide a family_id, otherwise generate one
    family_id = (data.get("family_id") or "").strip() or _rand_family_id(10)

    if not name:
        return jsonify({"error": "Name required"}), 400
    if not (8 <= len(password) <= 20):
        return jsonify({"error": "Password must be 8–20 characters"}), 400
    if Family.query.filter_by(family_id=family_id).first():
        return jsonify({"error": "Family ID already exists"}), 400

    creator = get_jwt_identity()
    hashed_pw = generate_password_hash(password)

    fam = Family(family_id=family_id, name=name, password=hashed_pw, creator_username=creator)
    db.session.add(fam)

    # Optionally assign creator
    user = User.query.filter_by(username=creator).first()
    if user:
        user.family_id = family_id

    db.session.commit()
    return jsonify({"message": "Family created", "family_id": fam.family_id}), 200

@app.route("/family/join", methods=["POST"])
@jwt_required()
def join_family():
    data = request.get_json(silent=True) or {}
    family_id = (data.get("family_id") or "").strip()
    password = data.get("password") or ""

    fam = Family.query.filter_by(family_id=family_id).first()
    if not fam or not check_password_hash(fam.password, password):
        return jsonify({"error": "Invalid family ID or password"}), 401

    user = User.query.filter_by(username=get_jwt_identity()).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    user.family_id = family_id
    db.session.commit()
    return jsonify({"message": "Joined family successfully"}), 200

# -------------------- Health --------------------
@app.route("/")
def health():
    return jsonify({"ok": True})

if __name__ == "__main__":
    # Run on 127.0.0.1:5000 for your Flutter client
    app.run(host="127.0.0.1", port=5000, debug=True)