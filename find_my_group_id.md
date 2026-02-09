# How to Find Your Telegram Group ID

To configure the **Telegram Signal Parser Service**, you need the numeric ID (Chat ID) of the group or channel you want to monitor.

## Recommended Method: Using @userinfobot

The most reliable and easiest way to find a Group ID is by using the specialized Telegram bot **@userinfobot**.

### Step-by-Step Instructions:

1.  Open Telegram and search for **@userinfobot**.
2.  Start a conversation with the bot by clicking **"Start"**.
3.  **Forward any message** from the group you want to monitor directly to this bot.
4.  The bot will reply with a message containing information about the original message.
5.  Look for the **"Chat ID"** (or simply **"ID"**) field.
    *   *Example:* `-5127304931`
6.  Copy this exact value (including the minus sign if present).

### Adding the ID to the Dashboard:

1.  Open your Signal Parser Dashboard ([http://127.0.0.1:8000](http://127.0.0.1:8000)).
2.  Go to the **"Trading Filters"** section.
3.  Enter the ID into the **"Channel Monitoring"** list.
4.  Click **"Apply Changes"**.

---
*Note: Group IDs usually start with a minus sign (e.g., `-5127304931`). For channels or supergroups, they often start with `-100` (e.g., `-1001234567890`). Copy the ID exactly as provided by the bot.*
