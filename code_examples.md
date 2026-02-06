# Примеры кода: Telegram Signal Parser

Этот файл содержит все примеры кода для реализации Python-парсера сигналов из Telegram.

---

## 1. requirements.txt

```txt
# Telegram MTProto клиент
telethon>=1.36.0

# Валидация данных
pydantic>=2.5.0
pydantic-settings>=2.1.0

# Загрузка .env
python-dotenv>=1.0.0

# Логирование
loguru>=0.7.2

# Опционально: асинхронный SQLite (для высокой нагрузки)
# aiosqlite>=0.19.0
```

---

## 2. .env.example

```env
# Telegram API (получить на https://my.telegram.org)
TELEGRAM_API_ID=12345678
TELEGRAM_API_HASH=abcdef1234567890abcdef1234567890
TELEGRAM_PHONE=+1234567890

# Каналы для мониторинга (через запятую)
TELEGRAM_CHANNELS=-1001234567890,-1009876543210

# База данных
DATABASE_PATH=./data/signals.db

# Экспорт для EA
EXPORT_PATH=./mt5_signals/signal.csv
EXPORT_FORMAT=csv

# Фильтрация
FILTER_SYMBOLS=XAUUSD,GOLD

# Логирование
LOG_LEVEL=INFO
LOG_FILE=./logs/parser.log
```

---

## 3. config/settings.py

```python
"""Конфигурация приложения с Pydantic Settings."""
from pydantic_settings import BaseSettings
from pydantic import Field
from typing import List


class Settings(BaseSettings):
    """Настройки приложения из .env файла."""

    # Telegram API
    telegram_api_id: int = Field(..., description="Telegram API ID")
    telegram_api_hash: str = Field(..., description="Telegram API Hash")
    telegram_phone: str = Field(..., description="Номер телефона")
    telegram_channels: List[int] = Field(
        default_factory=list,
        description="ID каналов для мониторинга"
    )

    # База данных
    database_path: str = Field(
        default="./data/signals.db",
        description="Путь к SQLite базе"
    )

    # Экспорт
    export_path: str = Field(
        default="./mt5_signals/signal.csv",
        description="Путь к файлу экспорта для EA"
    )
    export_format: str = Field(default="csv", pattern="^(csv|txt)$")

    # Фильтрация
    filter_symbols: List[str] = Field(
        default=["XAUUSD", "GOLD"],
        description="Символы для фильтрации"
    )

    # Логирование
    log_level: str = Field(default="INFO")
    log_file: str = Field(default="./logs/parser.log")

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
```

---

## 4. database/models.py

```python
"""Pydantic модели для сигналов."""
from pydantic import BaseModel, Field, field_validator, model_validator
from typing import Optional, Literal
from datetime import datetime
from enum import Enum


class SignalDirection(str, Enum):
    BUY = "BUY"
    SELL = "SELL"


class SignalStatus(str, Enum):
    NEW = "NEW"
    SENT_TO_EA = "SENT_TO_EA"
    PROCESSED = "PROCESSED"
    EXPIRED = "EXPIRED"
    INVALID = "INVALID"
    ERROR = "ERROR"


class TradingSignal(BaseModel):
    """Модель торгового сигнала с валидацией."""

    telegram_message_id: int
    telegram_channel_id: int
    symbol: str = "XAUUSD"
    direction: SignalDirection
    entry_min: float = Field(gt=0)
    entry_max: float = Field(gt=0)
    stop_loss: float = Field(gt=0)
    take_profit_1: float = Field(gt=0)
    take_profit_2: Optional[float] = Field(default=None, gt=0)
    take_profit_3: Optional[float] = Field(default=None, gt=0)
    raw_message: str
    status: SignalStatus = SignalStatus.NEW
    parse_error: Optional[str] = None

    @field_validator('entry_max')
    @classmethod
    def entry_max_greater_than_min(cls, v, info):
        if 'entry_min' in info.data and v < info.data['entry_min']:
            # Автоматически меняем местами
            return info.data['entry_min']
        return v

    @model_validator(mode='after')
    def validate_trading_levels(self):
        """Проверка логики торговых уровней."""
        if self.direction == SignalDirection.BUY:
            # Для BUY: SL < Entry < TP1 < TP2
            if self.stop_loss >= self.entry_min:
                raise ValueError(
                    f"BUY: SL ({self.stop_loss}) должен быть ниже Entry ({self.entry_min})"
                )
            if self.take_profit_1 <= self.entry_max:
                raise ValueError(
                    f"BUY: TP1 ({self.take_profit_1}) должен быть выше Entry ({self.entry_max})"
                )
            if self.take_profit_2 and self.take_profit_2 <= self.take_profit_1:
                raise ValueError(
                    f"BUY: TP2 ({self.take_profit_2}) должен быть выше TP1 ({self.take_profit_1})"
                )
        else:
            # Для SELL: SL > Entry > TP1 > TP2
            if self.stop_loss <= self.entry_max:
                raise ValueError(
                    f"SELL: SL ({self.stop_loss}) должен быть выше Entry ({self.entry_max})"
                )
            if self.take_profit_1 >= self.entry_min:
                raise ValueError(
                    f"SELL: TP1 ({self.take_profit_1}) должен быть ниже Entry ({self.entry_min})"
                )
            if self.take_profit_2 and self.take_profit_2 >= self.take_profit_1:
                raise ValueError(
                    f"SELL: TP2 ({self.take_profit_2}) должен быть ниже TP1 ({self.take_profit_1})"
                )

        return self

    def to_db_dict(self) -> dict:
        """Конвертация в словарь для SQLite."""
        return {
            "telegram_message_id": self.telegram_message_id,
            "telegram_channel_id": self.telegram_channel_id,
            "symbol": self.symbol,
            "direction": self.direction.value,
            "entry_min": self.entry_min,
            "entry_max": self.entry_max,
            "stop_loss": self.stop_loss,
            "take_profit_1": self.take_profit_1,
            "take_profit_2": self.take_profit_2,
            "take_profit_3": self.take_profit_3,
            "raw_message": self.raw_message,
            "status": self.status.value,
            "parse_error": self.parse_error,
        }
```

---

## 5. database/connection.py

```python
"""SQLite подключение и операции с базой данных."""
import sqlite3
from pathlib import Path
from typing import Optional, Dict, Any, List
from loguru import logger
from datetime import datetime


class Database:
    """Менеджер SQLite базы данных."""

    def __init__(self, db_path: str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn: Optional[sqlite3.Connection] = None

    def _get_connection(self) -> sqlite3.Connection:
        """Получить соединение с БД."""
        if self._conn is None:
            self._conn = sqlite3.connect(
                str(self.db_path),
                check_same_thread=False
            )
            self._conn.row_factory = sqlite3.Row
        return self._conn

    def init_tables(self) -> None:
        """Инициализация таблиц БД."""
        conn = self._get_connection()
        cursor = conn.cursor()

        # Таблица сигналов
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                telegram_message_id INTEGER NOT NULL,
                telegram_channel_id INTEGER NOT NULL,
                symbol TEXT NOT NULL DEFAULT 'XAUUSD',
                direction TEXT NOT NULL CHECK (direction IN ('BUY', 'SELL')),
                entry_min REAL NOT NULL,
                entry_max REAL NOT NULL,
                stop_loss REAL NOT NULL,
                take_profit_1 REAL NOT NULL,
                take_profit_2 REAL,
                take_profit_3 REAL,
                status TEXT NOT NULL DEFAULT 'NEW'
                    CHECK (status IN ('NEW', 'SENT_TO_EA', 'PROCESSED', 'EXPIRED', 'INVALID', 'ERROR')),
                raw_message TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                processed_at TIMESTAMP,
                parse_error TEXT,
                UNIQUE(telegram_channel_id, telegram_message_id)
            )
        """)

        # Индексы
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_signals_status ON signals(status)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_signals_created ON signals(created_at)
        """)

        # Таблица лога экспорта
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS signal_export_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                signal_id INTEGER NOT NULL,
                export_file TEXT NOT NULL,
                exported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (signal_id) REFERENCES signals(id)
            )
        """)

        # Таблица каналов
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS channels (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                telegram_id INTEGER NOT NULL UNIQUE,
                name TEXT NOT NULL,
                is_active BOOLEAN DEFAULT 1,
                priority INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.commit()
        logger.info(f"База данных инициализирована: {self.db_path}")

    async def save_signal(self, **kwargs) -> int:
        """Сохранить сигнал в БД."""
        conn = self._get_connection()
        cursor = conn.cursor()

        columns = ', '.join(kwargs.keys())
        placeholders = ', '.join(['?' for _ in kwargs])
        values = tuple(kwargs.values())

        try:
            cursor.execute(f"""
                INSERT INTO signals ({columns})
                VALUES ({placeholders})
            """, values)
            conn.commit()
            signal_id = cursor.lastrowid
            logger.info(f"Сигнал сохранён: ID={signal_id}")
            return signal_id
        except sqlite3.IntegrityError as e:
            logger.warning(f"Дубликат сигнала: {e}")
            raise

    async def get_signal(self, signal_id: int) -> Optional[Dict[str, Any]]:
        """Получить сигнал по ID."""
        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT * FROM signals WHERE id = ?", (signal_id,))
        row = cursor.fetchone()

        if row:
            return dict(row)
        return None

    async def get_latest_new_signal(self) -> Optional[Dict[str, Any]]:
        """Получить последний новый сигнал."""
        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT * FROM signals
            WHERE status = 'NEW'
            ORDER BY created_at DESC
            LIMIT 1
        """)
        row = cursor.fetchone()

        if row:
            return dict(row)
        return None

    async def update_signal_status(self, signal_id: int, status: str) -> None:
        """Обновить статус сигнала."""
        conn = self._get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE signals
            SET status = ?, updated_at = ?
            WHERE id = ?
        """, (status, datetime.now(), signal_id))
        conn.commit()
        logger.debug(f"Статус сигнала {signal_id} обновлён: {status}")

    def close(self) -> None:
        """Закрыть соединение."""
        if self._conn:
            self._conn.close()
            self._conn = None
```

---

## 6. parser/signal_parser.py

```python
"""Парсер сигналов из текста Telegram сообщений."""
import re
from typing import Optional, Tuple, List
from dataclasses import dataclass
from loguru import logger


@dataclass
class ParsedSignal:
    """Результат парсинга сигнала."""
    direction: str
    entry_min: float
    entry_max: float
    stop_loss: float
    take_profits: List[float]
    symbol: str = "XAUUSD"


class SignalParser:
    """Парсер торговых сигналов с поддержкой разных форматов."""

    # Паттерны для извлечения данных
    PATTERNS = {
        # Направление: BUY/SELL/LONG/SHORT
        'direction': re.compile(
            r'\b(BUY|SELL|LONG|SHORT)\b',
            re.IGNORECASE
        ),

        # Диапазон входа: "2350 to 2352", "2350-2352", "Entry: 2350 - 2352"
        'entry_range': re.compile(
            r'(?:entry|вход)?[:\s]*(\d+(?:\.\d+)?)\s*(?:to|-|–|—)\s*(\d+(?:\.\d+)?)',
            re.IGNORECASE
        ),

        # Одиночный вход: "Entry: 2350" или "@ 2350"
        'entry_single': re.compile(
            r'(?:entry|@|вход)[:\s]*(\d+(?:\.\d+)?)',
            re.IGNORECASE
        ),

        # Stop Loss: "SL: 2340", "Stop Loss: 2340", "SL 2340"
        'stop_loss': re.compile(
            r'(?:sl|stop\s*loss|стоп)[:\s]*(\d+(?:\.\d+)?)',
            re.IGNORECASE
        ),

        # Take Profits: "TP1: 2355", "TP 2360", "Take Profit: 2355"
        'take_profit': re.compile(
            r'(?:tp\s*\d*|take\s*profit\s*\d*|тейк)[:\s]*(\d+(?:\.\d+)?)',
            re.IGNORECASE
        ),

        # Символ: XAUUSD, GOLD, XAU/USD
        'symbol': re.compile(
            r'\b(XAUUSD|XAU/?USD|GOLD)\b',
            re.IGNORECASE
        ),
    }

    def parse(self, text: str) -> Optional[ParsedSignal]:
        """
        Парсит текст сообщения и извлекает торговый сигнал.

        Args:
            text: Текст сообщения из Telegram

        Returns:
            ParsedSignal если успешно, None если не удалось распарсить
        """
        try:
            # 1. Извлекаем направление
            direction = self._extract_direction(text)
            if not direction:
                logger.debug(f"Направление не найдено: {text[:50]}...")
                return None

            # 2. Извлекаем диапазон входа
            entry_min, entry_max = self._extract_entry_range(text)
            if entry_min is None:
                logger.debug(f"Диапазон входа не найден: {text[:50]}...")
                return None

            # 3. Извлекаем Stop Loss
            stop_loss = self._extract_stop_loss(text)
            if stop_loss is None:
                logger.debug(f"Stop Loss не найден: {text[:50]}...")
                return None

            # 4. Извлекаем Take Profits
            take_profits = self._extract_take_profits(text)
            if not take_profits:
                logger.debug(f"Take Profits не найдены: {text[:50]}...")
                return None

            # 5. Извлекаем символ (опционально)
            symbol = self._extract_symbol(text) or "XAUUSD"

            return ParsedSignal(
                direction=direction,
                entry_min=entry_min,
                entry_max=entry_max,
                stop_loss=stop_loss,
                take_profits=take_profits,
                symbol=symbol
            )

        except Exception as e:
            logger.error(f"Ошибка парсинга: {e}, текст: {text[:100]}...")
            return None

    def _extract_direction(self, text: str) -> Optional[str]:
        """Извлекает направление сделки."""
        match = self.PATTERNS['direction'].search(text)
        if match:
            direction = match.group(1).upper()
            # Нормализация: LONG -> BUY, SHORT -> SELL
            return "BUY" if direction in ("BUY", "LONG") else "SELL"
        return None

    def _extract_entry_range(self, text: str) -> Tuple[Optional[float], Optional[float]]:
        """Извлекает диапазон входа."""
        # Сначала пробуем диапазон
        match = self.PATTERNS['entry_range'].search(text)
        if match:
            entry1 = float(match.group(1))
            entry2 = float(match.group(2))
            return (min(entry1, entry2), max(entry1, entry2))

        # Если диапазон не найден, пробуем одиночное значение
        match = self.PATTERNS['entry_single'].search(text)
        if match:
            entry = float(match.group(1))
            return (entry, entry)

        return (None, None)

    def _extract_stop_loss(self, text: str) -> Optional[float]:
        """Извлекает уровень Stop Loss."""
        match = self.PATTERNS['stop_loss'].search(text)
        return float(match.group(1)) if match else None

    def _extract_take_profits(self, text: str) -> List[float]:
        """Извлекает все уровни Take Profit."""
        matches = self.PATTERNS['take_profit'].findall(text)
        return [float(tp) for tp in matches] if matches else []

    def _extract_symbol(self, text: str) -> Optional[str]:
        """Извлекает торговый символ."""
        match = self.PATTERNS['symbol'].search(text)
        if match:
            symbol = match.group(1).upper().replace("/", "")
            return "XAUUSD" if symbol in ("XAUUSD", "GOLD") else symbol
        return None
```

---

## 7. telegram/client.py

```python
"""Telethon клиент для чтения сообщений из Telegram."""
import asyncio
from telethon import TelegramClient, events
from telethon.tl.types import Channel, Chat
from loguru import logger

from config.settings import settings
from parser.signal_parser import SignalParser
from database.connection import Database


class TelegramSignalClient:
    """Клиент для мониторинга Telegram каналов."""

    def __init__(self):
        self.client = TelegramClient(
            'signal_session',  # Имя файла сессии
            settings.telegram_api_id,
            settings.telegram_api_hash
        )
        self.parser = SignalParser()
        self.db = Database(settings.database_path)
        self.monitored_channels = set(settings.telegram_channels)

    async def start(self):
        """Запуск клиента и начало мониторинга."""
        await self.client.start(phone=settings.telegram_phone)
        logger.info("Telegram клиент запущен")

        # Инициализация БД
        self.db.init_tables()

        # Регистрация обработчика новых сообщений
        self.client.add_event_handler(
            self._on_new_message,
            events.NewMessage(chats=list(self.monitored_channels))
        )

        logger.info(f"Мониторинг каналов: {self.monitored_channels}")

        # Запуск бесконечного цикла
        await self.client.run_until_disconnected()

    async def _on_new_message(self, event):
        """Обработчик новых сообщений."""
        message = event.message
        text = message.text or ""

        # Пропускаем пустые сообщения
        if not text.strip():
            return

        # Проверяем, содержит ли сообщение ключевые слова
        if not self._is_potential_signal(text):
            return

        logger.info(f"Потенциальный сигнал обнаружен: {text[:100]}...")

        try:
            # Парсим сигнал
            parsed = self.parser.parse(text)

            if parsed:
                # Сохраняем в БД
                signal_id = await self.db.save_signal(
                    telegram_message_id=message.id,
                    telegram_channel_id=event.chat_id,
                    symbol=parsed.symbol,
                    direction=parsed.direction,
                    entry_min=parsed.entry_min,
                    entry_max=parsed.entry_max,
                    stop_loss=parsed.stop_loss,
                    take_profit_1=parsed.take_profits[0],
                    take_profit_2=parsed.take_profits[1] if len(parsed.take_profits) > 1 else None,
                    take_profit_3=parsed.take_profits[2] if len(parsed.take_profits) > 2 else None,
                    raw_message=text
                )

                logger.success(f"Сигнал сохранён: ID={signal_id}, {parsed.direction} {parsed.symbol}")

                # Экспорт для EA
                await self._export_for_ea(signal_id)
            else:
                logger.warning(f"Не удалось распарсить сигнал: {text[:100]}...")

        except Exception as e:
            logger.error(f"Ошибка обработки сообщения: {e}")

    def _is_potential_signal(self, text: str) -> bool:
        """Быстрая проверка, может ли это быть сигналом."""
        text_upper = text.upper()

        # Должен содержать символ
        has_symbol = any(s in text_upper for s in settings.filter_symbols)

        # Должен содержать направление
        has_direction = any(d in text_upper for d in ["BUY", "SELL", "LONG", "SHORT"])

        return has_symbol and has_direction

    async def _export_for_ea(self, signal_id: int):
        """Экспорт сигнала в файл для EA."""
        from export.csv_exporter import export_signal_to_csv

        signal = await self.db.get_signal(signal_id)
        if signal:
            export_signal_to_csv(signal, settings.export_path)
            await self.db.update_signal_status(signal_id, "SENT_TO_EA")
            logger.info(f"Сигнал {signal_id} экспортирован в {settings.export_path}")


async def main():
    """Точка входа."""
    client = TelegramSignalClient()
    await client.start()


if __name__ == "__main__":
    asyncio.run(main())
```

---

## 8. export/csv_exporter.py

```python
"""Экспорт сигналов в CSV для EA."""
import csv
from pathlib import Path
from datetime import datetime
from typing import Dict, Any
from loguru import logger


def export_signal_to_csv(signal: Dict[str, Any], filepath: str) -> None:
    """
    Экспортирует сигнал в CSV файл для чтения EA.

    Формат CSV:
    signal_id,symbol,direction,entry_min,entry_max,stop_loss,tp1,tp2,timestamp,status
    """
    path = Path(filepath)
    path.parent.mkdir(parents=True, exist_ok=True)

    row = {
        'signal_id': signal['id'],
        'symbol': signal['symbol'],
        'direction': signal['direction'],
        'entry_min': f"{signal['entry_min']:.2f}",
        'entry_max': f"{signal['entry_max']:.2f}",
        'stop_loss': f"{signal['stop_loss']:.2f}",
        'tp1': f"{signal['take_profit_1']:.2f}",
        'tp2': f"{signal['take_profit_2']:.2f}" if signal.get('take_profit_2') else "",
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'status': 'NEW'
    }

    fieldnames = list(row.keys())

    # Перезаписываем файл (EA читает только последний сигнал)
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerow(row)

    logger.debug(f"Записан сигнал в {filepath}: {row}")


def export_signal_to_txt(signal: Dict[str, Any], filepath: str) -> None:
    """
    Альтернативный формат: key=value для простого парсинга в MQL5.
    """
    path = Path(filepath)
    path.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        f"SIGNAL_ID={signal['id']}",
        f"SYMBOL={signal['symbol']}",
        f"DIRECTION={signal['direction']}",
        f"ENTRY_MIN={signal['entry_min']:.2f}",
        f"ENTRY_MAX={signal['entry_max']:.2f}",
        f"STOP_LOSS={signal['stop_loss']:.2f}",
        f"TP1={signal['take_profit_1']:.2f}",
        f"TP2={signal['take_profit_2']:.2f}" if signal.get('take_profit_2') else "TP2=",
        f"TIMESTAMP={datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"STATUS=NEW"
    ]

    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    logger.debug(f"Записан сигнал в {filepath}")
```

---

## 9. main.py

```python
"""Точка входа приложения."""
import asyncio
import sys
from loguru import logger

from config.settings import settings
from telegram.client import TelegramSignalClient


def setup_logging():
    """Настройка логирования."""
    logger.remove()

    # Консоль
    logger.add(
        sys.stdout,
        level=settings.log_level,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
               "<level>{level: <8}</level> | "
               "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
               "<level>{message}</level>"
    )

    # Файл
    logger.add(
        settings.log_file,
        level=settings.log_level,
        rotation="10 MB",
        retention="7 days",
        compression="zip"
    )


async def main():
    """Главная функция."""
    setup_logging()

    logger.info("=" * 50)
    logger.info("Telegram Signal Parser")
    logger.info("=" * 50)
    logger.info(f"Database: {settings.database_path}")
    logger.info(f"Export: {settings.export_path}")
    logger.info(f"Channels: {settings.telegram_channels}")

    client = TelegramSignalClient()

    try:
        await client.start()
    except KeyboardInterrupt:
        logger.info("Получен сигнал остановки")
    except Exception as e:
        logger.exception(f"Критическая ошибка: {e}")
    finally:
        client.db.close()
        logger.info("Приложение остановлено")


if __name__ == "__main__":
    asyncio.run(main())
```

---

## 10. tests/test_parser.py

```python
"""Тесты для парсера сигналов."""
import pytest
from parser.signal_parser import SignalParser


@pytest.fixture
def parser():
    return SignalParser()


class TestSignalParser:
    """Тесты парсера сигналов."""

    def test_parse_basic_buy_signal(self, parser):
        """Тест парсинга базового BUY сигнала."""
        text = """
        XAUUSD BUY
        Entry: 2350 to 2352
        Stop Loss (SL): 2340
        Take Profit (TP): TP1: 2355
        TP2: 2360
        """

        result = parser.parse(text)

        assert result is not None
        assert result.direction == "BUY"
        assert result.entry_min == 2350.0
        assert result.entry_max == 2352.0
        assert result.stop_loss == 2340.0
        assert result.take_profits == [2355.0, 2360.0]
        assert result.symbol == "XAUUSD"

    def test_parse_sell_signal(self, parser):
        """Тест парсинга SELL сигнала."""
        text = """
        GOLD SELL
        Entry: 2400 - 2398
        SL: 2410
        TP1: 2390
        TP2: 2380
        """

        result = parser.parse(text)

        assert result is not None
        assert result.direction == "SELL"
        assert result.stop_loss == 2410.0
        assert result.take_profits[0] == 2390.0

    def test_parse_single_entry(self, parser):
        """Тест парсинга одиночного входа."""
        text = """
        XAUUSD BUY @ 2350
        SL: 2340
        TP: 2360
        """

        result = parser.parse(text)

        assert result is not None
        assert result.entry_min == 2350.0
        assert result.entry_max == 2350.0

    def test_parse_long_short(self, parser):
        """Тест парсинга LONG/SHORT."""
        text = "GOLD LONG Entry: 2350 SL: 2340 TP: 2360"
        result = parser.parse(text)
        assert result.direction == "BUY"

        text = "GOLD SHORT Entry: 2350 SL: 2360 TP: 2340"
        result = parser.parse(text)
        assert result.direction == "SELL"

    def test_invalid_signal_no_direction(self, parser):
        """Тест: нет направления."""
        text = "XAUUSD Entry: 2350 SL: 2340 TP: 2360"
        result = parser.parse(text)
        assert result is None

    def test_invalid_signal_no_symbol(self, parser):
        """Тест: нет символа (не влияет на парсинг)."""
        text = "BUY Entry: 2350 SL: 2340 TP: 2360"
        result = parser.parse(text)
        # Парсер всё равно вернёт результат с дефолтным символом
        if result:
            assert result.symbol == "XAUUSD"

    def test_invalid_signal_no_sl(self, parser):
        """Тест: нет Stop Loss."""
        text = "XAUUSD BUY Entry: 2350 TP: 2360"
        result = parser.parse(text)
        assert result is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
```

---

## 11. Структура проекта

```
telegram_signal_parser/
│
├── .env                      # Секреты (НЕ в git!)
├── .env.example              # Пример конфигурации
├── requirements.txt          # Зависимости
├── README.md                 # Документация
│
├── config/
│   ├── __init__.py
│   └── settings.py           # Pydantic Settings
│
├── database/
│   ├── __init__.py
│   ├── connection.py         # SQLite подключение
│   └── models.py             # Pydantic модели
│
├── parser/
│   ├── __init__.py
│   └── signal_parser.py      # Regex парсинг сигналов
│
├── telegram/
│   ├── __init__.py
│   └── client.py             # Telethon клиент
│
├── export/
│   ├── __init__.py
│   └── csv_exporter.py       # Экспорт в CSV для EA
│
├── main.py                   # Точка входа
│
└── tests/
    └── test_parser.py        # Тесты парсера
```

---

## 12. SQL-схема базы данных

```sql
-- Таблица сигналов
CREATE TABLE signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    telegram_message_id INTEGER NOT NULL,
    telegram_channel_id INTEGER NOT NULL,
    symbol TEXT NOT NULL DEFAULT 'XAUUSD',
    direction TEXT NOT NULL CHECK (direction IN ('BUY', 'SELL')),
    entry_min REAL NOT NULL,
    entry_max REAL NOT NULL,
    stop_loss REAL NOT NULL,
    take_profit_1 REAL NOT NULL,
    take_profit_2 REAL,
    take_profit_3 REAL,
    status TEXT NOT NULL DEFAULT 'NEW'
        CHECK (status IN ('NEW', 'SENT_TO_EA', 'PROCESSED', 'EXPIRED', 'INVALID', 'ERROR')),
    raw_message TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    parse_error TEXT,
    UNIQUE(telegram_channel_id, telegram_message_id)
);

-- Индексы
CREATE INDEX idx_signals_status ON signals(status);
CREATE INDEX idx_signals_created ON signals(created_at);
CREATE INDEX idx_signals_symbol ON signals(symbol);

-- Лог экспорта
CREATE TABLE signal_export_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_id INTEGER NOT NULL,
    export_file TEXT NOT NULL,
    exported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (signal_id) REFERENCES signals(id)
);

-- Каналы
CREATE TABLE channels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    telegram_id INTEGER NOT NULL UNIQUE,
    name TEXT NOT NULL,
    is_active BOOLEAN DEFAULT 1,
    priority INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Настройки
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```
