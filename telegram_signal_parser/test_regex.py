
from parser.signal_parser import SignalParser
from loguru import logger

def test_parser():
    parser = SignalParser()

    test_message = """
    XAUUSD BUY
    Entry: 2350 to 2352
    Stop Loss (SL): 2340
    Take Profit (TP): TP1: 2355
    TP2: 2360
    """

    logger.info("Testing parser with sample message...")
    result = parser.parse(test_message)

    if result:
        print("\n=== PARSE SUCCESS ===")
        print(f"Symbol: {result.symbol}")
        print(f"Direction: {result.direction}")
        print(f"Entry: {result.entry_min} - {result.entry_max}")
        print(f"Stop Loss: {result.stop_loss}")
        print(f"Take Profits: {result.take_profits}")
        print(f"Hash: {result.generate_hash()}")
    else:
        print("\n=== PARSE FAILED ===")

if __name__ == "__main__":
    test_parser()
