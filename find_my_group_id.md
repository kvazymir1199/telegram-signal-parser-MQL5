# Telegram Signal Parser: Setup Guide

This guide covers how to obtain your Telegram API credentials and how to find the Group ID for monitoring.

---

## 1. How to Get Telegram API Credentials (API ID & Hash)

To connect the parser to your Telegram account, you need to obtain your own API credentials from Telegram.

### Step-by-Step Instructions:

1.  Go to the official Telegram website: [https://my.telegram.org](https://my.telegram.org)
2.  **Log in** with your Telegram phone number (in international format, e.g., `+1234567890`).
3.  Enter the confirmation code sent to your Telegram app.
4.  Go to the **"API development tools"** section.
5.  If this is your first time, you will be asked to create a new application.
    *   **App title:** You can use `SignalParser` or any name you like.
    *   **Short name:** Use a simple name like `sigparser`.
    *   **Platform:** Select `Desktop` or `Other`.
    *   **URL/Description:** Can be left blank or filled with placeholder info.
6.  Once created, you will see your **App api_id** and **App api_hash**.
7.  Copy these values into the **Telegram API Configuration** section of your Dashboard.

---

## 2. How to Find Your Telegram Group ID

To monitor a specific group or channel, you need its numeric ID.

### Recommended Method: Using @userinfobot

The most reliable way to find a Group ID is by using the specialized Telegram bot **@userinfobot**.

### Step-by-Step Instructions:

1.  Open Telegram and search for **@userinfobot**.
2.  Start a conversation with the bot by clicking **"Start"**.
3.  **Forward any message** from the group you want to monitor directly to this bot.
4.  The bot will reply with a message containing the **"Chat ID"** (or **"ID"**).
    *   *Example:* `-5127304931`
5.  Copy this exact value (including the minus sign `-`).

---

## 3. Applying Settings to the Dashboard

1.  Open your Signal Parser Dashboard ([http://127.0.0.1:8000](http://127.0.0.1:8000)).
2.  Fill in the **API ID**, **API Hash**, and **Phone Number**.
3.  Add the **Group ID** to the **"Channel Monitoring"** list under Trading Filters.
4.  Click **"Apply Changes"**.
5.  Click **"Start Parser"** to begin monitoring.

---
*Note: Group IDs usually start with a minus sign (e.g., `-5127304931`). For channels or supergroups, they often start with `-100` (e.g., `-1001234567890`).*
