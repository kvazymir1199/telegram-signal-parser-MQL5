# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Telegram Signal Parser project.

## Project Overview

Telegram Signal Parser Service - a standalone Python service that:
1. Reads XAUUSD signals from specified Telegram channels/groups.
2. Parses message content using flexible regex patterns.
3. Validates signals based on risk management rules (SL distance, symbol filtering).
4. Stores full signal history and configuration in a local SQLite3 database.

## Architecture

```
Telegram → [Python Parser Service] → SQLite3 Database → Web Dashboard
```

## Python Component

### Tech Stack
- FastAPI (Web Dashboard)
- Telethon (Telegram MTProto client)
- Pydantic (Data validation and settings)
- SQLite3 / SQLAlchemy (Storage)
- Loguru (Logging with file filtering)

### Structure
```
telegram_signal_parser/
├── config/settings.py     # Pydantic Settings & Validators
├── database/
│   ├── connection.py      # SQLAlchemy DB Manager
│   └── models.py          # Data models (Signal, Setting)
├── parser/signal_parser.py # Regex engine for extraction
├── telegram/client.py     # Telethon event handlers
├── web/                   # Dashboard (templates, app logic)
└── main.py                # Service entry point
```

### Signal Parsing Rules
- **Symbol**: XAUUSD, GOLD (normalized to XAUUSD).
- **Direction**: BUY/SELL/LONG/SHORT.
- **Entry**: Supports single value or ranges ("2350 to 2352" or "2350-2352").
- **Stop Loss**: Mandatory (keywords: SL, Stop Loss).
- **Take Profits**: Supports multiple targets (keywords: TP, TP1, TP2, etc.).

### Validation Logic
- **BUY**: SL < Entry < TP1 < TP2.
- **SELL**: SL > Entry > TP1 > TP2.
- **Max SL Distance**: Configurable via Dashboard (prevents high-risk entries).

## Web Dashboard
- **URL**: http://127.0.0.1:8000 (configurable via settings).
- **Features**:
  - Live process control (Start/Stop).
  - Clean log monitoring (filtered from web noise).
  - Persistent configuration (API keys, Channel IDs, Filters).
  - Signal history view.

## Development Notes

- **Channel IDs**: For common groups, use the ID as provided (e.g., -5127304931). For channels/supergroups, the -100 prefix is usually required.
- **Logging**: Web request noise is filtered out from the `parser.log` file but remains in terminal stdout for debugging.
- **Risk Management**: Always validate the `max_sl_distance` when new signal types are introduced.
