import csv
import os
from pathlib import Path
from typing import List, Dict, Any
from loguru import logger

from database.models import Signal, SignalStatus

class CSVExporter:
    """Class to export trading signals from DB to CSV."""

    def __init__(self, export_path: str):
        """
        Initialize exporter.

        Args:
            export_path: Path where CSV file will be saved (e.g., './data_export/signals.csv').
        """
        self.export_path = Path(export_path)
        self._ensure_directory()

    def _ensure_directory(self) -> None:
        """Create export directory if it doesn't exist."""
        self.export_path.parent.mkdir(parents=True, exist_ok=True)

    def export_signals(self, signals: List[Signal]) -> bool:
        """
        Export list of signals to CSV file.

        Format: signal_id,symbol,direction,entry_min,entry_max,stop_loss,tp1,tp2,timestamp,status
        """
        try:
            # Using utf-8-sig (with BOM) for best compatibility
            with open(self.export_path, mode='w', newline='', encoding='utf-8-sig') as f:
                writer = csv.writer(f)

                # Header
                writer.writerow([
                    "id", "symbol", "direction", "entry_min", "entry_max",
                    "stop_loss", "tp1", "tp2", "tp3", "timestamp", "status"
                ])

                for s in signals:
                    writer.writerow([
                        s.id,
                        s.symbol,
                        s.direction,
                        f"{s.entry_min:.2f}",
                        f"{s.entry_max:.2f}",
                        f"{s.stop_loss:.2f}",
                        f"{s.take_profit_1:.2f}",
                        f"{s.take_profit_2:.2f}" if s.take_profit_2 else "0.00",
                        f"{s.take_profit_3:.2f}" if s.take_profit_3 else "0.00",
                        s.created_at.strftime("%Y-%m-%d %H:%M:%S"),
                        s.status
                    ])

            logger.debug(f"Exported {len(signals)} signals to {self.export_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to export signals to CSV: {e}")
            return False

    def clear_export(self) -> None:
        """Clear the signal file (e.g. after signals are processed)."""
        if self.export_path.exists():
            try:
                self.export_path.unlink()
                logger.info(f"Export file cleared: {self.export_path}")
            except Exception as e:
                logger.error(f"Error clearing export file: {e}")
