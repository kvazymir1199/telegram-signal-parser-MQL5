"""Data models module for SQLAlchemy and Pydantic schemas."""
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import Integer, String, Float, DateTime, ForeignKey, Boolean, CheckConstraint, UniqueConstraint, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


# --- Base Enums ---

class SignalDirection(str, Enum):
    """Trading signal directions."""
    BUY = "BUY"
    SELL = "SELL"


class SignalStatus(str, Enum):
    """
    Signal processing statuses.
    """
    PROCESS = "PROCESS"   # New signal to be processed
    MODIFY = "MODIFY"     # Signal prices updated
    DONE = "DONE"         # Completed processing this signal
    INVALID = "INVALID"   # Internal status for logically incorrect signals
    ERROR = "ERROR"       # Error during processing
    EXPIRED = "EXPIRED"   # Signal expired (60-minute validity window exceeded)


# --- SQLAlchemy Models (Database) ---

class Base(DeclarativeBase):
    """Base declarative class for SQLAlchemy models."""
    pass


class Signal(Base):
    """Signal table model for SQLite."""
    __tablename__ = "signals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    telegram_message_id: Mapped[int] = mapped_column(Integer, nullable=False)
    telegram_channel_id: Mapped[int] = mapped_column(Integer, nullable=False)
    symbol: Mapped[str] = mapped_column(String, nullable=False, default="XAUUSD")
    direction: Mapped[str] = mapped_column(String, nullable=False)
    entry_min: Mapped[float] = mapped_column(Float, nullable=False)
    entry_max: Mapped[float] = mapped_column(Float, nullable=False)
    stop_loss: Mapped[float] = mapped_column(Float, nullable=False)
    take_profit_1: Mapped[float] = mapped_column(Float, nullable=False)
    take_profit_2: Mapped[Optional[float]] = mapped_column(Float)
    take_profit_3: Mapped[Optional[float]] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String, nullable=False, default=SignalStatus.PROCESS.value)
    raw_message: Mapped[str] = mapped_column(String, nullable=False)

    # Hash of content to detect duplicates and changes
    content_hash: Mapped[str] = mapped_column(String, nullable=False, index=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    parse_error: Mapped[Optional[str]] = mapped_column(String)

    __table_args__ = (
        UniqueConstraint('telegram_channel_id', 'telegram_message_id', name='uix_channel_message'),
        CheckConstraint("direction IN ('BUY', 'SELL')", name='check_direction'),
        CheckConstraint(
            "status IN ('PROCESS', 'MODIFY', 'DONE', 'INVALID', 'ERROR', 'EXPIRED')",
            name='check_status'
        ),
    )

    def __repr__(self) -> str:
        return f"<Signal(id={self.id}, sym={self.symbol}, dir={self.direction}, status={self.status})>"


class Channel(Base):
    """Configuration table for monitored Telegram channels/groups."""
    __tablename__ = "channels"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    telegram_id: Mapped[int] = mapped_column(Integer, nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    priority: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Setting(Base):
    """General application settings stored as key-value pairs."""
    __tablename__ = "settings"

    key: Mapped[str] = mapped_column(String, primary_key=True)
    value: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def __repr__(self) -> str:
        return f"<Setting(key={self.key}, value={self.value})>"


# --- Pydantic Schemas (Validation) ---

class TradingSignalSchema(BaseModel):
    """Schema for strict validation of trading signal parameters."""
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
    content_hash: str
    status: SignalStatus = SignalStatus.PROCESS
    parse_error: Optional[str] = None

    @field_validator('entry_max')
    @classmethod
    def entry_max_greater_than_min(cls, v: float, info) -> float:
        """Ensures entry_max is not less than entry_min."""
        if 'entry_min' in info.data and v < info.data['entry_min']:
            return info.data['entry_min']
        return v

    @model_validator(mode='after')
    def validate_trading_levels(self) -> 'TradingSignalSchema':
        """Validates logical correctness of SL and TP levels."""
        from config.settings import settings
        max_sl = float(settings.max_sl_distance)

        if self.direction == SignalDirection.BUY:
            if self.stop_loss >= self.entry_min:
                raise ValueError(f"BUY: SL ({self.stop_loss}) must be below Entry ({self.entry_min})")

            # SL Distance Check
            sl_distance = self.entry_min - self.stop_loss
            if sl_distance > max_sl:
                raise ValueError(f"BUY: SL distance ({sl_distance:.2f}) exceeds maximum allowed ({max_sl:.2f})")

            if self.take_profit_1 <= self.entry_max:
                raise ValueError(f"BUY: TP1 ({self.take_profit_1}) must be above Entry ({self.entry_max})")
            if self.take_profit_2 and self.take_profit_2 <= self.take_profit_1:
                raise ValueError(f"BUY: TP2 ({self.take_profit_2}) must be above TP1 ({self.take_profit_1})")
            if self.take_profit_3 and self.take_profit_2 and self.take_profit_3 <= self.take_profit_2:
                raise ValueError(f"BUY: TP3 ({self.take_profit_3}) must be above TP2 ({self.take_profit_2})")
        else:
            if self.stop_loss <= self.entry_max:
                raise ValueError(f"SELL: SL ({self.stop_loss}) must be above Entry ({self.entry_max})")

            # SL Distance Check
            sl_distance = self.stop_loss - self.entry_max
            if sl_distance > max_sl:
                raise ValueError(f"SELL: SL distance ({sl_distance:.2f}) exceeds maximum allowed ({max_sl:.2f})")

            if self.take_profit_1 >= self.entry_min:
                raise ValueError(f"SELL: TP1 ({self.take_profit_1}) must be below Entry ({self.entry_min})")
            if self.take_profit_2 and self.take_profit_2 >= self.take_profit_1:
                raise ValueError(f"SELL: TP2 ({self.take_profit_2}) must be below TP1 ({self.take_profit_1})")
            if self.take_profit_3 and self.take_profit_2 and self.take_profit_3 >= self.take_profit_2:
                raise ValueError(f"SELL: TP3 ({self.take_profit_3}) must be below TP2 ({self.take_profit_2})")
        return self
