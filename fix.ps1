# === Flask + JWT Repair Script (Windows, Python 3.12+) ===
# Run this in PowerShell from your project folder.

Write-Host "🚧 Cleaning old installs..." -ForegroundColor Yellow
pip uninstall cryptography cffi PyJWT jwt flask-jwt-extended -y

Write-Host "⬆️  Upgrading pip, setuptools, wheel..." -ForegroundColor Cyan
pip install --upgrade pip setuptools wheel

Write-Host "🧱  Forcing pip to use only binary wheels (no source builds)..." -ForegroundColor Cyan
pip config set global.only-binary ":all:"

Write-Host "🔐  Installing clean, precompiled cryptography wheel..." -ForegroundColor Cyan
pip install --only-binary cryptography cryptography==42.0.8

Write-Host "📦  Reinstalling Flask JWT dependencies..." -ForegroundColor Cyan
pip install flask-jwt-extended PyJWT flask flask_sqlalchemy flask_cors


PYCODE
