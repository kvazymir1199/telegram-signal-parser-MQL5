@echo off
setlocal enabledelayedexpansion

:: Get the directory where the script is located
cd /d %~dp0

set VENV_DIR=venv
set PROJECT_DIR=telegram_signal_parser
set PYTHON_VERSION=3.12.2
set INSTALLER_NAME=python-installer.exe

echo ============================================================
echo    Telegram Signal Parser: Zero-Touch Setup (Windows)
echo ============================================================

:: 1. Check Python installation
set PYTHON_CMD=
python --version >nul 2>&1
if %errorlevel% equ 0 (
    set PYTHON_CMD=python
) else (
    py --version >nul 2>&1
    if %errorlevel% equ 0 (
        set PYTHON_CMD=py
    ) else (
        python3 --version >nul 2>&1
        if %errorlevel% equ 0 (
            set PYTHON_CMD=python3
        )
    )
)

:: 2. If Python is missing, download and install it
if "%PYTHON_CMD%"=="" (
    echo [!] Python not found on your system.
    echo [*] Downloading Python %PYTHON_VERSION%...

    :: Use curl (built into Windows 10+) to download installer
    :: Added -f (fail silently on server errors) and better error handling
    curl -fL "https://www.python.org/ftp/python/%PYTHON_VERSION%/python-%PYTHON_VERSION%-amd64.exe" -o %INSTALLER_NAME%

    :: Check if file exists and is not empty instead of just errorlevel
    if not exist %INSTALLER_NAME% (
        echo [X] Failed to download Python installer. File not found.
        pause
        exit /b 1
    )

    for %%I in (%INSTALLER_NAME%) do if %%~zI lss 1000000 (
        echo [X] Downloaded file is too small. Probably a download error.
        del %INSTALLER_NAME%
        pause
        exit /b 1
    )

    echo [*] Installing Python... (This may require Administrative privileges)
    echo [*] Please wait, this could take a minute...

    :: Silent installation with PATH addition
    start /wait %INSTALLER_NAME% /quiet InstallAllUsers=0 PrependPath=1 Include_test=0

    :: Cleanup installer
    del %INSTALLER_NAME%

    :: Re-check after installation
    :: We need to refresh environment variables in current session if possible,
    :: but usually a simple re-search in default paths works.
    echo [*] Installation complete. Checking again...

    :: Try common install paths as fallback since PATH doesn't update in current CMD
    set "USER_PYTHON_PATH=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    if exist "!USER_PYTHON_PATH!" (
        set PYTHON_CMD="!USER_PYTHON_PATH!"
    ) else (
        python --version >nul 2>&1
        if %errorlevel% equ 0 (
            set PYTHON_CMD=python
        ) else (
            echo [X] Python was installed but is not yet in your PATH.
            echo [!] PLEASE RESTART THIS SCRIPT (run.bat) to continue.
            pause
            exit /b 1
        )
    )
)

echo [*] Using Python command: %PYTHON_CMD%

:: 3. Create virtual environment
if not exist "%VENV_DIR%" (
    echo --> Creating virtual environment...
    %PYTHON_CMD% -m venv %VENV_DIR%
    if %errorlevel% neq 0 (
        echo [X] Failed to create virtual environment.
        pause
        exit /b 1
    )
)

:: 4. Activate and install dependencies
echo --> Activating environment and installing dependencies...
call %VENV_DIR%\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r %PROJECT_DIR%\requirements.txt

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
