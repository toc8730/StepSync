from __future__ import annotations
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import (
    JWTManager, create_access_token, jwt_required, get_jwt_identity
)
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import timedelta
import re
import json
import os
import secrets
import string
import requests

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

GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
GROQ_MODEL = os.environ.get("GROQ_MODEL", "llama-3.1-8b-instant")

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

_AI_KEYWORD_STEPS = {
    "homework": [
        "Gather notebooks and assignment list",
        "Work through each subject with focus blocks",
        "Review answers and pack everything away",
    ],
    "exercise": [
        "Warm up and stretch",
        "Complete the main workout",
        "Cool down and hydrate",
    ],
    "chores": [
        "Collect supplies for the chore",
        "Work through each area methodically",
        "Tidy up and put supplies back",
    ],
    "breakfast": [
        "Set the table and gather ingredients",
        "Prepare and eat breakfast",
        "Clear dishes and wipe counters",
    ],
    "dinner": [
        "Prep ingredients and cookware",
        "Cook and plate the meal",
        "Clean the kitchen and store leftovers",
    ],
    "study": [
        "Review class notes or slides",
        "Work through practice problems",
        "Summarize what was learned",
    ],
}

_TIME_RE = re.compile(
    r'(?P<hour>1[0-2]|0?[1-9])(?::(?P<minute>[0-5][0-9]))?\s*(?P<period>a\.?m\.?|p\.?m\.?|am|pm)',
    re.IGNORECASE,
)

_AI_SYSTEM_INSTRUCTION = (
    "You are a helpful family scheduling assistant. "
    "Given the user's request, produce ONLY valid JSON matching this schema:\n"
    '{"tasks":[{"title":string,"steps":string[],"startTime":string,"endTime":string,"period":"AM"|"PM"}]}.\n'
    "Use concise task titles (<=60 chars) and 1-6 actionable steps each. "
    "Return 3-8 tasks in chronological order, using 12-hour times like \"7:30\". "
    "Do not include any commentary outside the JSON."
)

def _extract_text_from_gemini(payload: dict) -> str:
    candidates = payload.get("candidates") or []
    for cand in candidates:
        content = cand.get("content") or {}
        parts = content.get("parts") or []
        for part in parts:
            text = part.get("text")
            if isinstance(text, str) and text.strip():
                return text.strip()
    raise RuntimeError("Gemini response did not contain text content.")

def _strip_code_fence(text: str) -> str:
    trimmed = text.strip()
    if trimmed.startswith("```"):
        trimmed = re.sub(r"^```(?:json)?", "", trimmed, flags=re.IGNORECASE)
        if trimmed.endswith("```"):
            trimmed = trimmed[:-3]
    return trimmed.strip()

def _sanitize_model_tasks(raw) -> list[dict]:
    items = []
    if isinstance(raw, dict):
        if isinstance(raw.get("tasks"), list):
            items = raw["tasks"]
        elif isinstance(raw.get("schedule"), list):
            items = raw["schedule"]
    elif isinstance(raw, list):
        items = raw

    tasks: list[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title", "")).strip()
        if not title:
            continue
        steps = item.get("steps")
        if isinstance(steps, list):
            steps = [
                str(step).strip()
                for step in steps
                if isinstance(step, (str, int, float)) and str(step).strip()
            ]
        else:
            steps = []

        start = str(item.get("startTime", "")).strip() or None
        end = str(item.get("endTime", "")).strip() or None
        period = str(item.get("period", "")).strip().upper()
        if period not in ("AM", "PM"):
            period = None

        tasks.append({
            "title": title[:60],
            "steps": steps,
            "startTime": start,
            "endTime": end,
            "period": period,
            "hidden": bool(item.get("hidden", False)),
            "completed": bool(item.get("completed", False)),
        })
    return tasks

def _call_groq_for_tasks(prompt: str) -> list[dict]:
    if not GROQ_API_KEY:
        raise RuntimeError("GROQ_API_KEY is not set on the Flask server.")

    url = "https://api.groq.com/openai/v1/chat/completions"
    body = {
        "model": GROQ_MODEL,
        "messages": [
            {"role": "system", "content": _AI_SYSTEM_INSTRUCTION},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.4,
        "max_tokens": 800,
    }

    response = requests.post(
        url,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {GROQ_API_KEY}",
        },
        json=body,
        timeout=30,
    )
    if response.status_code != 200:
        try:
            detail = response.json()
        except Exception:
            detail = response.text
        raise RuntimeError(f"Groq HTTP {response.status_code}: {detail}")

    payload = response.json()
    choices = payload.get("choices") or []
    if not choices:
        raise RuntimeError("Groq response contained no choices.")
    content = choices[0].get("message", {}).get("content", "")
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("Groq response did not contain message content.")

    text = _strip_code_fence(content)
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Groq returned invalid JSON: {exc}") from exc

    tasks = _sanitize_model_tasks(parsed)
    if not tasks:
        raise RuntimeError("Groq response did not contain any tasks.")
    return tasks

def _ai_chunks(prompt: str) -> list[str]:
    cleaned = prompt.replace(' - ', '. ')
    raw_parts = re.split(r'[.\n;]+', cleaned)
    parts: list[str] = []
    for fragment in raw_parts:
        fragment = fragment.strip(' ,')
        if fragment:
            parts.append(fragment)
    return parts

def _starting_clock(prompt: str) -> tuple[int, int]:
    lower = prompt.lower()
    if "evening" in lower or "night" in lower:
        return 18, 0
    if "afternoon" in lower or "after school" in lower:
        return 13, 0
    if "morning" in lower or "before school" in lower or "wake" in lower:
        return 7, 0
    return 8, 0

def _format_time(hour24: int, minute: int) -> tuple[str, str]:
    period = 'PM' if hour24 >= 12 else 'AM'
    hour12 = hour24 % 12
    if hour12 == 0:
        hour12 = 12
    return f"{hour12}:{minute:02d}", period

def _advance_clock(hour24: int, minute: int, delta_minutes: int) -> tuple[int, int]:
    total = hour24 * 60 + minute + delta_minutes
    total %= (24 * 60)
    return total // 60, total % 60

def _extract_time_from_chunk(chunk: str) -> tuple[int | None, int | None, str]:
    match = _TIME_RE.search(chunk)
    if not match:
        return None, None, chunk
    hour = int(match.group('hour'))
    minute = int(match.group('minute') or 0)
    period = match.group('period').lower()
    if period.startswith('p') and hour != 12:
        hour += 12
    if period.startswith('a') and hour == 12:
        hour = 0
    cleaned = _TIME_RE.sub('', chunk)
    cleaned = re.sub(r'\bat\b', '', cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip(' ,')
    return hour, minute, cleaned if cleaned else chunk

def _title_from_chunk(chunk: str, index: int) -> str:
    cleaned = re.sub(r'[^A-Za-z0-9 &/:-]', '', chunk).strip()
    if not cleaned:
        cleaned = f"Task {index + 1}"
    return cleaned[:60].strip().title()

def _steps_from_chunk(chunk: str, title: str) -> list[str]:
    lower = chunk.lower()
    for keyword, steps in _AI_KEYWORD_STEPS.items():
        if keyword in lower:
            return steps
    topic = title.lower()
    return [
        f"Plan what is needed for {topic}",
        f"Work through the main part of {topic}",
        f"Review progress and clean up after {topic}",
    ]

def _ai_generate_tasks(prompt: str) -> list[dict]:
    if GROQ_API_KEY:
        try:
            return _call_groq_for_tasks(prompt)
        except Exception as exc:
            app.logger.warning("Groq generation failed, using heuristic fallback: %s", exc)
    else:
        app.logger.warning("GROQ_API_KEY missing; using heuristic fallback.")

    return _fallback_generate_tasks(prompt)

def _fallback_generate_tasks(prompt: str) -> list[dict]:
    parts = _ai_chunks(prompt)
    if not parts:
        parts = ["Plan the day", "Focus block", "Wrap up and reflect"]

    max_items = min(len(parts), 8)
    hour, minute = _starting_clock(prompt)
    tasks: list[dict] = []

    for idx, raw_chunk in enumerate(parts[:max_items]):
        custom_hour, custom_minute, cleaned_chunk = _extract_time_from_chunk(raw_chunk)
        if custom_hour is not None:
            hour, minute = custom_hour, custom_minute

        title = _title_from_chunk(cleaned_chunk, idx)
        steps = _steps_from_chunk(cleaned_chunk, title)
        start_str, period = _format_time(hour, minute)
        end_hour, end_minute = _advance_clock(hour, minute, 45)
        end_str, _ = _format_time(end_hour, end_minute)

        tasks.append({
            "title": title,
            "steps": steps,
            "startTime": start_str,
            "endTime": end_str,
            "period": period,
            "hidden": False,
            "completed": False,
        })

        hour, minute = end_hour, end_minute

    return tasks

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

# get the profile of the head of the family (used for saving blocks from the parent to the child account)
@app.route("/profile/family", methods=["GET"])
@jwt_required()
def family_get():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = Family.query.filter_by(family_id=user.family_id).first()
    if not family:
        return jsonify(_safe_profile_dict(user.profile_data)), 200 # if no family, load user who queried as a failsafe
    family_head = User.query.filter_by(username=family.creator_username).first()
    if not family_head:
        return jsonify({"error": "Family head not found"}), 404
    return jsonify(_safe_profile_dict(family_head.profile_data)), 200
    

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

@app.route("/profile/family/block/edit", methods=["POST"])
@jwt_required()
def family_block_edit():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    if not user.family_id:
        return jsonify({"error": "User not linked to a family"}), 400

    family = Family.query.filter_by(family_id=user.family_id).first()
    if not family:
        return jsonify({"error": "Family not found"}), 404

    parent = User.query.filter_by(username=family.creator_username).first()
    if not parent:
        return jsonify({"error": "Family head not found"}), 404

    payload = request.get_json(silent=True) or {}
    old_block = payload.get("old_block")
    new_block = payload.get("new_block")
    if old_block is None or new_block is None:
        return jsonify({"error": "Missing 'old_block' or 'new_block'"}), 400

    prof = _safe_profile_dict(parent.profile_data)
    idx = _first_match_index(prof["schedule_blocks"], old_block)
    if idx < 0:
        return jsonify({"error": "Old block not found"}), 404

    prof["schedule_blocks"][idx] = _norm_block(new_block)
    parent.profile_data = json.dumps(prof)
    db.session.commit()
    return jsonify({"message": "Family block edit successful"}), 200

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

# -------------------- AI Task Generation --------------------
@app.route("/ai/tasks", methods=["POST"])
@jwt_required()
def ai_tasks():
    payload = request.get_json(silent=True) or {}
    prompt = (payload.get("prompt") or "").strip()
    if not prompt:
        return jsonify({"error": "Prompt is required."}), 400

    tasks = _ai_generate_tasks(prompt)
    return jsonify({
        "prompt": prompt,
        "tasks": tasks,
        "count": len(tasks),
    }), 200

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
