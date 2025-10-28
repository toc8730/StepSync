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
DB_URI = "sqlite:///users.db"
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
    profile_data = db.Column(db.Text)                         # JSON string
    family_id    = db.Column(db.String(20), nullable=True)

class Family(db.Model):
    __tablename__ = "families"
    id               = db.Column(db.Integer, primary_key=True)
    family_id        = db.Column(db.String(20), unique=True, nullable=False)
    name             = db.Column(db.String(100), nullable=False)
    password         = db.Column(db.String(200), nullable=False)
    creator_username = db.Column(db.String(100), nullable=False)

with app.app_context():
    db.create_all()

# -------------------- Helpers --------------------
def _safe_profile_dict(text_json: str | None) -> dict:
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

def _norm_block(b: dict | None) -> dict:
    """Normalize a block dict so matching is tolerant of missing keys/whitespace/case."""
    b = b or {}
    def s(x): return (x or "").strip()
    def upper2(x): 
        x = (x or "").strip().upper()
        return x if x in ("AM", "PM") else ""
    steps = b.get("steps") or []
    if isinstance(steps, list):
        steps = [s(x) for x in steps if isinstance(x, str)]
    else:
        steps = []
    return {
        "title": s(b.get("title")),
        "startTime": s(b.get("startTime")),
        "endTime": s(b.get("endTime")),
        "period": upper2(b.get("period")),
        "steps": steps,
        "hidden": bool(b.get("hidden", False)),
        "completed": bool(b.get("completed", False)),
    }

def _first_match_index(blocks: list, cand: dict) -> int:
    """Find index of matching block with several fallbacks."""
    C = _norm_block(cand)
    # 1) strict normalized equality
    for i, raw in enumerate(blocks):
        if not isinstance(raw, dict): 
            continue
        if _norm_block(raw) == C:
            return i
    # 2) relaxed: title + start/end/period (ignore steps/flags)
    for i, raw in enumerate(blocks):
        if not isinstance(raw, dict): 
            continue
        R = _norm_block(raw)
        if (R["title"] == C["title"]
            and R["startTime"] == C["startTime"]
            and R["endTime"] == C["endTime"]
            and R["period"] == C["period"]):
            return i
    # 3) title-only fallback (use first)
    for i, raw in enumerate(blocks):
        if not isinstance(raw, dict): 
            continue
        R = _norm_block(raw)
        if R["title"] == C["title"] and R["title"]:
            return i
    return -1

# -------------------- Auth --------------------
@app.route("/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    raw_role = (data.get("account_type") or data.get("type") or data.get("role") or "parent").strip().lower()
    account_type = "child" if raw_role == "child" else "parent"

    if not username:
        return jsonify({"error": "Username required"}), 400
    if not (8 <= len(password) <= 20):
        return jsonify({"error": "Password must be 8–20 characters"}), 400
    if User.query.filter_by(username=username).first():
        return jsonify({"error": "Username already exists"}), 400

    hashed_pw = generate_password_hash(password)
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
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404
    return jsonify(_safe_profile_dict(user.profile_data)), 200

@app.route("/me", methods=["GET"])
@jwt_required()
def me():
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
                "family": {"name": fam.name, "identifier": fam.family_id},
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
    if "block" not in payload or not isinstance(payload["block"], dict):
        return jsonify({"error": "Missing 'block'"}), 400

    prof = _safe_profile_dict(user.profile_data)
    # normalize before storing so matching is consistent later
    prof["schedule_blocks"].append(_norm_block(payload["block"]))
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
    idx = _first_match_index(prof["schedule_blocks"], old_block)
    if idx < 0:
        return jsonify({"error": "Old block not found"}), 404

    prof["schedule_blocks"][idx] = _norm_block(new_block)
    user.profile_data = json.dumps(prof)
    db.session.commit()
    return jsonify({"message": "Block edit successful"}), 200

@app.route("/profile/block/delete", methods=["POST"])
@jwt_required()
def block_delete():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    # Restrict children
    if user.account_type.lower() == "child":
        return jsonify({"error": "Children cannot delete tasks"}), 403

    payload = request.get_json(silent=True) or {}
    prof = _safe_profile_dict(user.profile_data)
    blocks = prof["schedule_blocks"]

    # delete by index (if provided)
    if isinstance(payload.get("index"), int):
        i = payload["index"]
        if 0 <= i < len(blocks):
            removed = blocks.pop(i)
            user.profile_data = json.dumps(prof)
            db.session.commit()
            return jsonify({"message": "Deleted", "deleted": removed}), 200
        return jsonify({"error": "Index out of range"}), 400

    # delete by block (robust matching)
    cand = payload.get("block")
    if isinstance(cand, dict):
        idx = _first_match_index(blocks, cand)
        if idx >= 0:
            removed = blocks.pop(idx)
            user.profile_data = json.dumps(prof)
            db.session.commit()
            return jsonify({"message": "Deleted", "deleted": removed}), 200
        return jsonify({"error": "Block not found"}), 404

    return jsonify({"error": "Provide 'index' or 'block'"}), 400

# -------------------- Families --------------------
@app.route("/family/create", methods=["POST"])
@jwt_required()
def create_family():
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    password = data.get("password") or ""
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
    app.run(host="127.0.0.1", port=5000, debug=True)