Telegram Signal → MT5 Auto Trading System

I’m looking for an experienced developer to build a simple, stable, and risk-controlled trading automation system.

This system is mainly for trading, so risk management and stability are the top priority.

The system consists of two fully separated parts.

--------------------------------------------------

1. Python – Telegram Signal Reader

A Python script that reads text-based trading signals from Telegram groups.

Example signal format:

XAUUSD BUY
Entry: 2350 to 2352
Stop Loss (SL): 2340
Take Profit (TP): TP1: 2355
TP2: 2360

Python responsibilities:
- Read messages from Telegram groups
- Filter only XAUUSD (Gold) signals
- Parse Buy/Sell, entry range, SL, and TP levels
- Save parsed data to a local TXT or CSV file
- Python handles Telegram only (no direct MT5 interaction)
- Telegram format may change, so parsing logic must be easy to adjust

--------------------------------------------------

2. MetaTrader 5 EA (MQL5)

General Requirements:
- EA reads only the local file created by Python
- EA must NOT use DLL
- EA must NOT use WebRequest
- Full .mq5 source file must be delivered

Trading Logic:

- Only one active signal at a time
- For each valid signal, always open 2 market orders

Entry rules:
- If current price is inside the entry range → enter at market
- If price already passed the entry range:
- Entry allowed only if price exceeds the range by maximum 3 XAUUSD prices = 0.03 = 30 pips (configurable)
- If price exceeds more than this → ignore the signal

Order management:
- Order 1 → TP1
- Order 2 → TP2
- When Order 1 hits TP1:
- Move Order 2 SL to breakeven (entry price)

New signal handling:
- When a new signal arrives:
- Close all existing trades immediately
- Follow the new signal only

--------------------------------------------------

3. Risk Management (Very Important)

- Fixed lot size (user input)
- Maximum daily loss: 3% of equity
- EA must monitor equity in real time

Daily loss protection:
- If daily equity loss reaches 3% or more:
- Immediately close all open positions
- Stop trading until the next trading day

Order safety:
- SL and TP must be attached immediately when placing orders
- If SL fails to be placed for any reason:
- EA must close the trade immediately

--------------------------------------------------

4. Additional Safety Rules

- Slippage limit: 30 pips (0.03 XAUUSD), configurable
- EA must not:
- Open duplicate trades
- Re-enter the same signal multiple times
- Trade when any risk rule is violated

--------------------------------------------------

5. General Notes

- Python = Telegram only
- EA = Trading only
- Communication between them via local file only
- Developer does NOT need access to my trading accounts or Telegram account
- System will be tested on demo first
- Code must be clean, stable, and easy to understand

--------------------------------------------------

6. Deliverables

- Python source file (.py)
- MT5 EA source file (.mq5)
- Basic setup instructions
- Clear explanation of logic and risk protection

--------------------------------------------------

7. Payment & Communication

- Fixed-price project
- Milestone-based payment preferred
- Clear communication is required

--------------------------------------------------

8. Final Request

Please:
- Briefly explain your technical approach
- Confirm that you fully understand all requirements and risk rules above 