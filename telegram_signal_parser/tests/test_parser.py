"""Automated testing module for the signal parser."""
import pytest
from parser.signal_parser import SignalParser, ParsedSignal


@pytest.fixture
def parser() -> SignalParser:
    """Fixture to initialize the parser before each test."""
    return SignalParser()


class TestSignalParser:
    """Test suite for verifying data extraction logic from text."""

    def test_price_adjustment_buy(self, parser: SignalParser) -> None:
        """Verify that BUY signal prices are adjusted correctly (SL -0.50, TP +0.50)."""
        text = "XAUUSD BUY Entry: 2000 SL: 1990 TP: 2010"
        result = parser.parse(text)

        assert result is not None
        # Original Entry: 2000 -> Range 2000-2000
        assert result.entry_min == 2000.0
        # Original SL: 1990 -> Adjusted: 1990 - 0.50 = 1989.50
        assert result.stop_loss == 1989.50
        # Original TP: 2010 -> Adjusted: 2010 + 0.50 = 2010.50
        assert result.take_profits == [2010.50]

    def test_price_adjustment_sell(self, parser: SignalParser) -> None:
        """Verify that SELL signal prices are adjusted correctly (SL +0.50, TP -0.50)."""
        text = "XAUUSD SELL Entry: 2000 SL: 2010 TP: 1990"
        result = parser.parse(text)

        assert result is not None
        # Original SL: 2010 -> Adjusted: 2010 + 0.50 = 2010.50
        assert result.stop_loss == 2010.50
        # Original TP: 1990 -> Adjusted: 1990 - 0.50 = 1989.50
        assert result.take_profits == [1989.50]

    def test_content_hashing(self, parser: SignalParser) -> None:
        """Verify that identical signals produce the same hash and changes produce different hashes."""
        text1 = "XAUUSD BUY Entry: 2000 SL: 1990 TP: 2010"
        text2 = "XAUUSD BUY @ 2000 SL 1990 TP 2010"  # Same content, different format
        text3 = "XAUUSD BUY Entry: 2000 SL: 1990 TP: 2011"  # Different TP

        res1 = parser.parse(text1)
        res2 = parser.parse(text2)
        res3 = parser.parse(text3)

        hash1 = res1.generate_hash()
        hash2 = res2.generate_hash()
        hash3 = res3.generate_hash()

        assert hash1 == hash2
        assert hash1 != hash3

    def test_parse_standard_buy(self, parser: SignalParser) -> None:
        """Verify parsing of a standard BUY signal with a price range (with adjustment)."""
        text = """
        XAUUSD BUY
        Entry: 2040.50 - 2042.00
        SL: 2030.00
        TP1: 2050.00
        TP2: 2060.00
        """
        result = parser.parse(text)

        assert isinstance(result, ParsedSignal)
        assert result.direction == "BUY"
        assert result.entry_min == 2040.50
        assert result.entry_max == 2042.00
        assert result.stop_loss == 2029.50  # 2030.00 - 0.50
        assert result.take_profits == [2050.50, 2060.50] # Each + 0.50

    def test_parse_user_specific_format(self, parser: SignalParser) -> None:
        """Verify parsing of the specific format provided by the user (with adjustment)."""
        text = """
        XAUUSD BUY

        • Entry: 4809-4805

        • Stop Loss (SL): 4799

        • Take Profit (TP): TP1:  4818
                                            TP2: 4828
                                             TP3:4849

        Utilize risk management techniques
        to protect your capital.
        """
        result = parser.parse(text)

        assert result is not None
        assert result.direction == "BUY"
        assert result.entry_min == 4805.0
        assert result.entry_max == 4809.0
        assert result.stop_loss == 4798.50 # 4799.0 - 0.50
        assert 4818.50 in result.take_profits
        assert 4828.50 in result.take_profits
        assert 4849.50 in result.take_profits

    def test_strict_parsing_missing_sl_tp(self, parser: SignalParser) -> None:
        """Verify that signals without SL or TP are rejected."""
        # Missing TP
        assert parser.parse("XAUUSD BUY Entry: 2000 SL: 1990") is None
        # Missing SL
        assert parser.parse("XAUUSD BUY Entry: 2000 TP: 2010") is None
        # Missing Direction
        assert parser.parse("XAUUSD Entry: 2000 SL: 1990 TP: 2010") is None

    def test_parse_with_markdown_formatting(self, parser: SignalParser) -> None:
        """Verify that markdown stars do not break price extraction."""
        text = "XAUUSD BUY Entry: **4805** SL: **4790** TP: **4820**"
        result = parser.parse(text)

        assert result is not None
        assert result.entry_min == 4805.0
        assert result.stop_loss == 4789.50 # 4790 - 0.50
        assert result.take_profits == [4820.50] # 4820 + 0.50

    def test_invalid_tp_sequence(self, parser: SignalParser) -> None:
        """Verify that out-of-order Take Profits raise validation errors."""
        from database.models import TradingSignalSchema, SignalDirection, SignalStatus

        # Invalid BUY sequence: TP2 is lower than TP1
        with pytest.raises(ValueError, match="BUY: TP2 .* must be above TP1"):
            TradingSignalSchema(
                telegram_message_id=1,
                telegram_channel_id=1,
                symbol="XAUUSD",
                direction=SignalDirection.BUY,
                entry_min=2000.0,
                entry_max=2005.0,
                stop_loss=1990.0,
                take_profit_1=2010.0,
                take_profit_2=2005.0, # INVALID: TP2 < TP1
                raw_message="test",
                content_hash="hash",
                status=SignalStatus.PROCESS
            )

        # Invalid SELL sequence: TP2 is higher than TP1
        with pytest.raises(ValueError, match="SELL: TP2 .* must be below TP1"):
            TradingSignalSchema(
                telegram_message_id=1,
                telegram_channel_id=1,
                symbol="XAUUSD",
                direction=SignalDirection.SELL,
                entry_min=2000.0,
                entry_max=2005.0,
                stop_loss=2015.0,
                take_profit_1=1990.0,
                take_profit_2=1995.0, # INVALID: TP2 > TP1
                raw_message="test",
                content_hash="hash",
                status=SignalStatus.PROCESS
            )

    def test_strict_symbol_filtering(self, parser: SignalParser) -> None:
        """Verify that non-XAUUSD signals are ignored."""
        assert parser.parse("EURUSD BUY Entry: 1.0800 SL: 1.0700 TP: 1.0900") is None
        assert parser.parse("GBPUSD SELL Entry: 1.2500 SL: 1.2600 TP: 1.2400") is None

    def test_max_sl_distance_validation(self, parser: SignalParser) -> None:
        """Verify that signals with SL distance > max_sl_distance are rejected."""
        from database.models import TradingSignalSchema, SignalDirection, SignalStatus
        from config.settings import settings

        # Set temporary max distance for test
        original_max = settings.max_sl_distance
        settings.max_sl_distance = 15.0

        try:
            # Valid BUY (Distance = 2000 - 1990 = 10.0)
            TradingSignalSchema(
                telegram_message_id=1, telegram_channel_id=1,
                symbol="XAUUSD", direction=SignalDirection.BUY,
                entry_min=2000.0, entry_max=2000.0, stop_loss=1990.0,
                take_profit_1=2010.0, raw_message="test", content_hash="hash1"
            )

            # Invalid BUY (Distance = 2000 - 1980 = 20.0 > 15.0)
            with pytest.raises(ValueError, match="BUY: SL distance .* exceeds maximum allowed"):
                TradingSignalSchema(
                    telegram_message_id=2, telegram_channel_id=1,
                    symbol="XAUUSD", direction=SignalDirection.BUY,
                    entry_min=2000.0, entry_max=2000.0, stop_loss=1980.0,
                    take_profit_1=2010.0, raw_message="test", content_hash="hash2"
                )

            # Valid SELL (Distance = 2010 - 2000 = 10.0)
            TradingSignalSchema(
                telegram_message_id=3, telegram_channel_id=1,
                symbol="XAUUSD", direction=SignalDirection.SELL,
                entry_min=2000.0, entry_max=2000.0, stop_loss=2010.0,
                take_profit_1=1990.0, raw_message="test", content_hash="hash3"
            )

            # Invalid SELL (Distance = 2020 - 2000 = 20.0 > 15.0)
            with pytest.raises(ValueError, match="SELL: SL distance .* exceeds maximum allowed"):
                TradingSignalSchema(
                    telegram_message_id=4, telegram_channel_id=1,
                    symbol="XAUUSD", direction=SignalDirection.SELL,
                    entry_min=2000.0, entry_max=2000.0, stop_loss=2020.0,
                    take_profit_1=1990.0, raw_message="test", content_hash="hash4"
                )
        finally:
            settings.max_sl_distance = original_max


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
