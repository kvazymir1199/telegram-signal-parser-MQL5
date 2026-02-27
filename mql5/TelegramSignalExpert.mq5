//+------------------------------------------------------------------+
//|                                         TelegramSignalExpert.mq5 |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//--- Подключение модулей
#include "Include/TelegramExpert/Defines.mqh"
#include "Include/TelegramExpert/SignalManager.mqh"

//--- Входные параметры
input group "=== Trading Settings ==="
input double        InpLotOrder1     = 0.15;           // Lot Order 1 (TP1)
input double        InpLotOrder2     = 0.20;           // Lot Order 2 (TP2)
input int           InpMagicNumber   = 123456;         // Magic Number
input int           InpTimerInterval = 1;              // DB Polling Interval (sec)
input int           InpEntryRangePips = 30;            // Entry Range Tolerance (Pips)

input group "=== Risk Management ==="
input double        InpMaxDailyLoss  = 3.0;            // Max Daily Loss (%)
input double        InpMaxSLDistance = 15.0;           // Max Allowed SL Distance (Price Units)
input string        InpStartTimeJST  = "07:10";        // Day Start Time (JST)
input bool          InpIncludeManualTrades = false;    // Include Manual Trades in P/L

input group "=== Database Settings ==="
input string        InpDatabasePath  = "signals.sqlite3";           // DB File Path (in MQL5/Files)

//--- Глобальные объекты
CSignalManager g_manager;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Инициализация главного менеджера
   bool init_res = g_manager.Init(InpDatabasePath, _Symbol, InpMagicNumber,
                                  InpLotOrder1, InpLotOrder2,
                                  InpMaxDailyLoss, InpMaxSLDistance, InpStartTimeJST,
                                  InpIncludeManualTrades, InpEntryRangePips * 10);
   if(!init_res)
   {
      Print("ERROR: Could not initialize SignalManager.");
      return(INIT_FAILED);
   }

   // Установка таймера для опроса БД
   if(!EventSetTimer(InpTimerInterval))
   {
      Print("ERROR: Could not set timer.");
      return(INIT_FAILED);
   }

   PrintFormat("Expert started. Symbol: %s, Magic: %d, Polling: %d sec.", _Symbol, InpMagicNumber, InpTimerInterval);
   PrintFormat("Data Path: %s\\MQL5\\Files\\", TerminalInfoString(TERMINAL_DATA_PATH));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Остановка таймера
   EventKillTimer();

   // Очистка ресурсов менеджера
   g_manager.Deinit();

   PrintFormat("Expert stopped. Reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Передача управления менеджеру сигналов
   g_manager.OnTick();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // В данной реализации вся логика работает по таймеру в OnTimer.
   // OnTick оставлен пустым для минимизации нагрузки.
}
//+------------------------------------------------------------------+
