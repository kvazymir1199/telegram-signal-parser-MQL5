# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Telegram Signal → MT5 Auto Trading System - two fully isolated components communicating via local file:
1. **Python Service** - reads XAUUSD signals from Telegram channels, parses and saves to SQLite3, exports to CSV/TXT
2. **MQL5 Expert Advisor** - reads signals from file, executes trades with strict risk management

## Architecture

```
Telegram → [Python Parser] → SQLite3 → CSV/TXT → [MQL5 EA] → MT5
```

### Key Constraints
- **NO DLL** - EA must not use external DLLs
- **NO WebRequest** - EA reads only local files
- **One active signal at a time** - new signal closes all existing positions
- **Two orders per signal** - Order1 (TP1), Order2 (TP2)
- **Daily loss limit: 3%** - stops trading until next day

## Python Component

### Tech Stack
- Telethon (MTProto client for Telegram)
- Pydantic (validation)
- SQLite3 (storage)
- Loguru (logging)

### Structure
```
telegram_signal_parser/
├── config/settings.py     # Pydantic Settings from .env
├── database/
│   ├── connection.py      # SQLite operations
│   └── models.py          # TradingSignal model with validation
├── parser/signal_parser.py # Regex patterns for signal extraction
├── telegram/client.py     # Telethon event handler
├── export/csv_exporter.py # CSV/TXT export for EA
└── main.py
```

### Signal Parsing Rules
- Direction: BUY/SELL/LONG/SHORT
- Entry range: "2350 to 2352" or "Entry: 2350"
- Stop Loss: "SL: 2340" or "Stop Loss: 2340"
- Take Profits: "TP1: 2355", "TP2: 2360"

### Validation Logic
- BUY: SL < Entry < TP1 < TP2
- SELL: SL > Entry > TP1 > TP2
- **Max SL Distance**: Default 15.00 units (150 pips). Configurable via Dashboard.

## Web Dashboard
- **URL**: http://127.0.0.1:8000 (configurable)
- **Features**:
  - Start/Stop parser
  - Live log monitoring (chronological order)
  - Configuration management (API keys, channels, trading filters, port)
  - View signal history

## MQL5 EA Component

### Planned Structure
```
MQL5/
├── Experts/Nguyen-N/
│   └── TelegramSignalEA.mq5
└── Include/Nguyen-N/
    ├── SignalReader.mqh    # CSV/TXT file parsing
    ├── TradeExecutor.mqh   # Order placement
    ├── RiskManager.mqh     # Daily loss monitoring
    └── PositionManager.mqh # TP1→BE logic
```

### Trading Logic
1. Check daily loss (>= 3% → stop trading)
2. Read signal file for new signals
3. If new signal: close all existing positions
4. Validate entry conditions:
   - Price in range → market entry
   - Price outside by <= 30 pips → market entry
   - Price outside by > 30 pips → ignore
5. Open 2 orders with SL/TP attached
6. When TP1 hit → move Order2 SL to breakeven

### Input Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| LotSize | 0.01 | Fixed lot size |
| MaxSlippagePips | 30 | Max slippage |
| MaxDailyLossPercent | 3.0 | Daily loss limit |
| MaxEntryDeviation | 30 | Max pips from entry range |
| SignalFilePath | signal.csv | Path to signal file |

## Export File Format

### CSV (recommended)
```csv
signal_id,symbol,direction,entry_min,entry_max,stop_loss,tp1,tp2,timestamp,status
1,XAUUSD,BUY,2350.00,2352.00,2340.00,2355.00,2360.00,2024-01-15 10:30:00,NEW
```

### TXT (alternative)
```
SIGNAL_ID=1
SYMBOL=XAUUSD
DIRECTION=BUY
ENTRY_MIN=2350.00
...
```

## Risk Management Rules

| Rule | Value | Action |
|------|-------|--------|
| Daily loss | >= 3% equity | Close all, stop until next day |
| Slippage | > 30 pips | Reject order |
| SL placement fails | - | Immediately close trade |
| Duplicate signal | - | Ignore |

## MCP Tools

При работе с этим репозиторием используй **Context7 MCP** для получения актуальной документации:

```bash
# Найти ID библиотеки
mcp-cli call plugin_context7_context7/resolve-library-id '{"libraryName": "telethon"}'

# Получить документацию
mcp-cli call plugin_context7_context7/query-docs '{"libraryId": "...", "query": "send message"}'
```

Библиотеки для проверки документации:
- **Telethon** - Telegram MTProto клиент
- **Pydantic** - валидация данных
- **Loguru** - логирование
- **SQLite3** - работа с базой данных

## Development Notes

- Python parses Telegram → MQL5 never accesses network
- Signal format may change → parser uses modular regex patterns
- Test on demo before live trading
- SQLite uses UNIQUE constraint on (channel_id, message_id) to prevent duplicates
