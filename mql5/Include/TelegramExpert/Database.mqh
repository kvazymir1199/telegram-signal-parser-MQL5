//+------------------------------------------------------------------+
//|                                                     Database.mqh |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"

//+------------------------------------------------------------------+
//| Класс для управления SQLite базой данных сигналов                |
//+------------------------------------------------------------------+
class CDatabaseManager
{
private:
   int               m_db_handle;      // Хэндл базы данных
   string            m_db_path;        // Путь к файлу БД

public:
                     CDatabaseManager();
                    ~CDatabaseManager();

   bool              Open(const string path);
   void              Close();

   // Получение списка сигналов для обработки
   int               GetPendingSignals(SSignalData &signals[]);

   // Смена статуса сигнала (атомарная операция)
   bool              UpdateStatus(const long signal_id, const ENUM_SIGNAL_STATUS new_status);

private:
   ENUM_SIGNAL_DIRECTION StringToDirection(string dir);
   string                StatusToDBString(const ENUM_SIGNAL_STATUS status);
   bool                  CheckAndCreateTable();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDatabaseManager::CDatabaseManager() : m_db_handle(INVALID_HANDLE)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDatabaseManager::~CDatabaseManager()
{
   Close();
}

//+------------------------------------------------------------------+
//| Открытие базы данных                                             |
//+------------------------------------------------------------------+
bool CDatabaseManager::Open(const string path)
{
   Close();

   // Флаги: Чтение/Запись + Создание если нет
   m_db_handle = DatabaseOpen(path, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE);

   if(m_db_handle == INVALID_HANDLE)
   {
      PrintFormat("DB: Error opening %s. Error code: %d", path, GetLastError());
      return false;
   }

   m_db_path = path;
   
   // Проверяем/создаем таблицу
   if(!CheckAndCreateTable())
   {
      Close();
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Закрытие базы данных                                             |
//+------------------------------------------------------------------+
void CDatabaseManager::Close()
{
   if(m_db_handle != INVALID_HANDLE)
   {
      DatabaseClose(m_db_handle);
      m_db_handle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Чтение сигналов PROCESS/MODIFY из БД                             |
//+------------------------------------------------------------------+
int CDatabaseManager::GetPendingSignals(SSignalData &signals[])
{
   ArrayFree(signals);
   if(m_db_handle == INVALID_HANDLE) return 0;

   // Выбираем только золото и только активные статусы
   string sql = "SELECT id, telegram_message_id, telegram_channel_id, symbol, direction, "
                "entry_min, entry_max, stop_loss, take_profit_1, take_profit_2, take_profit_3, status "
                "FROM signals "
                "WHERE symbol IN ('XAUUSD', 'GOLD') AND status IN ('PROCESS', 'MODIFY') "
                "ORDER BY id ASC";

   int request = DatabasePrepare(m_db_handle, sql);
   if(request == INVALID_HANDLE)
   {
      PrintFormat("DB: DatabasePrepare error. Code: %d", GetLastError());
      return 0;
   }

   int count = 0;
   while(DatabaseRead(request))
   {
      SSignalData data;
      string dir_text, status_text;

      // Чтение колонок по индексам
      DatabaseColumnLong(request, 0, data.id);
      DatabaseColumnLong(request, 1, data.telegram_msg_id);
      DatabaseColumnLong(request, 2, data.telegram_channel_id);
      DatabaseColumnText(request, 3, data.symbol);
      DatabaseColumnText(request, 4, dir_text);
      DatabaseColumnDouble(request, 5, data.entry_min);
      DatabaseColumnDouble(request, 6, data.entry_max);
      DatabaseColumnDouble(request, 7, data.stop_loss);
      DatabaseColumnDouble(request, 8, data.take_profit_1);

      // Проверка на NULL для опциональных TP (5 = DATABASE_TYPE_NULL)
      if(DatabaseColumnType(request, 9) != 5)
         DatabaseColumnDouble(request, 9, data.take_profit_2);
      else data.take_profit_2 = 0;

      if(DatabaseColumnType(request, 10) != 5)
         DatabaseColumnDouble(request, 10, data.take_profit_3);
      else data.take_profit_3 = 0;

      DatabaseColumnText(request, 11, status_text);

      // Конвертация строк в перечисления
      data.direction = StringToDirection(dir_text);

      if(status_text == "PROCESS") data.status = STATUS_PROCESS;
      else if(status_text == "MODIFY") data.status = STATUS_MODIFY;
      else data.status = STATUS_INVALID;

      // Добавляем только корректные сигналы
      if(data.direction != DIR_NONE)
      {
         ArrayResize(signals, count + 1);
         signals[count] = data;
         count++;
      }
   }

   // Обязательное освобождение хэндла запроса
   DatabaseFinalize(request);
   return count;
}

//+------------------------------------------------------------------+
//| Обновление статуса (с использованием транзакции)                 |
//+------------------------------------------------------------------+
bool CDatabaseManager::UpdateStatus(const long signal_id, const ENUM_SIGNAL_STATUS new_status)
{
   if(m_db_handle == INVALID_HANDLE) return false;

   string status_str = StatusToDBString(new_status);
   string sql = StringFormat("UPDATE signals SET status='%s', updated_at=datetime('now') WHERE id=%lld",
                             status_str, signal_id);

   // Запуск транзакции для надежности
   if(!DatabaseTransactionBegin(m_db_handle))
   {
      PrintFormat("DB: TransactionBegin error. Code: %d", GetLastError());
      return false;
   }

   if(!DatabaseExecute(m_db_handle, sql))
   {
      PrintFormat("DB: UPDATE error. Code: %d. SQL: %s", GetLastError(), sql);
      DatabaseTransactionRollback(m_db_handle);
      return false;
   }

   if(!DatabaseTransactionCommit(m_db_handle))
   {
      PrintFormat("DB: TransactionCommit error. Code: %d", GetLastError());
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Маппинг направления                                              |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIRECTION CDatabaseManager::StringToDirection(string dir)
{
   StringToUpper(dir);
   if(dir == "BUY" || dir == "LONG") return DIR_BUY;
   if(dir == "SELL" || dir == "SHORT") return DIR_SELL;
   return DIR_NONE;
}

//+------------------------------------------------------------------+
//| Маппинг статуса в строку                                         |
//+------------------------------------------------------------------+
string CDatabaseManager::StatusToDBString(const ENUM_SIGNAL_STATUS status)
{
   switch(status)
   {
      case STATUS_PROCESS: return "PROCESS";
      case STATUS_MODIFY:  return "MODIFY";
      case STATUS_DONE:    return "DONE";
      case STATUS_INVALID: return "INVALID";
      case STATUS_ERROR:   return "ERROR";
      case STATUS_EXPIRED: return "EXPIRED";
   }
   return "UNKNOWN";
}
//+------------------------------------------------------------------+
//| Создание таблицы если она отсутствует                            |
//+------------------------------------------------------------------+
bool CDatabaseManager::CheckAndCreateTable()
{
   if(m_db_handle == INVALID_HANDLE) return false;

   string sql = "CREATE TABLE IF NOT EXISTS signals ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "telegram_message_id INTEGER, "
                "telegram_channel_id INTEGER, "
                "symbol TEXT, "
                "direction TEXT, "
                "entry_min REAL, "
                "entry_max REAL, "
                "stop_loss REAL, "
                "take_profit_1 REAL, "
                "take_profit_2 REAL, "
                "take_profit_3 REAL, "
                "status TEXT, "
                "updated_at DATETIME"
                ");";

   if(!DatabaseExecute(m_db_handle, sql))
   {
      PrintFormat("DB: Table creation error. Code: %d", GetLastError());
      return false;
   }
   return true;
}
