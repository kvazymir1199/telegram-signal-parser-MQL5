"""Trading signal parsing module for extracting data from text messages."""
import re
import hashlib
from typing import Optional, Tuple, List, Dict, Any
from pydantic import BaseModel
from loguru import logger


class ParsedSignal(BaseModel):
    """Data structure for storing primary parsing results (Pydantic model)."""
    direction: str
    entry_min: float
    entry_max: float
    stop_loss: float
    take_profits: List[float]
    symbol: str = "XAUUSD"

    def generate_hash(self) -> str:
        """
        Generates a unique MD5 hash for the signal content.
        Used to detect identical signals and track price changes.
        """
        # Sort TPs to ensure consistent hash even if order changes
        sorted_tps = sorted([round(tp, 2) for tp in self.take_profits])

        content = (
            f"{self.symbol}|{self.direction}|"
            f"{round(self.entry_min, 2)}|{round(self.entry_max, 2)}|"
            f"{round(self.stop_loss, 2)}|{sorted_tps}"
        )
        return hashlib.md5(content.encode()).hexdigest()


class SignalParser:
    """Trading signal parser using flexible regular expressions."""

    def __init__(self, allowed_symbols: List[str] = None):
        """
        Initialize parser.

        Args:
            allowed_symbols: List of symbols to monitor (e.g., ['XAUUSD', 'GOLD'])
        """
        self.allowed_symbols = [s.upper() for s in allowed_symbols] if allowed_symbols else ["XAUUSD", "GOLD"]

    # Patterns are flexible: they look for a keyword, then skip non-numeric characters [^0-9.]*
    _PATTERNS: Dict[str, re.Pattern] = {
        'direction': re.compile(
            r'\b(BUY|SELL|LONG|SHORT)\b',
            re.IGNORECASE
        ),
        'entry_range': re.compile(
            r'(?:entry|вход|•?\s*entry)[^0-9]*(\d+(?:\.\d+)?)\s*(?:to|-|–|—)\s*(\d+(?:\.\d+)?)',
            re.IGNORECASE
        ),
        'entry_single': re.compile(
            r'(?:entry|@|вход|•?\s*entry)[^0-9]*(\d+(?:\.\d+)?)',
            re.IGNORECASE
        ),
        'stop_loss': re.compile(
            r'(?:sl|stop\s*loss|стоп|•?\s*stop\s*loss)[^0-9]*(\d+(?:\.\d+)?)',
            re.IGNORECASE
        ),
        'take_profit_line': re.compile(
            r'(?:tp|take\s*profit|тейк)[^0-9]*',
            re.IGNORECASE
        ),
        'symbol': re.compile(
            r'\b(XAUUSD|XAU/?USD|GOLD)\b',
            re.IGNORECASE
        ),
    }

    def parse(self, text: str) -> Optional[ParsedSignal]:
        """
        Extracts a trading signal from arbitrary text and applies price adjustments.
        Requires symbol, direction, entry, SL, and at least one TP.

        Args:
            text: Message text.

        Returns:
            ParsedSignal: Object with adjusted data or None if required fields are not found.
        """
        try:
            # 0. Clean text from markdown formatting (like **4810**)
            cleaned_text = self._clean_text(text)

            # 1. Symbol (Filter based on allowed_symbols setting)
            symbol = self._extract_symbol(cleaned_text)
            if not symbol or symbol not in self.allowed_symbols:
                return None

            # Normalize symbol to XAUUSD if it's Gold
            if symbol in ("GOLD", "XAUUSD"):
                symbol = "XAUUSD"

            # 2. Direction
            direction = self._extract_direction(cleaned_text)
            if not direction:
                return None

            # 3. Entry Price
            entry_min, entry_max = self._extract_entry_range(cleaned_text)
            if entry_min is None:
                return None

            # 4. Stop Loss (Mandatory)
            stop_loss = self._extract_stop_loss(cleaned_text)
            if stop_loss is None:
                return None

            # 5. Take Profits (Mandatory)
            take_profits = self._extract_take_profits(cleaned_text)
            if not take_profits:
                return None

            # Create signal object with rounded values
            signal = ParsedSignal(
                direction=direction,
                entry_min=round(entry_min, 2),
                entry_max=round(entry_max, 2),
                stop_loss=round(stop_loss, 2),
                take_profits=[round(tp, 2) for tp in take_profits],
                symbol=symbol
            )

            # 6. Apply ±0.50 (5 pips / 50 points) adjustment for Gold
            return self._adjust_prices(signal)

        except Exception as e:
            logger.error(f"Error parsing text: {e}")
            return None

    def _clean_text(self, text: str) -> str:
        """Removes markdown formatting characters to prevent parsing errors."""
        # Remove bold, italic, code, and underline markers
        cleaned = re.sub(r'[\*_`~]', '', text)
        return cleaned

    def _adjust_prices(self, signal: ParsedSignal) -> ParsedSignal:
        """
        Applies ±0.50 price adjustment for XAUUSD.
        BUY: SL -= 0.50, TP += 0.50
        SELL: SL += 0.50, TP -= 0.50
        """
        adjustment = 0.50

        if signal.direction == "BUY":
            signal.stop_loss -= adjustment
            signal.take_profits = [tp + adjustment for tp in signal.take_profits]
        else:
            signal.stop_loss += adjustment
            signal.take_profits = [tp - adjustment for tp in signal.take_profits]

        return signal

    def _extract_direction(self, text: str) -> Optional[str]:
        """Extracts and normalizes trade direction."""
        match = self._PATTERNS['direction'].search(text)
        if match:
            val = match.group(1).upper()
            return "BUY" if val in ("BUY", "LONG") else "SELL"
        return None

    def _extract_entry_range(self, text: str) -> Tuple[Optional[float], Optional[float]]:
        """Extracts entry range or single entry price."""
        range_match = self._PATTERNS['entry_range'].search(text)
        if range_match:
            e1, e2 = float(range_match.group(1)), float(range_match.group(2))
            return min(e1, e2), max(e1, e2)

        single_match = self._PATTERNS['entry_single'].search(text)
        if single_match:
            val = float(single_match.group(1))
            return val, val

        return None, None

    def _extract_stop_loss(self, text: str) -> Optional[float]:
        """Extracts Stop Loss level."""
        match = self._PATTERNS['stop_loss'].search(text)
        return float(match.group(1)) if match else None

    def _extract_take_profits(self, text: str) -> List[float]:
        """
        Extracts a list of all found Take Profit levels.
        Only looks for numbers appearing after TP keywords.
        """
        all_tps = []
        lines = text.split('\n')
        in_tp_block = False

        for line in lines:
            line_upper = line.upper()
            tp_match = self._PATTERNS['take_profit_line'].search(line_upper)

            if tp_match:
                in_tp_block = True
                content_after_tp = line_upper[tp_match.end():]
                numbers = re.findall(r'(\d{3,}(?:\.\d+)?)', content_after_tp)
                for num in numbers:
                    all_tps.append(float(num))
                continue

            if in_tp_block:
                # Exit TP block only if we meet a major keyword (Entry, Stop Loss)
                # without meeting a TP keyword on the same line.
                if any(kw in line_upper for kw in ["ENTRY", "STOP LOSS", "SL:"]) and not tp_match:
                    in_tp_block = False
                    continue

                numbers = re.findall(r'(\d{3,}(?:\.\d+)?)', line_upper)
                if not numbers:
                    if not line.strip():
                        in_tp_block = False
                    continue

                for num in numbers:
                    all_tps.append(float(num))

        return list(dict.fromkeys(all_tps))

    def _extract_symbol(self, text: str) -> Optional[str]:
        """Extracts and normalizes trading symbol."""
        match = self._PATTERNS['symbol'].search(text)
        if match:
            sym = match.group(1).upper().replace("/", "")
            return "XAUUSD" if sym in ("XAUUSD", "GOLD") else sym
        return None
