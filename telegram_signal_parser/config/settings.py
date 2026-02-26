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
        default="signals.sqlite3",
        description="Path to SQLite database file"
    )

    # Trading Filters
    max_sl_distance: float = Field(
        default=15.0,
        description="Maximum allowed SL distance in price units (e.g. 15.00 = 150 pips for Gold)"
    )

    # Logging
    log_level: str = Field(default="DEBUG")
    log_file: str = Field(default="./logs/parser.log")

    # Web Settings
    web_port: int = Field(default=8000, description="Web dashboard port")

    # Validators for correct parsing of comma-separated lists from .env
    @field_validator("telegram_channels", mode="before")
    @classmethod
    def parse_channels(cls, v: Any) -> List[int]:
        """Converts comma-separated string to list of integers (Channel IDs)."""
        from loguru import logger
        logger.debug(f"Validating telegram_channels: input={v} (type={type(v)})")

        raw_ids = []
        if isinstance(v, str):
            raw_ids = [item.strip() for item in v.split(",") if item.strip()]
        elif isinstance(v, (list, tuple)):
            raw_ids = [str(item).strip() for item in v]
        else:
            logger.warning(f"Unexpected type for telegram_channels: {type(v)}")
            return []

        result = []
        for rid in raw_ids:
            try:
                # Reverted auto-fix: use ID exactly as provided by user
                val = int(rid)
                result.append(val)
            except ValueError:
                logger.error(f"Invalid channel ID format: {rid}")

        logger.debug(f"Final parsed channels: {result}")
        return result

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
        """Update settings object with values from database using Pydantic validation."""
        from loguru import logger

        # Prepare data for Pydantic validation (lowercase keys)
        # Skip empty string values to avoid validation errors for numeric fields
        update_data = {}
        for key, value in db_settings.items():
            attr_name = key.lower()
            if hasattr(self, attr_name) and str(value).strip() != "":
                update_data[attr_name] = value

        if not update_data:
            return

        try:
            # Create a temporary object to trigger validation/coercion
            # This is safer than raw setattr because it handles types (str -> int, etc.)
            new_obj = self.__class__(**{**self.model_dump(), **update_data})

            # Update current object with validated data
            for attr, val in new_obj.model_dump().items():
                setattr(self, attr, val)

            logger.info("Settings successfully updated from database and validated.")
        except Exception as e:
            logger.error(f"Failed to validate settings update from DB: {e}")
            # Fallback to direct setattr if validation fails (best effort)
            for attr, val in update_data.items():
                try:
                    setattr(self, attr, val)
                except:
                    pass

    def is_fully_configured(self) -> bool:
        """Check if required Telegram credentials are provided."""
        from loguru import logger

        # Explicitly check values after potential DB update
        api_id = 0
        try:
            api_id = int(self.telegram_api_id)
        except:
            pass

        api_hash = str(self.telegram_api_hash or "").strip()
        phone = str(self.telegram_phone or "").strip()

        is_ok = (
            api_id > 0 and
            len(api_hash) > 10 and # API Hash is usually long
            len(phone) > 5
        )

        if not is_ok:
            logger.warning(f"Configuration validation failed: ID={api_id}, HashSet={bool(api_hash)}, PhoneSet={bool(phone)}")

        return is_ok


# Create global settings object
try:
    settings = Settings()
except Exception as e:
    # Rethrow for handling in main.py
    raise e
