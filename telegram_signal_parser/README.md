# Telegram Signal Parser

A service for automatically reading trading signals from Telegram channels and preparing them for MetaTrader 5.

## Features
- Real-time channel monitoring (Userbot based on Telethon).
- Signal parsing for Gold (XAUUSD/GOLD).
- Validation of trading levels (SL, TP, Entry).
- Signal history storage in SQLite (via SQLAlchemy).
- Export of the latest signal to CSV/TXT format for the Expert Advisor.

## Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure settings:
   - Copy `.env.example` to `.env`.
   - Obtain `API_ID` and `API_HASH` at [my.telegram.org](https://my.telegram.org).
   - Specify your phone number and target channel IDs in the `.env` file.

## Launch

```bash
python main.py
```

On the first run, you will need to enter a confirmation code received in your Telegram app.

## Testing

```bash
pytest tests/test_parser.py
```
