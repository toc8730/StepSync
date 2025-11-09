from __future__ import annotations
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import (
    JWTManager, create_access_token, jwt_required, get_jwt_identity
)
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime, timedelta
from sqlalchemy import inspect, text
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

def _load_google_client_ids() -> set[str]:
    """
    Collect all OAuth client IDs we trust for Google sign-in.
    This lets the backend accept tokens minted for any of the runtime-configured IDs.
    """
    raw = os.environ.get("GOOGLE_CLIENT_IDS", "")
    ids = {cid.strip() for cid in raw.split(",") if cid.strip()}
    for key in ("GOOGLE_WEB_CLIENT_ID", "GOOGLE_ANDROID_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID"):
        val = (os.environ.get(key) or "").strip()
        if val:
            ids.add(val)
    return ids

GOOGLE_CLIENT_IDS = _load_google_client_ids()

# -------------------- Models --------------------
class User(db.Model):
    __tablename__ = "users"
    id           = db.Column(db.Integer, primary_key=True)
    username     = db.Column(db.String(100), unique=True, nullable=False)
    email        = db.Column(db.String(200), unique=True, nullable=True)
    display_name = db.Column(db.String(100), nullable=True)
    password     = db.Column(db.String(200), nullable=False)  # hashed
    auth_provider = db.Column(db.String(20), nullable=False, default="password")  # "password" | "google"
    account_type = db.Column(db.Text, nullable=False)         # "parent" | "child"
    profile_data = db.Column(db.Text)                         # JSON string
    family_id    = db.Column(db.String(20), nullable=True)
    family_joined_at = db.Column(db.DateTime, nullable=True)

class Family(db.Model):
    __tablename__ = "families"
    id               = db.Column(db.Integer, primary_key=True)
    family_id        = db.Column(db.String(20), unique=True, nullable=False)
    name             = db.Column(db.String(100), nullable=False)
    password         = db.Column(db.String(200), nullable=False)
    creator_username = db.Column(db.String(100), nullable=False)

class FamilyLeaveRequest(db.Model):
    __tablename__ = "family_leave_requests"
    id             = db.Column(db.Integer, primary_key=True)
    family_id      = db.Column(db.String(20), db.ForeignKey("families.family_id"), nullable=False)
    child_username = db.Column(db.String(100), nullable=False)
    status         = db.Column(db.String(20), nullable=False, default="pending")  # pending | resolved
    created_at     = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

class FamilyInvite(db.Model):
    __tablename__ = "family_invites"
    id             = db.Column(db.Integer, primary_key=True)
    family_id      = db.Column(db.String(20), db.ForeignKey("families.family_id"), nullable=False)
    child_username = db.Column(db.String(100), nullable=False)
    status         = db.Column(db.String(20), nullable=False, default="pending")  # pending | accepted | rejected
    created_at     = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

with app.app_context():
    db.create_all()
    _insp = inspect(db.engine)
    user_columns = {col["name"] for col in _insp.get_columns("users")}
    if "email" not in user_columns:
        with db.engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN email TEXT"))
    if "auth_provider" not in user_columns:
        with db.engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN auth_provider TEXT DEFAULT 'password'"))
        with db.engine.begin() as conn:
            conn.execute(text("UPDATE users SET auth_provider = 'password' WHERE auth_provider IS NULL OR TRIM(auth_provider) = ''"))
    if "family_joined_at" not in user_columns:
        with db.engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN family_joined_at TIMESTAMP"))
        with db.engine.begin() as conn:
            conn.execute(text("UPDATE users SET family_joined_at = CURRENT_TIMESTAMP WHERE family_id IS NOT NULL AND family_joined_at IS NULL"))
    if "display_name" not in user_columns:
        with db.engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN display_name TEXT"))
        with db.engine.begin() as conn:
            conn.execute(text("UPDATE users SET display_name = username WHERE display_name IS NULL OR TRIM(display_name) = ''"))
    existing_tables = set(_insp.get_table_names())
    if "family_invites" not in existing_tables:
        FamilyInvite.__table__.create(db.engine, checkfirst=True)

# -------------------- Helpers --------------------
def _default_preferences() -> dict:
    return {"theme": "system"}

def _safe_profile_dict(text_json: str | None) -> dict:
    if not text_json:
        return {"schedule_blocks": [], "preferences": _default_preferences()}
    try:
        data = json.loads(text_json)
        if not isinstance(data, dict):
            return {"schedule_blocks": [], "preferences": _default_preferences()}
        if "schedule_blocks" not in data or not isinstance(data.get("schedule_blocks"), list):
            data["schedule_blocks"] = []
        if "preferences" not in data or not isinstance(data.get("preferences"), dict):
            data["preferences"] = _default_preferences()
        else:
            prefs = data["preferences"]
            theme = (prefs.get("theme") or "").lower()
            if theme not in ("light", "dark", "system"):
                prefs["theme"] = "system"
        return data
    except Exception:
        return {"schedule_blocks": [], "preferences": _default_preferences()}

def _rand_family_id(n: int = 10) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))

def _family_for_user(user: 'User') -> 'Family | None':
    if not user.family_id:
        return None
    return Family.query.filter_by(family_id=user.family_id).first()

def _user_display_name(user: 'User | None') -> str:
    if not user:
        return ""
    name = (user.display_name or "").strip()
    if not name:
        name = (user.username or "").strip()
    return name

def _current_user_from_token() -> 'User | None':
    ident = get_jwt_identity()
    if not ident:
        return None
    return User.query.filter_by(username=ident).first()

def _schedule_owner(user: 'User') -> tuple['User', bool]:
    is_master = True
    owner = user
    if user.account_type.lower() == "parent" and user.family_id:
        family = _family_for_user(user)
        if family:
            master = User.query.filter_by(username=family.creator_username).first()
            if master:
                owner = master
                is_master = (master.username == user.username)
    return owner, is_master

def _family_children(family: 'Family') -> list['User']:
    members = User.query.filter_by(family_id=family.family_id).all()
    return [m for m in members if m.account_type.lower() == "child"]

def _family_parents(family: 'Family') -> list['User']:
    members = User.query.filter_by(family_id=family.family_id).all()
    return [m for m in members if m.account_type.lower() == "parent"]

def _clear_child_tasks(child: 'User') -> None:
    profile = _safe_profile_dict(child.profile_data)
    if profile.get("schedule_blocks"):
        profile["schedule_blocks"] = []
        child.profile_data = json.dumps(profile)

def _detach_user_from_family(user: 'User') -> None:
    user.family_id = None
    user.family_joined_at = None

def _pick_longest_tenured_parent(family: 'Family', *, exclude: str | None = None) -> 'User | None':
    parents = _family_parents(family)
    candidates = [p for p in parents if p.username != exclude]
    if not candidates:
        return None
    now = datetime.utcnow()
    candidates.sort(key=lambda u: ((u.family_joined_at or now), u.id))
    return candidates[0]

def _delete_family_and_cleanup(family: 'Family') -> None:
    members = User.query.filter_by(family_id=family.family_id).all()
    for member in members:
        if member.account_type.lower() == "child":
            _clear_child_tasks(member)
        _detach_user_from_family(member)
    FamilyLeaveRequest.query.filter_by(family_id=family.family_id).delete()
    db.session.delete(family)

def _handle_parent_leave(user: 'User', family: 'Family') -> str:
    was_master = family.creator_username == user.username
    _detach_user_from_family(user)
    message = "Left family."
    if was_master:
        replacement = _pick_longest_tenured_parent(family, exclude=user.username)
        if replacement:
            family.creator_username = replacement.username
            message = f"Transferred master role to {replacement.username}."
        else:
            _delete_family_and_cleanup(family)
            message = "Family deleted because no parents remained."
    return message

def _append_block_to_user(user: 'User', block: dict) -> None:
    prof = _safe_profile_dict(user.profile_data)
    prof["schedule_blocks"].append(dict(block))
    user.profile_data = json.dumps(prof)

def _update_block_with_tag(user: 'User', tag: str, new_block: dict) -> bool:
    tag = (tag or "").strip()
    if not tag:
        return False
    prof = _safe_profile_dict(user.profile_data)
    updated = False
    for idx, blk in enumerate(prof["schedule_blocks"]):
        if (blk.get("family_tag") or "").strip() == tag:
            prof["schedule_blocks"][idx] = dict(new_block)
            updated = True
    if updated:
        user.profile_data = json.dumps(prof)
    return updated

def _remove_family_tag_from_user(user: 'User', tag: str) -> bool:
    tag = (tag or "").strip()
    if not tag:
        return False
    prof = _safe_profile_dict(user.profile_data)
    blocks = prof["schedule_blocks"]
    new_blocks = [b for b in blocks if (b.get("family_tag") or "").strip() != tag]
    if len(new_blocks) == len(blocks):
        return False
    prof["schedule_blocks"] = new_blocks
    user.profile_data = json.dumps(prof)
    return True

def _resolve_schedule_user(user: 'User', target_child: str | None):
    target = (target_child or '').strip()
    if target:
        if user.account_type.lower() != "parent":
            raise ValueError("Only parents can assign tasks to a child")
        family = _family_for_user(user)
        if not family:
            raise ValueError("Parent is not linked to a family")
        child = User.query.filter_by(username=target).first()
        if not child or child.account_type.lower() != "child" or child.family_id != family.family_id:
            raise ValueError("Child not found in your family")
        return child
    owner, _ = _schedule_owner(user)
    return owner

def _verify_google_id_token(id_token: str) -> dict | None:
    if not id_token:
        return None
    try:
        resp = requests.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"id_token": id_token},
            timeout=8,
        )
    except requests.RequestException:
        return None
    if resp.status_code != 200:
        return None
    data = resp.json()
    aud = data.get("aud", "")
    if GOOGLE_CLIENT_IDS and aud not in GOOGLE_CLIENT_IDS:
        return None
    if data.get("email_verified") not in ("true", True, 1, "1"):
        return None
    return data

def _verify_google_access_token(access_token: str) -> dict | None:
    info = _fetch_google_token_info(access_token)
    if not info:
        return None
    aud = info.get("aud", "")
    if GOOGLE_CLIENT_IDS and aud not in GOOGLE_CLIENT_IDS:
        return None
    if info.get("email_verified") not in ("true", True, 1, "1"):
        profile = _fetch_google_userinfo(access_token)
    else:
        profile = info
    if not profile:
        return None
    email = (profile.get("email") or "").strip().lower()
    if not email:
        fallback = _fetch_google_userinfo(access_token)
        if fallback:
            email = (fallback.get("email") or "").strip().lower()
            profile.update(fallback)
    if not email:
        return None
    profile["email"] = email
    return profile

def _fetch_google_token_info(access_token: str) -> dict | None:
    if not access_token:
        return None
    try:
        resp = requests.get(
            "https://oauth2.googleapis.com/tokeninfo",
            params={"access_token": access_token},
            timeout=8,
        )
    except requests.RequestException:
        return None
    if resp.status_code != 200:
        return None
    try:
        return resp.json()
    except ValueError:
        return None

def _fetch_google_userinfo(access_token: str) -> dict | None:
    if not access_token:
        return None
    try:
        resp = requests.get(
            "https://www.googleapis.com/oauth2/v3/userinfo",
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=8,
        )
    except requests.RequestException:
        return None
    if resp.status_code != 200:
        return None
    try:
        return resp.json()
    except ValueError:
        return None

def _clean_display_name(*candidates: str) -> str:
    for raw in candidates:
        name = (raw or "").strip()
        if not name:
            continue
        name = re.sub(r"\s+", " ", name)
        if name:
            return name[:80]
    return ""

def _unique_username(base: str, *, exclude_user: 'User | None' = None) -> str:
    base = base or "user"
    base = base.strip()
    candidate = base
    counter = 2
    while True:
        query = User.query.filter_by(username=candidate)
        if exclude_user is not None:
            query = query.filter(User.id != exclude_user.id)
        if not query.first():
            return candidate
        candidate = f"{base} {counter}"
        counter += 1

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
        "family_tag": s(b.get("family_tag")),
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

def _split_time_and_period(value: str | None) -> tuple[str | None, str | None]:
    text = (value or "").strip()
    if not text:
        return None, None
    match = _TIME_RE.search(text)
    if not match:
        return None, None
    hour = int(match.group('hour'))
    minute = int(match.group('minute') or 0)
    period_raw = match.group('period') or ""
    period = 'AM' if period_raw.lower().startswith('a') else 'PM'
    hour12 = hour % 12
    if hour12 == 0:
        hour12 = 12
    return f"{hour12}:{minute:02d}", period

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

        start_raw = str(item.get("startTime", "")).strip()
        end_raw = str(item.get("endTime", "")).strip()
        start = start_raw or None
        end = end_raw or None
        period = str(item.get("period", "")).strip().upper()
        if period not in ("AM", "PM"):
            period = None
        norm_start, start_period = _split_time_and_period(start_raw)
        norm_end, end_period = _split_time_and_period(end_raw)
        if norm_start:
            start = norm_start
        if norm_end:
            end = norm_end
        if not period and start_period:
            period = start_period
        if not period and end_period:
            period = end_period

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
    display_name = (data.get("display_name") or data.get("displayName") or "").strip()
    password = data.get("password") or ""
    raw_role = (data.get("account_type") or data.get("type") or data.get("role") or "parent").strip().lower()
    account_type = "child" if raw_role == "child" else "parent"

    if not username:
        return jsonify({"error": "Username required"}), 400
    if not display_name:
        return jsonify({"error": "Display name required"}), 400
    if len(display_name) > 100:
        return jsonify({"error": "Display name must be at most 100 characters"}), 400
    if not (8 <= len(password) <= 20):
        return jsonify({"error": "Password must be 8–20 characters"}), 400
    if User.query.filter_by(username=username).first():
        return jsonify({"error": "Username already exists"}), 400

    hashed_pw = generate_password_hash(password)
    default_profile_data = json.dumps({"schedule_blocks": [], "preferences": _default_preferences()})
    new_user = User(
        username=username,
        display_name=display_name,
        password=hashed_pw,
        auth_provider="password",
        account_type=account_type,
        profile_data=default_profile_data
    )
    db.session.add(new_user)
    db.session.commit()
    return jsonify({
        "message": "User registered successfully",
        "username": username,
        "display_name": display_name,
        "role": account_type
    }), 200

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
        "display_name": _user_display_name(user),
        "role": user.account_type
    }), 200

@app.route("/login/google", methods=["POST"])
def login_google():
    data = request.get_json(silent=True) or {}
    id_token = (data.get("id_token") or "").strip()
    access_token = (data.get("access_token") or "").strip()
    preferred_raw = (data.get("preferred_role") or "").strip().lower()
    if preferred_raw in ("parent", "child"):
        preferred_role: str | None = preferred_raw
    else:
        preferred_role = None

    if not id_token and not access_token:
        return jsonify({"error": "id_token or access_token required"}), 400

    info = _verify_google_id_token(id_token) if id_token else None
    if not info and access_token:
        info = _verify_google_access_token(access_token)
    if not info:
        return jsonify({"error": "Invalid Google token"}), 401

    email = (info.get("email") or "").strip().lower()
    if not email:
        return jsonify({"error": "Google account missing email"}), 400

    display_name = _clean_display_name(
        info.get("name"),
        info.get("given_name"),
        email.split("@")[0] if "@" in email else email,
    )
    if not display_name:
        display_name = email.split("@")[0] if "@" in email else email

    user = User.query.filter_by(email=email).first()
    if not user:
        user = User.query.filter_by(username=email).first()
        if user:
            user.email = email
    if not user and preferred_role is None:
        return jsonify({
            "error": "role_required",
            "needs_role": True,
            "message": "Select whether this Google account should be parent or child.",
        }), 412

    if not user:
        default_profile_data = json.dumps({"schedule_blocks": [], "preferences": _default_preferences()})
        username = _unique_username(display_name or email)
        user = User(
            username=username,
            email=email,
            display_name=display_name or username,
            password=generate_password_hash(secrets.token_urlsafe(16)),
            auth_provider="google",
            account_type=preferred_role or "parent",
            profile_data=default_profile_data,
        )
        db.session.add(user)
    else:
        if not user.email:
            user.email = email
        if (user.username or "").strip().lower() == email or "@" in (user.username or ""):
            desired = display_name or email
            user.username = _unique_username(desired, exclude_user=user)
        if user.account_type not in ("parent", "child") and preferred_role:
            user.account_type = preferred_role
        if not (user.display_name or "").strip():
            user.display_name = display_name or user.username
    user.display_name = display_name or _user_display_name(user)
    user.auth_provider = "google"

    db.session.commit()

    token = create_access_token(identity=user.username)
    return jsonify({
        "message": "Login successful",
        "token": token,
        "username": user.username,
        "display_name": _user_display_name(user),
        "role": user.account_type,
    }), 200

# -------------------- Profile / Me --------------------
@app.route("/profile", methods=["GET"])
@jwt_required()
def profile_get():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404
    target_child = request.args.get("target_child")
    try:
        schedule_user = _resolve_schedule_user(user, target_child)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    return jsonify(_safe_profile_dict(schedule_user.profile_data)), 200

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
    user = _current_user_from_token()
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
        "user": {
            "username": user.username,
            "display_name": _user_display_name(user),
            "role": user.account_type,
            "email": user.email,
            "auth_provider": (user.auth_provider or "password"),
        },
        "families": [fam_entry] if fam_entry else []
    }), 200

# -------------------- Account Management --------------------
def _require_password(user: 'User', supplied: str) -> bool:
    return bool(supplied and check_password_hash(user.password, supplied))

@app.route("/account/credentials", methods=["POST"])
@jwt_required()
def account_update_credentials():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404

    payload = request.get_json(silent=True) or {}
    current_password = (payload.get("current_password") or payload.get("password") or "").strip()
    if not current_password:
        return jsonify({"error": "Current password is required."}), 400
    if not _require_password(user, current_password):
        return jsonify({"error": "Incorrect password."}), 403

    new_username = (payload.get("new_username") or "").strip()
    new_password = str(payload.get("new_password") or "")
    confirm_val = payload.get("confirm_password")
    if confirm_val is None:
        confirm_val = payload.get("new_password_confirm")
    confirm = str(confirm_val) if confirm_val is not None else None

    changes: list[str] = []
    if new_username and new_username != user.username:
        if len(new_username) > 100:
            return jsonify({"error": "Username must be 1–100 characters."}), 400
        existing = User.query.filter(User.username == new_username, User.id != user.id).first()
        if existing:
            return jsonify({"error": "Username is already taken."}), 400
        previous_username = user.username
        user.username = new_username
        families = Family.query.filter_by(creator_username=previous_username).all()
        for fam in families:
            fam.creator_username = new_username
        changes.append("username")

    if new_password:
        if confirm is not None and new_password != confirm:
            return jsonify({"error": "Passwords do not match."}), 400
        if not (8 <= len(new_password) <= 20):
            return jsonify({"error": "Password must be 8–20 characters."}), 400
        user.password = generate_password_hash(new_password)
        changes.append("password")

    if not changes:
        return jsonify({"error": "Provide a new username and/or password to update."}), 400

    db.session.commit()
    new_token = create_access_token(identity=user.username)
    return jsonify({
        "message": "Account updated successfully.",
        "username": user.username,
        "token": new_token,
        "changed": changes,
    }), 200

@app.route("/account/google/switch", methods=["POST"])
@jwt_required()
def account_switch_google():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    if (user.auth_provider or "password") != "google":
        return jsonify({"error": "Google sign-in is not linked to this account."}), 400

    payload = request.get_json(silent=True) or {}
    current_password = (payload.get("current_password") or payload.get("password") or "").strip()
    if not current_password:
        return jsonify({"error": "Current password is required."}), 400
    if not _require_password(user, current_password):
        return jsonify({"error": "Incorrect password."}), 403

    id_token = (payload.get("id_token") or "").strip()
    if not id_token:
        return jsonify({"error": "Google id_token is required."}), 400

    info = _verify_google_id_token(id_token)
    if not info:
        return jsonify({"error": "Invalid Google token."}), 400

    email = (info.get("email") or "").strip().lower()
    if not email:
        return jsonify({"error": "Google account is missing an email address."}), 400
    if user.email and user.email.lower() == email:
        return jsonify({"error": "That Google account is already linked."}), 400

    conflict = User.query.filter(User.email == email, User.id != user.id).first()
    if conflict:
        return jsonify({"error": "Another account already uses that Google email."}), 409

    user.email = email
    user.auth_provider = "google"

    db.session.commit()
    new_token = create_access_token(identity=user.username)
    return jsonify({
        "message": "Google account updated.",
        "username": user.username,
        "email": user.email,
        "token": new_token,
    }), 200

# -------------------- Schedule Blocks --------------------
@app.route("/profile/block/add", methods=["POST"])
@jwt_required()
def block_add():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    if user.account_type.lower() == "child":
        return jsonify({"error": "Children cannot add tasks"}), 403

    payload = request.get_json(silent=True) or {}
    block_payload = payload.get("block")
    if not isinstance(block_payload, dict):
        return jsonify({"error": "Missing 'block'"}), 400

    apply_family = bool(payload.get("apply_to_family"))
    if apply_family:
        family = _family_for_user(user)
        if not family:
            return jsonify({"error": "Join a family to assign to all children"}), 400
        children = _family_children(family)
        if not children:
            return jsonify({"error": "No children available in this family"}), 400
        family_tag = (payload.get("family_tag") or "").strip() or f"fam-{secrets.token_hex(8)}"
        normalized = _norm_block(block_payload)
        normalized["family_tag"] = family_tag
        owner, _ = _schedule_owner(user)
        _append_block_to_user(owner, normalized)
        for child in children:
            _append_block_to_user(child, normalized)
        db.session.commit()
        return jsonify({"message": "Family task added", "family_tag": family_tag}), 200

    try:
        schedule_user = _resolve_schedule_user(user, payload.get("target_child"))
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    prof = _safe_profile_dict(schedule_user.profile_data)
    prof["schedule_blocks"].append(_norm_block(block_payload))
    schedule_user.profile_data = json.dumps(prof)
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

    if payload.get("apply_to_family"):
        family = _family_for_user(user)
        if not family:
            return jsonify({"error": "Join a family to edit this task"}), 400
        tag = (payload.get("family_tag") or "").strip()
        if not tag and isinstance(old_block, dict):
            tag = (old_block.get("family_tag") or "").strip()
        if not tag and isinstance(new_block, dict):
            tag = (new_block.get("family_tag") or "").strip()
        if not tag:
            return jsonify({"error": "Family task identifier missing"}), 400
        normalized = _norm_block(new_block)
        normalized["family_tag"] = tag
        owner, _ = _schedule_owner(user)
        changed = _update_block_with_tag(owner, tag, normalized)
        for child in _family_children(family):
            changed = _update_block_with_tag(child, tag, normalized) or changed
        if not changed:
            return jsonify({"error": "Family task not found"}), 404
        db.session.commit()
        return jsonify({"message": "Family block edit successful"}), 200

    try:
        schedule_user = _resolve_schedule_user(user, payload.get("target_child"))
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    prof = _safe_profile_dict(schedule_user.profile_data)
    idx = _first_match_index(prof["schedule_blocks"], old_block)
    if idx < 0:
        return jsonify({"error": "Old block not found"}), 404

    prof["schedule_blocks"][idx] = _norm_block(new_block)
    schedule_user.profile_data = json.dumps(prof)
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
    if bool(payload.get("apply_to_family")):
        family = _family_for_user(user)
        if not family:
            return jsonify({"error": "Join a family to manage family-wide tasks"}), 400
        tag = (payload.get("family_tag") or "").strip()
        if not tag and isinstance(payload.get("block"), dict):
            tag = (payload["block"].get("family_tag") or "").strip()
        if not tag:
            return jsonify({"error": "Family task identifier missing"}), 400
        owner, _ = _schedule_owner(user)
        changed = _remove_family_tag_from_user(owner, tag)
        for child in _family_children(family):
            changed = _remove_family_tag_from_user(child, tag) or changed
        if not changed:
            return jsonify({"error": "Family task not found"}), 404
        db.session.commit()
        return jsonify({"message": "Family task removed"}), 200

    try:
        schedule_user = _resolve_schedule_user(user, payload.get("target_child"))
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    prof = _safe_profile_dict(schedule_user.profile_data)
    blocks = prof["schedule_blocks"]

    # delete by index (if provided)
    if isinstance(payload.get("index"), int):
        i = payload["index"]
        if 0 <= i < len(blocks):
            removed = blocks.pop(i)
            schedule_user.profile_data = json.dumps(prof)
            db.session.commit()
            return jsonify({"message": "Deleted", "deleted": removed}), 200
        return jsonify({"error": "Index out of range"}), 400

    # delete by block (robust matching)
    cand = payload.get("block")
    if isinstance(cand, dict):
        idx = _first_match_index(blocks, cand)
        if idx >= 0:
            removed = blocks.pop(idx)
            schedule_user.profile_data = json.dumps(prof)
            db.session.commit()
            return jsonify({"message": "Deleted", "deleted": removed}), 200
        return jsonify({"error": "Block not found"}), 404

    return jsonify({"error": "Provide 'index' or 'block'"}), 400

@app.route("/profile/preferences", methods=["GET", "POST"])
@jwt_required()
def profile_preferences():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    prof = _safe_profile_dict(user.profile_data)
    prefs = prof.get("preferences", _default_preferences())

    if request.method == "GET":
        return jsonify({"preferences": prefs}), 200

    payload = request.get_json(silent=True) or {}
    theme = (payload.get("theme") or "").strip().lower()
    if theme not in ("light", "dark", "system"):
        return jsonify({"error": "Theme must be 'light', 'dark', or 'system'."}), 400

    prefs["theme"] = theme
    prof["preferences"] = prefs
    user.profile_data = json.dumps(prof)
    db.session.commit()
    return jsonify({"preferences": prefs}), 200

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
        user.family_joined_at = datetime.utcnow()

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
    if user.family_id:
        return jsonify({"error": "Leave your current family before joining another one."}), 400

    user.family_id = family_id
    user.family_joined_at = datetime.utcnow()
    db.session.commit()
    return jsonify({"message": "Joined family successfully"}), 200

@app.route("/family/update", methods=["POST"])
@jwt_required()
def family_update():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "User is not part of a family"}), 400
    if user.account_type.lower() != "parent" or family.creator_username != user.username:
        return jsonify({"error": "Only the master parent can update the family."}), 403

    payload = request.get_json(silent=True) or {}
    current_password = (payload.get("current_password") or payload.get("password") or "").strip()
    if not current_password:
        return jsonify({"error": "Current family password is required."}), 400
    if not check_password_hash(family.password, current_password):
        return jsonify({"error": "Incorrect family password."}), 403

    new_name = (payload.get("name") or payload.get("new_name") or "").strip()
    new_password = (payload.get("new_password") or "").strip()

    changes: list[str] = []
    if new_name and new_name != family.name:
        if len(new_name) > 16:
            return jsonify({"error": "Family name must be at most 16 characters."}), 400
        family.name = new_name
        changes.append("name")

    if new_password:
        if not (8 <= len(new_password) <= 20):
            return jsonify({"error": "Family password must be 8–20 characters."}), 400
        family.password = generate_password_hash(new_password)
        changes.append("password")

    if not changes:
        return jsonify({"error": "Provide a new name and/or password to update."}), 400

    db.session.commit()
    return jsonify({
        "message": "Family updated.",
        "family": {"name": family.name, "identifier": family.family_id},
        "changed": changes,
    }), 200

@app.route("/family/invite", methods=["POST"])
@jwt_required()
def family_invite_send():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    if user.account_type.lower() != "parent":
        return jsonify({"error": "Only parents can send invites."}), 403

    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "Join a family before inviting children."}), 400

    payload = request.get_json(silent=True) or {}
    child_username = (payload.get("child_username") or payload.get("username") or "").strip()
    if not child_username:
        return jsonify({"error": "Child username required."}), 400
    if child_username == user.username:
        return jsonify({"error": "You cannot invite yourself."}), 400

    child = User.query.filter_by(username=child_username).first()
    if not child or child.account_type.lower() != "child":
        return jsonify({"error": "Child account not found."}), 404

    existing = FamilyInvite.query.filter_by(
        family_id=family.family_id,
        child_username=child_username,
        status="pending",
    ).first()
    if existing:
        return jsonify({"message": "An invite is already pending for this child."}), 200

    invite = FamilyInvite(family_id=family.family_id, child_username=child_username)
    db.session.add(invite)
    db.session.commit()
    return jsonify({"message": "Invitation sent."}), 200

@app.route("/family/invite/my", methods=["GET"])
@jwt_required()
def family_invite_my():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    if user.account_type.lower() != "child":
        return jsonify({"error": "Only child accounts receive invites."}), 403

    invites = FamilyInvite.query.filter_by(
        child_username=user.username,
        status="pending",
    ).order_by(FamilyInvite.created_at.asc()).all()
    results = []
    for inv in invites:
        family = Family.query.filter_by(family_id=inv.family_id).first()
        if not family:
            continue
        results.append({
            "family_id": inv.family_id,
            "family_name": family.name,
            "created_at": inv.created_at.isoformat() if inv.created_at else None,
        })
    return jsonify({"invites": results}), 200

@app.route("/family/invite/respond", methods=["POST"])
@jwt_required()
def family_invite_respond():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    if user.account_type.lower() != "child":
        return jsonify({"error": "Only child accounts can respond to invites."}), 403

    payload = request.get_json(silent=True) or {}
    family_id = (payload.get("family_id") or "").strip()
    action = (payload.get("action") or "").strip().lower()
    if not family_id or action not in ("accept", "approve", "reject", "deny"):
        return jsonify({"error": "Provide family_id and action ('accept' or 'reject')."}), 400

    invite = FamilyInvite.query.filter_by(
        family_id=family_id,
        child_username=user.username,
        status="pending",
    ).first()
    if not invite:
        return jsonify({"error": "Invite not found."}), 404

    family = Family.query.filter_by(family_id=family_id).first()
    if not family:
        invite.status = "rejected"
        db.session.commit()
        return jsonify({"error": "Family no longer exists."}), 404

    if action in ("reject", "deny"):
        invite.status = "rejected"
        db.session.commit()
        return jsonify({"message": "Invite declined."}), 200

    # accept path
    if user.family_id and user.family_id != family_id:
        # cannot accept now, keep pending
        return jsonify({"error": "Leave your current family before accepting this invite."}), 409

    invite.status = "accepted"
    if not user.family_id:
        user.family_id = family_id
        user.family_joined_at = datetime.utcnow()
    db.session.commit()
    return jsonify({"message": "Welcome to the family!", "family_id": family_id}), 200

@app.route("/family/members", methods=["GET"])
@jwt_required()
def family_members():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "User is not part of a family"}), 400

    members = User.query.filter_by(family_id=family.family_id).all()
    parents = []
    children = []
    for member in members:
        role = member.account_type.lower()
        if role == "parent":
            parents.append({
                "username": member.username,
                "is_master": member.username == family.creator_username,
                "display_name": _user_display_name(member),
            })
        else:
            children.append({
                "username": member.username,
                "display_name": _user_display_name(member),
            })

    pending = FamilyLeaveRequest.query.filter_by(family_id=family.family_id, status="pending").count()
    is_master = user.account_type.lower() == "parent" and user.username == family.creator_username
    return jsonify({
        "family_id": family.family_id,
        "is_master": is_master,
        "pending_leave_requests": pending if is_master else 0,
        "parents": parents,
        "children": children,
    }), 200

@app.route("/family/member/remove", methods=["POST"])
@jwt_required()
def family_member_remove():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "User is not part of a family"}), 400
    if user.account_type.lower() != "parent" or user.username != family.creator_username:
        return jsonify({"error": "Only the master parent can remove members"}), 403

    payload = request.get_json(silent=True) or {}
    target_username = (payload.get("username") or "").strip()
    if not target_username:
        return jsonify({"error": "Username is required"}), 400
    if target_username == user.username:
        return jsonify({"error": "Master parent cannot remove themselves"}), 400

    target = User.query.filter_by(username=target_username).first()
    if not target or target.family_id != family.family_id:
        return jsonify({"error": "User is not part of this family"}), 404

    if target.account_type.lower() == "child":
        _clear_child_tasks(target)
    _detach_user_from_family(target)
    FamilyLeaveRequest.query.filter_by(family_id=family.family_id, child_username=target.username).delete()
    db.session.commit()
    return jsonify({"message": f"Removed {target_username} from family"}), 200

@app.route("/family/leave", methods=["POST"])
@jwt_required()
def family_leave():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "You are not currently in a family."}), 400

    if user.account_type.lower() == "child":
        existing = FamilyLeaveRequest.query.filter_by(
            family_id=family.family_id,
            child_username=user.username,
            status="pending",
        ).first()
        if existing:
            return jsonify({"message": "A leave request is already pending approval."}), 200
        req = FamilyLeaveRequest(family_id=family.family_id, child_username=user.username)
        db.session.add(req)
        db.session.commit()
        return jsonify({"message": "Leave request sent to the master parent."}), 200

    message = _handle_parent_leave(user, family)
    db.session.commit()
    return jsonify({"message": message}), 200

@app.route("/family/leave/requests", methods=["GET"])
@jwt_required()
def family_leave_requests():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "User is not part of a family"}), 400
    if user.account_type.lower() != "parent" or user.username != family.creator_username:
        return jsonify({"error": "Only the master parent can view leave requests"}), 403

    pending = FamilyLeaveRequest.query.filter_by(
        family_id=family.family_id,
        status="pending",
    ).order_by(FamilyLeaveRequest.created_at.asc()).all()
    results = []
    for item in pending:
        child = User.query.filter_by(username=item.child_username).first()
        results.append({
            "child_username": item.child_username,
            "display_name": _user_display_name(child),
            "requested_at": item.created_at.isoformat() if item.created_at else None,
        })
    return jsonify({"requests": results}), 200

@app.route("/family/leave/requests/handle", methods=["POST"])
@jwt_required()
def family_leave_requests_handle():
    user = _current_user_from_token()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "User is not part of a family"}), 400
    if user.account_type.lower() != "parent" or user.username != family.creator_username:
        return jsonify({"error": "Only the master parent can manage leave requests"}), 403

    payload = request.get_json(silent=True) or {}
    child_username = (payload.get("child_username") or "").strip()
    action = (payload.get("action") or "").strip().lower()
    if not child_username or action not in ("approve", "accept", "deny", "reject"):
        return jsonify({"error": "Provide child_username and action ('approve' or 'reject')."}), 400

    request_row = FamilyLeaveRequest.query.filter_by(
        family_id=family.family_id,
        child_username=child_username,
        status="pending",
    ).first()
    if not request_row:
        return jsonify({"error": "No pending request found for that child."}), 404

    approved = action in ("approve", "accept")
    success = False
    child = User.query.filter_by(username=child_username).first()
    if approved:
        if child and child.family_id == family.family_id:
            _clear_child_tasks(child)
            _detach_user_from_family(child)
            success = True
        else:
            success = True  # child already left; treat as handled
    FamilyLeaveRequest.query.filter_by(id=request_row.id).delete()
    db.session.commit()
    if success and approved:
        return jsonify({"message": f"{child_username} has left the family."}), 200
    return jsonify({"message": "Leave request rejected."}), 200

@app.route("/family/master/transfer", methods=["POST"])
@jwt_required()
def family_transfer_master():
    current_user = get_jwt_identity()
    user = User.query.filter_by(username=current_user).first()
    if not user:
        return jsonify({"error": "User not found"}), 404
    family = _family_for_user(user)
    if not family:
        return jsonify({"error": "User is not part of a family"}), 400
    if user.account_type.lower() != "parent" or user.username != family.creator_username:
        return jsonify({"error": "Only the master parent can transfer ownership"}), 403

    payload = request.get_json(silent=True) or {}
    target_username = (payload.get("username") or "").strip()
    if not target_username:
        return jsonify({"error": "Username is required"}), 400
    if target_username == user.username:
        return jsonify({"error": "Target must be a different parent"}), 400

    target = User.query.filter_by(username=target_username).first()
    if not target or target.family_id != family.family_id:
        return jsonify({"error": "User is not part of this family"}), 404
    if target.account_type.lower() != "parent":
        return jsonify({"error": "Only parents can become master"}), 400

    master_profile = _safe_profile_dict(user.profile_data)
    target_profile = _safe_profile_dict(target.profile_data)

    target_profile["schedule_blocks"] = list(master_profile.get("schedule_blocks", []))
    master_profile["schedule_blocks"] = []

    user.profile_data = json.dumps(master_profile)
    target.profile_data = json.dumps(target_profile)
    family.creator_username = target.username
    db.session.commit()

    return jsonify({"message": f"Transferred master role to {target_username}"}), 200

# -------------------- Health --------------------
@app.route("/")
def health():
    return jsonify({"ok": True})

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
