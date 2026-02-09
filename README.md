# Telegram Signal Parser Service

A high-performance Python service that monitors Telegram channels for XAUUSD (Gold) trading signals, parses them using advanced regex patterns, and stores them in a local SQLite database.

## 🚀 Quick Start

1. **Setup Python Environment:**
   Run the automated setup script:
   ```bash
   ./run.sh
   ```
   *This will create a virtual environment, install dependencies, and launch the Dashboard.*

2. **Configure via Dashboard:**
   Open your browser at [http://127.0.0.1:8000](http://127.0.0.1:8000)
   - Enter your **Telegram API ID** and **API Hash** (get them from [my.telegram.org](https://my.telegram.org)).
   - Add the **Channel IDs** you want to monitor.
   - Click **"Apply Changes"**.

3. **Start Parsing:**
   Click the **"Start Parser"** button on the Dashboard. Monitor the "Live Parser Logs" to ensure it connects successfully and starts receiving messages.

## 🛠 System Features

- **Dashboard:** Modern web UI for configuration, real-time monitoring, and process control.
- **Advanced Parser:** Robust Regex engine specifically tuned for Gold (XAUUSD) signals with support for ranges and multiple targets.
- **Risk Validation:** Automated signal filtering based on Stop Loss distance and symbol keywords.
- **Database:** Persistent SQLite3 storage for full signal history and configuration.
- **Clean Logs:** Separated logging system focusing on parser events without web server noise.

## 📁 Project Structure

```text
.
├── telegram_signal_parser/   # Python service root
│   ├── web/                  # Dashboard (FastAPI + Tailwind)
│   ├── parser/               # Signal extraction logic
│   ├── database/             # SQLite & SQLAlchemy models
│   ├── config/               # Pydantic settings & validation
│   └── main.py               # Service entry point
├── run.sh                    # Automated setup & launch script
└── CLAUDE.md                 # Technical guidelines
```

## ⚠️ Requirements
- Python 3.10+
- Telegram API Credentials (API ID & Hash)
