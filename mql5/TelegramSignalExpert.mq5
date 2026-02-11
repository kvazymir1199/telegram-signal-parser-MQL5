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
input group "=== Торговые настройки ==="
input ENUM_LOT_TYPE InpLotType       = LOT_FIXED;      // Способ расчета лота
input double        InpLotValue      = 0.01;           // Значение (объем или % риска)
input int           InpMagicNumber   = 123456;         // Magic Number
input int           InpTimerInterval = 2;              // Интервал опроса БД (сек)

input group "=== Риск-менеджмент ==="
input double        InpMaxDailyLoss  = 3.0;            // Макс. дневной убыток (%)
input string        InpStartTimeJST  = "07:10";        // Начало торгового дня (JST)

input group "=== Настройки базы данных ==="
input string        InpDatabasePath  = "signals.sqlite3";           // Путь к файлу БД (в MQL5/Files)

//--- Глобальные объекты
//--- Глобальные объекты
CSignalManager g_manager;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Инициализация главного менеджера
   bool init_res = g_manager.Init(InpDatabasePath, _Symbol, InpMagicNumber, InpLotType, InpLotValue, InpMaxDailyLoss, InpStartTimeJST);
   if(!init_res)
   {
      Print("ОШИБКА: Не удалось инициализировать SignalManager.");
      return(INIT_FAILED);
   }

   // Установка таймера для опроса БД
   if(!EventSetTimer(InpTimerInterval))
   {
      Print("ОШИБКА: Не удалось установить таймер.");
      return(INIT_FAILED);
   }

   PrintFormat("Советник запущен. Символ: %s, Magic: %d, Опрос: %d сек.", _Symbol, InpMagicNumber, InpTimerInterval);
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

   PrintFormat("Советник остановлен. Причина: %d", reason);
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
