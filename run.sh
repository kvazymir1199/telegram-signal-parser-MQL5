#!/bin/bash

# Virtual environment directory name
VENV_DIR="venv"
PROJECT_DIR="telegram_signal_parser"

echo "============================================================"
echo "   Telegram Signal Parser: Automated Setup and Launch"
echo "============================================================"

# 1. Check Python installation
if ! command -v python3 &> /dev/null
then
    echo "Error: python3 not found. Please install Python."
    exit 1
fi

# 2. Create virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo "--> Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# 3. Activate and install dependencies
echo "--> Activating environment and installing dependencies..."
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$PROJECT_DIR/requirements.txt"

# 4. Check .env file (Optional in production, settings can be set in Dashboard)
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "Notice: $PROJECT_DIR/.env not found. Using defaults/database settings."
fi

# 5. Clean up old processes and locks
echo "--> Checking for hung processes on port 8000..."
if command -v lsof &> /dev/null; then
    lsof -ti:8000 | xargs kill -9 2>/dev/null || true
fi
pkill -f "python3 main.py" 2>/dev/null || true
rm -f "$PROJECT_DIR"/*.session-journal 2>/dev/null || true

# 6. Create necessary directories and set permissions
echo "--> Preparing environment..."
mkdir -p "$PROJECT_DIR/data" "$PROJECT_DIR/logs" "$PROJECT_DIR/data_export"
chmod +x "$0"

# 7. Start application
echo "--> Launching Dashboard on http://127.0.0.1:8000..."
cd "$PROJECT_DIR"
export PYTHONPATH=$PYTHONPATH:$(pwd)
python3 "main.py"
