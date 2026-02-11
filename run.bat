@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM    Telegram Signal Parser: Zero-Touch Setup (Windows)
REM ============================================================

REM Get the directory where the script is located
cd /d %~dp0

set VENV_DIR=venv
set PROJECT_DIR=telegram_signal_parser
set PYTHON_VERSION=3.12.2
set INSTALLER_NAME=python-installer.exe

REM 1. Check Python installation
set PYTHON_CMD=
python --version >nul 2>&1
if %errorlevel% equ 0 set PYTHON_CMD=python& goto :PYTHON_FOUND

py --version >nul 2>&1
if %errorlevel% equ 0 set PYTHON_CMD=py& goto :PYTHON_FOUND

python3 --version >nul 2>&1
if %errorlevel% equ 0 set PYTHON_CMD=python3& goto :PYTHON_FOUND

REM 2. Python missing -> Download and Install
echo [!] Python not found on your system.
echo [*] Downloading Python %PYTHON_VERSION%...

REM Use curl (built into Windows 10+)
curl -fL "https://www.python.org/ftp/python/%PYTHON_VERSION%/python-%PYTHON_VERSION%-amd64.exe" -o %INSTALLER_NAME%

if not exist %INSTALLER_NAME% (
    echo [X] Failed to download Python installer.
    pause
    exit /b 1
)

for %%I in (%INSTALLER_NAME%) do (
    if %%~zI lss 1000000 (
        echo [X] Downloaded file is too small. Probably a download error.
        del %INSTALLER_NAME%
        pause
        exit /b 1
    )
)

echo [*] Installing Python... (This may require Administrative privileges)
echo [*] Please wait, this could take a minute...

REM Silent installation with PATH addition
start /wait %INSTALLER_NAME% /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
del %INSTALLER_NAME%

echo [*] Installation complete. Checking again...

REM Try to find it in default User folder since PATH didn't update in this window
set "FALLBACK_PYTHON=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if exist "%FALLBACK_PYTHON%" (
    set PYTHON_CMD="%FALLBACK_PYTHON%"
    goto :PYTHON_FOUND
)

REM Last attempt via standard command
python --version >nul 2>&1
if %errorlevel% equ 0 (
    set PYTHON_CMD=python
    goto :PYTHON_FOUND
)

echo [X] Python was installed but is not yet in your PATH.
echo [!] PLEASE CLOSE THIS WINDOW AND START run.bat AGAIN.
pause
exit /b 1

:PYTHON_FOUND
echo [*] Using Python command: %PYTHON_CMD%

REM 3. Create virtual environment
if exist "%VENV_DIR%" goto :VENV_EXISTS
echo --> Creating virtual environment...
%PYTHON_CMD% -m venv %VENV_DIR%
if %errorlevel% neq 0 (
    echo [X] Failed to create virtual environment.
    pause
    exit /b 1
)

:VENV_EXISTS
REM 4. Activate and install dependencies
echo --^> Activating environment and installing dependencies...
set "ACTIVATE_PATH=%VENV_DIR%\Scripts\activate.bat"
if not exist "%ACTIVATE_PATH%" (
    echo [!] venv exists but is missing Windows activation script.
    echo [*] Recreating virtual environment for Windows...
    rd /s /q "%VENV_DIR%"
    %PYTHON_CMD% -m venv %VENV_DIR%
    if !errorlevel! neq 0 (
        echo [X] Failed to recreate virtual environment.
        pause
        exit /b 1
    )
)

call "%ACTIVATE_PATH%"
python -m pip install --upgrade pip
pip install -r %PROJECT_DIR%\requirements.txt

REM 5. Clean up old processes on port 8000
echo --> Checking for hung processes on port 8000...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :8000 ^| findstr LISTENING') do (
    if not "%%a"=="" (
        echo Found process %%a on port 8000. Terminating...
        taskkill /F /PID %%a >nul 2>&1
    )
)

REM 6. Create necessary directories
echo --> Preparing environment...
if not exist "%PROJECT_DIR%\data" mkdir "%PROJECT_DIR%\data"
if not exist "%PROJECT_DIR%\logs" mkdir "%PROJECT_DIR%\logs"
if not exist "%PROJECT_DIR%\data_export" mkdir "%PROJECT_DIR%\data_export"

REM 7. Start application
echo --> Launching Dashboard on http://127.0.0.1:8000...
cd %PROJECT_DIR%
set PYTHONPATH=%PYTHONPATH%;%CD%
python "main.py"

pause
