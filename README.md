# My App

Flutter + Flask playground for experimenting with family schedules, notifications, and Google authentication.

## Requirements

- Flutter 3.22+ and Dart 3.9+
- Xcode (iOS/macOS) or Android Studio toolchains
- Python 3.11+ with `pipenv`/`venv`
- Firebase project with Google Sign-In enabled

## Backend (Flask) Setup

```bash
cd flask
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export FLASK_APP=app.py
export JWT_SECRET_KEY=replace-me
# Google client IDs (see below)
export GOOGLE_WEB_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT.apps.googleusercontent.com
export GOOGLE_CLIENT_IDS=$GOOGLE_WEB_CLIENT_ID
flask run
```

`GOOGLE_CLIENT_IDS` accepts a comma-separated allow list that the backend trusts when verifying Google ID tokens. Convenience env vars `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_ANDROID_CLIENT_ID`, and `GOOGLE_IOS_CLIENT_ID` are automatically merged into that allow list.

## Flutter App Setup

1. Run `flutterfire configure` (or download from the Firebase console) to populate:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
   - `macos/Runner/GoogleService-Info.plist`
2. Collect the OAuth client IDs that Google issues for each platform (Web, Android, iOS).
3. Launch Flutter with matching `dart-define` flags so the `GoogleSignIn` plugin can request ID tokens:

```bash
flutter run \
  --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT.apps.googleusercontent.com \
  --dart-define=GOOGLE_ANDROID_CLIENT_ID=YOUR_ANDROID_CLIENT.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT.apps.googleusercontent.com
```

Only the web client ID is strictly required on Android (it is used as the `serverClientId`). iOS and macOS need both the web client ID **and** the dedicated iOS client ID so the native SDK can complete the handshake.

## Google Authentication Flow

1. The Flutter app signs in with Google (the button stays disabled until the required client IDs are provided). If the backend reports that this Google email has never been seen before, the app immediately prompts the user to choose **Parent** or **Child** and resends the token with that preference.
2. The token is posted to `POST /login/google` on the Flask backend.
3. The backend validates the token via `https://oauth2.googleapis.com/tokeninfo` and checks that the `aud` claim matches one of the configured client IDs.
4. If the user does not already exist, a new account is created with the Google profile name as the in‑app username, while the Google email is stored separately to keep the identity stable.
5. A JWT is issued (`create_access_token`) and returned to the app for subsequent API calls.

If you change your OAuth credentials, update both the backend environment variables and the Flutter `dart-define`s so the `aud` claim continues to match.

> **Note:** On first run after pulling these changes, delete `flask/users.db` (dev only) or let the app re-create the `email` column automatically. Existing Google accounts will be upgraded the next time they log in.

## Running Everything Together

1. Start the Flask server (see above).
2. In another terminal, run `flutter run` with the `dart-define`s.
3. Use the login screen to sign in with Google or the traditional username/password flow.

Happy hacking!
