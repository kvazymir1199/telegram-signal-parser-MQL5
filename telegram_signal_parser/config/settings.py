"""Application configuration module using Pydantic Settings."""
import os
from pathlib import Path
from typing import List, Union, Any, Dict

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


# Define base project directory (where .env is located)
BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    """Application settings loaded from .env file or environment variables."""

    # Telegram API
    telegram_api_id: int = Field(default=0, description="Telegram API ID")
    telegram_api_hash: str = Field(default="", description="Telegram API Hash")
    telegram_phone: str = Field(default="", description="Phone number in international format (+...)")

    # Use Any for raw data from .env to avoid automatic JSON decoding by Pydantic
    telegram_channels: Any = Field(
        default_factory=list,
        description="List of channel IDs to monitor"
    )
    filter_symbols: Any = Field(
        default_factory=lambda: ["XAUUSD", "GOLD"],
        description="Keywords for symbol filtering"
    )

    # Database
    database_path: str = Field(
        default="./data/signals.db",
        description="Path to SQLite database file"
    )

    # Export
    export_path: str = Field(
        default="./mt5_signals/signals.csv",
        description="Path to export CSV file for MT5"
    )

    # Trading Filters
    max_sl_distance: float = Field(
        default=15.0,
        description="Maximum allowed SL distance in price units (e.g. 15.00 = 150 pips for Gold)"
    )

    # Logging
    log_level: str = Field(default="INFO")
    log_file: str = Field(default="./logs/parser.log")

    # Validators for correct parsing of comma-separated lists from .env
    @field_validator("telegram_channels", mode="before")
    @classmethod
    def parse_channels(cls, v: Any) -> List[int]:
        """Converts comma-separated string to list of integers (Channel IDs)."""
        if isinstance(v, str):
            return [int(item.strip()) for item in v.split(",") if item.strip()]
        if isinstance(v, (list, tuple)):
            return [int(item) for item in v]
        return []

    @field_validator("filter_symbols", mode="before")
    @classmethod
    def parse_symbols(cls, v: Any) -> List[str]:
        """Converts comma-separated string to list of upper-case strings (Symbols)."""
        if isinstance(v, str):
            return [item.strip().upper() for item in v.split(",") if item.strip()]
        if isinstance(v, (list, tuple)):
            return [str(item).upper() for item in v]
        return ["XAUUSD", "GOLD"]

    # Pydantic configuration settings
    model_config = SettingsConfigDict(
        env_file=str(BASE_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        validate_assignment=True
    )

    def update_from_db(self, db_settings: Dict[str, Any]):
        """Update settings object with values from database."""
        for key, value in db_settings.items():
            # Match DB keys (upper) to class attributes (lower)
            attr_name = key.lower()
            if hasattr(self, attr_name):
                setattr(self, attr_name, value)

    def is_fully_configured(self) -> bool:
        """Check if required Telegram credentials are provided."""
        return (
            self.telegram_api_id > 0 and
            len(self.telegram_api_hash) > 5 and
            len(self.telegram_phone) > 5
        )


# Create global settings object
try:
    settings = Settings()
except Exception as e:
    # Rethrow for handling in main.py
    raise e
