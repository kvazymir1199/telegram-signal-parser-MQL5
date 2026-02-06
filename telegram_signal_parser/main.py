"""Main module for launching the Telegram Signal Parser application."""
import asyncio
import sys
from typing import Optional
from loguru import logger

from config.settings import settings
from telegram.client import TelegramSignalClient


class SignalParserApp:
    """Application class to manage the lifecycle of the parser."""

    def __init__(self):
        """Initialize application and setup environment."""
        self._setup_logging()
        self.client: Optional[TelegramSignalClient] = None

    def _setup_logging(self) -> None:
        """Configure the Loguru logging system."""
        logger.remove()

        # Console output
        logger.add(
            sys.stdout,
            level=settings.log_level,
            format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
                   "<level>{level: <8}</level> | "
                   "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
                   "<level>{message}</level>"
        )

        # File output
        logger.add(
            settings.log_file,
            level=settings.log_level,
            rotation="10 MB",
            retention="7 days",
            compression="zip",
            encoding="utf-8"
        )

    def _print_banner(self) -> None:
        """Display welcome banner with current settings."""
        logger.info("=" * 60)
        logger.info("STARTUP: Telegram Signal Parser")
        logger.info("=" * 60)
        logger.info(f"Database: {settings.database_path}")
        logger.info(f"Filter Symbols: {settings.filter_symbols}")
        logger.info(f"Monitored Channels: {settings.telegram_channels}")

    async def run(self) -> None:
        """Launch the main application loop."""
        self._print_banner()

        try:
            self.client = TelegramSignalClient()
            await self.client.start()
        except KeyboardInterrupt:
            logger.info("Application interrupted by user")
        except Exception as e:
            logger.exception(f"Critical application failure: {e}")
        finally:
            await self.stop()

    async def stop(self) -> None:
        """Stop application and release resources."""
        logger.info("Application shutting down...")
        if self.client and self.client.client.is_connected():
            await self.client.client.disconnect()
        logger.info("Shutdown complete")


async def main():
    """Entry point for the script."""
    app = SignalParserApp()
    await app.run()


if __name__ == "__main__":
    asyncio.run(main())
