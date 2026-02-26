import sqlite3
import time
from datetime import datetime

DB_PATH = "mql5/Files/telegram_signals.sqlite3" # Путь, где MT5 будет искать базу

def inject_test_signal():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # Создаем таблицу, если её нет (для автономного теста)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                telegram_message_id INTEGER,
                telegram_channel_id INTEGER,
                symbol TEXT,
                direction TEXT,
                entry_min REAL,
                entry_max REAL,
                stop_loss REAL,
                take_profit_1 REAL,
                take_profit_2 REAL,
                take_profit_3 REAL,
                status TEXT,
                raw_message TEXT,
                content_hash TEXT,
                created_at DATETIME,
                updated_at DATETIME
            )
        ''')

        # Тестовый сигнал на BUY (Золото)
        # Подберите цены под текущий рынок!
        current_price = 2650.0
        signal = {
            "msg_id": 1001,
            "chan_id": -100123456789,
            "symbol": "XAUUSD",
            "dir": "BUY",
            "entry_min": current_price - 0.5,
            "entry_max": current_price + 0.5,
            "sl": current_price - 5.0,
            "tp1": current_price + 2.0,
            "tp2": current_price + 5.0,
            "status": "PROCESS"
        }

        cursor.execute('''
            INSERT INTO signals (
                telegram_message_id, telegram_channel_id, symbol, direction,
                entry_min, entry_max, stop_loss, take_profit_1, take_profit_2,
                status, raw_message, content_hash, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            signal["msg_id"], signal["chan_id"], signal["symbol"], signal["dir"],
            signal["entry_min"], signal["entry_max"], signal["sl"], signal["tp1"], signal["tp2"],
            signal["status"], "Test message", "hash_123", datetime.now(), datetime.now()
        ))

        conn.commit()
        print(f"✅ Тестовый сигнал ID {cursor.lastrowid} добавлен в базу.")
        conn.close()
    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    inject_test_signal()
