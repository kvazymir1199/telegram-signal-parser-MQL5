"""Database management module using SQLAlchemy."""
from pathlib import Path
from typing import Optional, List, Any, Dict
from datetime import datetime

from sqlalchemy import create_engine, select, update, desc, insert
from sqlalchemy.orm import sessionmaker, Session
from loguru import logger

from database.models import Base, Signal, SignalStatus, Channel, Setting


class DatabaseManager:
    """Database manager for handling signals and channels."""

    def __init__(self, db_path: str):
        """
        Initialize database manager.

        Args:
            db_path: Path to SQLite file.
        """
        self.db_path = Path(db_path)
        self._ensure_directory()

        # Create SQLAlchemy engine
        self.engine = create_engine(
            f"sqlite:///{self.db_path}",
            connect_args={"check_same_thread": False}
        )

        # Session factory
        self.SessionLocal = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine
        )

    def _ensure_directory(self) -> None:
        """Create database directory if it doesn't exist."""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

    def init_tables(self) -> None:
        """Create all tables defined in models."""
        try:
            Base.metadata.create_all(bind=self.engine)
            logger.info(f"Database tables initialized: {self.db_path}")
        except Exception as e:
            logger.error(f"Error creating tables: {e}")
            raise

    def get_session(self) -> Session:
        """Return a new database session."""
        return self.SessionLocal()

    def save_signal(self, signal_data: Dict[str, Any]) -> int:
        """
        Save new signal to database.

        Args:
            signal_data: Data for Signal object creation.

        Returns:
            id: Created record ID.
        """
        with self.get_session() as session:
            try:
                db_signal = Signal(**signal_data)
                session.add(db_signal)
                session.commit()
                session.refresh(db_signal)
                logger.debug(f"Signal saved to DB: ID={db_signal.id}")
                return db_signal.id
            except Exception as e:
                session.rollback()
                logger.error(f"Error saving signal: {e}")
                raise

    def get_signal(self, signal_id: int) -> Optional[Signal]:
        """Get signal object by its ID."""
        with self.get_session() as session:
            return session.get(Signal, signal_id)

    def get_signal_by_remote_id(self, channel_id: int, message_id: int) -> Optional[Signal]:
        """
        Retrieve signal by its Telegram channel and message IDs.
        Used for identifying existing signals when a message is edited.
        """
        with self.get_session() as session:
            stmt = select(Signal).where(
                Signal.telegram_channel_id == channel_id,
                Signal.telegram_message_id == message_id
            )
            result = session.execute(stmt)
            return result.scalar_one_or_none()

    def get_latest_signal_by_hash(self, content_hash: str) -> Optional[Signal]:
        """
        Retrieve the most recent signal with a specific content hash.
        Used for duplicate detection.
        """
        with self.get_session() as session:
            stmt = (
                select(Signal)
                .where(Signal.content_hash == content_hash)
                .order_by(desc(Signal.created_at))
                .limit(1)
            )
            result = session.execute(stmt)
            return result.scalar_one_or_none()

    def update_signal(self, signal_id: int, update_data: Dict[str, Any]) -> None:
        """
        Update fields of an existing signal.

        Args:
            signal_id: Signal ID.
            update_data: Dictionary of fields to update.
        """
        with self.get_session() as session:
            try:
                # Ensure updated_at is always refreshed
                update_data['updated_at'] = datetime.utcnow()

                stmt = (
                    update(Signal)
                    .where(Signal.id == signal_id)
                    .values(**update_data)
                )
                session.execute(stmt)
                session.commit()
                logger.debug(f"Signal {signal_id} fields updated: {list(update_data.keys())}")
            except Exception as e:
                session.rollback()
                logger.error(f"Error updating signal {signal_id}: {e}")
                raise

    def update_signal_status(self, signal_id: int, status: SignalStatus) -> None:
        """
        Update status of an existing signal.

        Args:
            signal_id: Signal ID.
            status: New status from SignalStatus enum.
        """
        self.update_signal(signal_id, {"status": status.value})

    def expire_old_signals(self, max_age_seconds: int = 3600) -> int:
        """
        Mark signals older than max_age_seconds as EXPIRED.

        Args:
            max_age_seconds: Maximum age in seconds (default 3600 = 60 min)

        Returns:
            Number of signals marked as expired.
        """
        from datetime import timedelta

        cutoff_time = datetime.utcnow() - timedelta(seconds=max_age_seconds)

        with self.get_session() as session:
            try:
                stmt = (
                    update(Signal)
                    .where(
                        Signal.status.in_([SignalStatus.PROCESS.value, SignalStatus.MODIFY.value]),
                        Signal.created_at < cutoff_time
                    )
                    .values(
                        status=SignalStatus.EXPIRED.value,
                        updated_at=datetime.utcnow()
                    )
                )
                result = session.execute(stmt)
                session.commit()
                expired_count = result.rowcount
                if expired_count > 0:
                    logger.info(f"Expired {expired_count} signal(s) older than {max_age_seconds}s")
                return expired_count
            except Exception as e:
                session.rollback()
                logger.error(f"Error expiring old signals: {e}")
                return 0

    def get_active_channels(self) -> List[int]:
        """Return a list of IDs for all active Telegram channels."""
        with self.get_session() as session:
            stmt = select(Channel.telegram_id).where(Channel.is_active == True)
            result = session.execute(stmt)
            return [row[0] for row in result.all()]

    # --- Settings Management ---

    def get_all_settings(self) -> Dict[str, Any]:
        """Retrieve all settings from the database as a dictionary."""
        with self.get_session() as session:
            stmt = select(Setting)
            result = session.execute(stmt)
            return {s.key: s.value for s in result.scalars().all()}

    def get_setting(self, key: str, default: Any = None) -> Any:
        """Get a specific setting value by key."""
        with self.get_session() as session:
            setting = session.get(Setting, key)
            return setting.value if setting else default

    def update_setting(self, key: str, value: Any, description: Optional[str] = None) -> None:
        """Update or create a setting in the database."""
        with self.get_session() as session:
            try:
                setting = session.get(Setting, key)
                if setting:
                    setting.value = str(value)
                    if description:
                        setting.description = description
                    setting.updated_at = datetime.utcnow()
                else:
                    new_setting = Setting(key=key, value=str(value), description=description)
                    session.add(new_setting)
                session.commit()
                logger.debug(f"Setting updated: {key}={value}")
            except Exception as e:
                session.rollback()
                logger.error(f"Error updating setting {key}: {e}")
                raise

    def bulk_update_settings(self, settings_dict: Dict[str, Any]) -> None:
        """Update multiple settings at once in a single transaction."""
        with self.get_session() as session:
            try:
                for key, value in settings_dict.items():
                    setting = session.get(Setting, key)
                    if setting:
                        setting.value = str(value)
                        setting.updated_at = datetime.utcnow()
                    else:
                        new_setting = Setting(key=key, value=str(value))
                        session.add(new_setting)
                session.commit()
                logger.info(f"Bulk settings update successful for {len(settings_dict)} keys")
            except Exception as e:
                session.rollback()
                logger.error(f"Error in bulk settings update: {e}")
                raise
