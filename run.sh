#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

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
    # Try to find PID on port 8000 and kill it
    PID=$(lsof -ti:8000)
    if [ ! -z "$PID" ]; then
        echo "Found process $PID on port 8000. Terminating..."
        kill -9 $PID 2>/dev/null || true
    fi
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
# Ensure we use the venv's python
export PYTHONPATH=$PYTHONPATH:$(pwd)
python3 "main.py"
