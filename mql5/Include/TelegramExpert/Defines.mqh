//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property strict

//--- Константы проекта
#define JST_OFFSET           32400   // Смещение JST относительно GMT (9 часов * 3600 сек)
#define TARGET_JST_HOUR      7       // Час разблокировки (JST)
#define TARGET_JST_MINUTE    10      // Минута разблокировки (JST)

//--- Направление сделки
enum ENUM_SIGNAL_DIRECTION
{
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = 2
};

//--- Статусы сигнала (синхронизировано с Python SignalStatus)
enum ENUM_SIGNAL_STATUS
{
   STATUS_PROCESS = 0,   // PROCESS (Новый)
   STATUS_MODIFY  = 1,   // MODIFY (Изменен)
   STATUS_DONE    = 2,   // DONE (Обработан)
   STATUS_INVALID = 3,   // INVALID (Некорректен)
   STATUS_ERROR   = 4,   // ERROR (Ошибка)
   STATUS_EXPIRED = 5    // EXPIRED (Истёк 60-мин срок, установлен Python)
};

//--- Типы расчета лота
enum ENUM_LOT_TYPE
{
   LOT_FIXED        = 0  // Фиксированный лот
};

//--- Структура данных сигнала (соответствует схеме БД)
struct SSignalData
{
   long                 id;                  // Primary Key
   long                 telegram_msg_id;     // ID сообщения
   long                 telegram_channel_id; // ID канала (long для Telegram ID)
   string               symbol;              // "XAUUSD"
   ENUM_SIGNAL_DIRECTION direction;          // Направление
   double               entry_min;           // Entry Min
   double               entry_max;           // Entry Max
   double               stop_loss;           // SL
   double               take_profit_1;       // TP1
   double               take_profit_2;       // TP2
   double               take_profit_3;       // TP3
   ENUM_SIGNAL_STATUS   status;              // Текущий статус
};

//--- Состояние советника
struct SExpertState
{
   double               starting_equity;     // Эквити на 07:10 JST
   bool                 trading_locked;      // Блокировка (при -3%)
   datetime             lock_until;          // Время окончания блокировки
   long                 active_signal_id;    // ID текущего обрабатываемого сигнала
};
