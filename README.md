# Telegram Signal → MT5 Auto Trading System

A stable and risk-controlled trading automation system that bridge Telegram signals to MetaTrader 5 using a Python service and a custom MQL5 Expert Advisor.

## 🚀 Quick Start

1. **Setup Python Environment:**
   Run the automated setup script:
   ```bash
   ./run.sh
   ```
   *This will create a virtual environment, install dependencies, and launch the Dashboard.*

2. **Configure via Dashboard:**
   Open your browser at [http://127.0.0.1:7000](http://127.0.0.1:7000)
   - Enter your **Telegram API ID** and **API Hash** (get them from [my.telegram.org](https://my.telegram.org)).
   - Add the **Channel IDs** you want to monitor.
   - Set the **MT5 Export Path** to your MetaTrader 5 `MQL5/Files` directory.
   - Click **"Apply Changes"**.

3. **Start Parsing:**
   Click the **"Start Parser"** button on the Dashboard. Monitor the "Live Parser Logs" to ensure it connects successfully.

4. **Install MQL5 EA:**
   - Copy the contents of the `MQL5/Include/Nguyen-N/` folder to your MT5 `MQL5/Include/Nguyen-N/`.
   - Copy the file `MQL5/Experts/Nguyen-N/TelegramSignalEA.mq5` to your MT5 `MQL5/Experts/Nguyen-N/`.
   - Compile the EA in MetaEditor and attach it to an **XAUUSD** chart.

## 🛠 System Architecture

- **Python Service (FastAPI):**
  - **Dashboard:** Modern web UI for settings and process control.
  - **Parser:** Advanced Regex engine to extract XAUUSD signals.
  - **Database:** SQLite3 storage for signal history and persistent settings.
  - **Exporter:** Generates a UTF-16 CSV file for MT5 consumption.

- **MQL5 EA:**
  - **Risk Manager:** Monitors equity in real-time. Stops trading if daily loss ≥ 3%.
  - **Trade Executor:** Opens 2 orders per signal (TP1 and TP2) with mandatory SL.
  - **Position Manager:** Automatically moves Order 2 SL to Breakeven when Order 1 hits TP1.

## 🛡 Risk Management Rules

| Rule | Value | Action |
|------|-------|--------|
| Daily Loss Limit | 3% of daily start equity | Close all positions, stop until next day |
| Max Entry Deviation | 30 pips (configurable) | Ignore signal if price moved too far |
| SL Missing | - | Close trade immediately if SL fails to place |
| New Signal | - | Close all existing positions before following new signal |

## 📁 Project Structure

```text
.
├── telegram_signal_parser/   # Python component
│   ├── web/                  # Dashboard (FastAPI + Tailwind)
│   ├── parser/               # Regex logic
│   ├── database/             # SQLite & SQLAlchemy
│   ├── export/               # CSV Export logic
│   └── main.py               # Entry point
├── MQL5/                     # MetaTrader 5 component
│   ├── Experts/              # TelegramSignalEA.mq5
│   └── Include/              # Logic modules (.mqh)
├── run.sh                    # One-click launch script
└── CLAUDE.md                 # Project technical guidelines
```

## ⚠️ Requirements
- Python 3.10+
- MetaTrader 5 Terminal
- Telegram API Credentials
