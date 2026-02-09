@echo off
setlocal enabledelayedexpansion

:: Get the directory where the script is located
cd /d %~dp0

set VENV_DIR=venv
set PROJECT_DIR=telegram_signal_parser

echo ============================================================
echo    Telegram Signal Parser: Automated Setup and Launch
echo ============================================================

:: 1. Check Python installation
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: Python not found. Please install Python from https://www.python.org/
    pause
    exit /b 1
)

:: 2. Create virtual environment
if not exist "%VENV_DIR%" (
    echo --> Creating virtual environment...
    python -m venv %VENV_DIR%
)

:: 3. Activate and install dependencies
echo --> Activating environment and installing dependencies...
call %VENV_DIR%\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r %PROJECT_DIR%\requirements.txt

:: 4. Check .env file
if not exist "%PROJECT_DIR%\.env" (
    echo Notice: %PROJECT_DIR%\.env not found. Using defaults/database settings.
)

:: 5. Clean up old processes on port 8000
echo --> Checking for hung processes on port 8000...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :8000 ^| findstr LISTENING') do (
    if not "%%a"=="" (
        echo Found process %%a on port 8000. Terminating...
        taskkill /F /PID %%a >nul 2>&1
    )
)

:: 6. Create necessary directories
echo --> Preparing environment...
if not exist "%PROJECT_DIR%\data" mkdir "%PROJECT_DIR%\data"
if not exist "%PROJECT_DIR%\logs" mkdir "%PROJECT_DIR%\logs"
if not exist "%PROJECT_DIR%\data_export" mkdir "%PROJECT_DIR%\data_export"

:: 7. Start application
echo --> Launching Dashboard on http://127.0.0.1:8000...
cd %PROJECT_DIR%
set PYTHONPATH=%PYTHONPATH%;%CD%
python "main.py"

pause
