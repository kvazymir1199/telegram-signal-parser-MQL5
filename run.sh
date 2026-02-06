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

# 4. Check .env file
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "============================================================"
    echo "WARNING: File $PROJECT_DIR/.env not found!"
    echo "Please create it based on .env.example"
    echo "Application cannot start without valid settings."
    echo "============================================================"
    exit 1
fi

# 5. Clean up old processes and locks
echo "--> Checking for hung processes..."
pkill -f "python3 main.py" 2>/dev/null || true
rm -f "$PROJECT_DIR"/*.session-journal 2>/dev/null || true

# 6. Create necessary directories
echo "--> Creating data and logs directories..."
mkdir -p "$PROJECT_DIR/data" "$PROJECT_DIR/logs" "$PROJECT_DIR/mt5_signals"

# 7. Start application
echo "--> Launching application..."
cd "$PROJECT_DIR"
export PYTHONPATH=$PYTHONPATH:$(pwd)
python3 "main.py"
