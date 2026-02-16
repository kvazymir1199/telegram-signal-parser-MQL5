# Telegram Signal Parser Service

A high-performance Python service that monitors Telegram channels for XAUUSD (Gold) trading signals, parses them using advanced regex patterns, and stores them in a local SQLite database for further integration.

---

## 🚀 Installation & Setup

Follow these steps to get the service running on your local machine.

### 1. Clone the Repository
Open your terminal and run:
```bash
git clone git@github.com:kvazymir1199/telegram-signal-parser-MQL5.git
cd telegram-signal-parser-MQL5
```

### 2. Launch the Service
The project includes automated setup scripts that create a virtual environment, install all dependencies, and launch the dashboard.

**For Linux / macOS:**
```bash
./run.sh
```

**For Windows:**
Double-click `run.bat` or run it from PowerShell:
```powershell
.\run.bat
```
Or from CMD:
```cmd
run.bat
```

### 3. Access the Dashboard
Once the script finishes, open your web browser and go to:
**[http://127.0.0.1:8000](http://127.0.0.1:8000)**

---

## ⚙️ Configuration Guide

Before starting the parser, you need to configure your Telegram credentials and the channels you want to monitor.

### Step 1: Telegram Credentials
1. Obtain your **API ID** and **API Hash** from [my.telegram.org](https://my.telegram.org).
2. Enter these values along with your **Phone Number** in the **Telegram API Configuration** section of the dashboard.
3. *Detailed guide available in:* [find_my_group_id.md](./find_my_group_id.md)

### Step 2: Channel Monitoring
1. Find the numeric ID of the Telegram group you want to monitor (using the guide above).
2. Add the ID to the **Channel Monitoring** list under the **Trading Filters** section.
3. Click **"Apply Changes"** to save your settings.

### Step 3: Start Parsing
1. Click the **"Start Parser"** button.
2. Monitor the **Live Parser Logs** at the bottom of the dashboard.
3. You will see a success message once the Telegram client is authorized.

---

## 🛠 Features

- **Automated Directory Picker:** Easily select path for your database via a visual menu.
- **Test Signal Generation:** Click **"Send Test Signal"** to instantly verify that the parser and database are working correctly.
- **Clean Logging:** A dedicated logging system that filters out web server noise, allowing you to focus on signal data.
- **Signal History:** View all parsed signals in a dedicated history page with detailed extraction info.

---

## 📁 Project Structure

```text
.
├── telegram_signal_parser/   # Python service root
│   ├── web/                  # Dashboard (FastAPI + Tailwind + HTMX)
│   ├── parser/               # Regex extraction logic
│   ├── database/             # SQLite & SQLAlchemy models
│   ├── config/               # Pydantic settings & validation
│   └── main.py               # Service entry point
├── run.sh                    # Automated setup & launch script
├── find_my_group_id.md       # Guide for Telegram credentials & IDs
└── CLAUDE.md                 # Technical guidelines
```

---

## ⚠️ Requirements

- **Python 3.10+** installed on your system.
- Active Telegram account and API credentials.
- Linux, macOS, or Windows (via Git Bash/WSL).
