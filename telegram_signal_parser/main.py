"""Main module for launching the Telegram Signal Parser application."""
import asyncio
import sys
import uvicorn
from typing import Optional
from loguru import logger

from config.settings import settings


class SignalParserApp:
    """Application class to manage the lifecycle of the parser."""

    def __init__(self):
        """Initialize application and setup environment."""
        self._setup_logging()

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

        # File output (Dashboard logs) - Filter out web server request noise
        logger.add(
            settings.log_file,
            level=settings.log_level,
            rotation="10 MB",
            retention="7 days",
            compression="zip",
            encoding="utf-8",
            filter=lambda record: "web.app" not in record["name"]
        )

    def _print_banner(self) -> None:
        """Display welcome banner with current settings."""
        logger.info("=" * 60)
        logger.info("STARTUP: Telegram Signal Parser")
        logger.info("=" * 60)
        logger.info(f"Database: {settings.database_path}")
        logger.info(f"Filter Symbols: {settings.filter_symbols}")
        logger.info(f"Monitored Channels: {settings.telegram_channels}")

    def run_web(self) -> None:
        """Launch the web dashboard."""
        logger.info(f"Starting Web Dashboard on http://127.0.0.1:{settings.web_port}")
        uvicorn.run("web.app:app", host="0.0.0.0", port=settings.web_port, log_level="info", reload=False)


def main():
    """Entry point for the script."""
    app = SignalParserApp()
    app.run_web()


if __name__ == "__main__":
    main()
