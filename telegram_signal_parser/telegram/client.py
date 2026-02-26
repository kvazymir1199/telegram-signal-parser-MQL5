"""Telegram client module for channel monitoring and database-driven signaling."""
import asyncio
from datetime import datetime
from typing import Set, Optional, Dict, Any

from telethon import TelegramClient, events
from loguru import logger

from config.settings import settings
from parser.signal_parser import SignalParser, ParsedSignal
from database.connection import DatabaseManager
from database.models import TradingSignalSchema, SignalStatus, Signal


class TelegramSignalClient:
    """Client for monitoring Telegram channels and saving signals to the database."""

    def __init__(self):
        """Initialize client and database manager."""
        self.client = TelegramClient(
            'signal_session',
            settings.telegram_api_id,
            settings.telegram_api_hash,
            connection_retries=None,
            auto_reconnect=True
        )
        self.parser = SignalParser(allowed_symbols=settings.filter_symbols)
        self.db = DatabaseManager(settings.database_path)
        self.monitored_channels = set(settings.telegram_channels)
        logger.debug(f"Initialized TelegramSignalClient with channels: {self.monitored_channels}")

    async def start(self) -> None:
        """Start client and begin listening to channels."""
        await self.client.start(phone=settings.telegram_phone)
        logger.info("Telegram client successfully authorized and started")

        self.db.init_tables()

        # Handler for New Messages
        logger.debug(f"Registering NewMessage handler for chats: {list(self.monitored_channels)}")
        self.client.add_event_handler(
            self._on_new_message,
            events.NewMessage(chats=list(self.monitored_channels))
        )

        # Handler for Edited Messages
        self.client.add_event_handler(
            self._on_message_edited,
            events.MessageEdited(chats=list(self.monitored_channels))
        )

        logger.info(f"Monitoring started for {len(self.monitored_channels)} channels")
        await self.client.run_until_disconnected()

    async def _on_new_message(self, event: events.NewMessage.Event) -> None:
        """Handler for new messages."""
        await self._process_event_safely(event, is_edit=False)

    async def _on_message_edited(self, event: events.MessageEdited.Event) -> None:
        """Handler for edited messages."""
        await self._process_event_safely(event, is_edit=True)

    async def _process_event_safely(self, event: Any, is_edit: bool) -> None:
        """Wrapper for safe message processing with unified error logging."""
        message = event.message
        text = message.text or ""

        # Log EVERY message from monitored channels for debugging
        logger.debug(f"Received message from chat {event.chat_id}: {text[:50]}...")

        if not text.strip():
            return

        # Check if it looks like a signal before deep parsing
        if not self._is_potential_signal(text):
            logger.debug(f"Message {message.id} from {event.chat_id} ignored: not a potential signal")
            return

        logger.info(f"--- Processing {'Edit' if is_edit else 'New Message'} ---")
        logger.debug(f"Channel: {event.chat_id}, Msg ID: {message.id}")

        try:
            await self._process_signal(message, event.chat_id, is_edit)
        except Exception as e:
            logger.error(f"Error processing message {message.id}: {e}")

    async def _process_signal(self, message: Any, chat_id: int, is_edit: bool) -> None:
        """Unified signal processing pipeline."""
        text = message.text or ""

        # 1. Parsing and Price Adjustment
        parsed: Optional[ParsedSignal] = self.parser.parse(text)
        if not parsed:
            logger.debug(f"Message {message.id} ignored (not XAUUSD or parsing failed)")
            return

        # 2. Content Hashing for Deduplication/Change tracking
        content_hash = parsed.generate_hash()

        # 3. Duplicate Check for New Messages (Ignore if same content within 5 seconds)
        if not is_edit:
            latest = self.db.get_latest_signal_by_hash(content_hash)
            if latest and (datetime.utcnow() - latest.created_at).total_seconds() < 5:
                logger.warning(f"Ignoring duplicate signal received within 5s window (Msg ID: {message.id})")
                return

        # 4. Handle Edits vs New Messages
        existing_signal = self.db.get_signal_by_remote_id(chat_id, message.id)

        if is_edit and existing_signal:
            # Check if content actually changed
            if existing_signal.content_hash == content_hash:
                logger.debug(f"Message {message.id} edited but prices remain the same. Ignoring.")
                return

            # Validate the new data before updating
            schema = self._create_signal_schema(message, chat_id, parsed, content_hash, SignalStatus.MODIFY)
            if not schema:
                return

            # Update existing signal to MODIFY status
            update_data = schema.model_dump(exclude={'status'})
            update_data["status"] = SignalStatus.MODIFY.value
            self.db.update_signal(existing_signal.id, update_data)
        else:
            if existing_signal:
                logger.debug(f"Message {message.id} already exists. Skipping.")
                return

            # Validate and Save New Signal with PROCESS status
            schema = self._create_signal_schema(message, chat_id, parsed, content_hash, SignalStatus.PROCESS)
            if not schema:
                return

            signal_id = self.db.save_signal(schema.model_dump())

        # 5. Log Details
        log_msg = (
            f"✅ SIGNAL SAVED: ID={signal_id if 'signal_id' in locals() else existing_signal.id}\n"
            f"   Symbol: {parsed.symbol} | Direction: {parsed.direction}\n"
            f"   Entry: {parsed.entry_min} - {parsed.entry_max}\n"
            f"   Adjusted SL: {parsed.stop_loss} | Adjusted TPs: {parsed.take_profits}"
        )
        logger.info(log_msg)

    def _create_signal_schema(self, message: Any, chat_id: int, parsed: ParsedSignal,
                            content_hash: str, status: SignalStatus) -> Optional[TradingSignalSchema]:
        """Creates and validates Pydantic schema."""
        try:
            return TradingSignalSchema(
                telegram_message_id=message.id,
                telegram_channel_id=chat_id,
                symbol=parsed.symbol,
                direction=parsed.direction,
                entry_min=parsed.entry_min,
                entry_max=parsed.entry_max,
                stop_loss=parsed.stop_loss,
                take_profit_1=parsed.take_profits[0],
                take_profit_2=parsed.take_profits[1] if len(parsed.take_profits) > 1 else None,
                take_profit_3=parsed.take_profits[2] if len(parsed.take_profits) > 2 else None,
                raw_message=message.text,
                content_hash=content_hash,
                status=status
            )
        except ValueError as ve:
            self._handle_invalid_signal(message, parsed, str(ve))
            return None

    def _is_potential_signal(self, text: str) -> bool:
        """Quick check for signal-related keywords."""
        text_upper = text.upper()
        return any(s in text_upper for s in settings.filter_symbols) and \
               any(d in text_upper for d in ["BUY", "SELL", "LONG", "SHORT"])

    def _handle_invalid_signal(self, message: Any, parsed: ParsedSignal, error: str) -> None:
        """Logs rejected signals."""
        log_msg = (
            f"❌ SIGNAL REJECTED (Validation Failed) for Message {message.id}:\n"
            f"   Reason: {error}\n"
            f"   Entry={parsed.entry_min}-{parsed.entry_max}, SL={parsed.stop_loss}, TPs={parsed.take_profits}"
        )
        logger.warning(log_msg)
