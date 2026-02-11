//+------------------------------------------------------------------+
//|                                                SignalManager.mqh |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"
#include "Database.mqh"
#include "RiskManager.mqh"
#include "TradeEngine.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Класс-координатор (Мозг советника)                               |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
   CDatabaseManager  m_db;             // Модуль БД
   CRiskManager      m_risk;           // Модуль рисков
   CTradeEngine      m_trade;          // Торговый модуль

   string            m_symbol;         // Символ (XAUUSD)
   int               m_magic;          // Magic Number
   ENUM_LOT_TYPE     m_lot_type;       // Тип расчета лота
   double            m_lot_value;      // Значение для лота (фикс или %)
   double            m_max_daily_loss; // Лимит убытка (%)
   CLogger           m_log;            // Логгер

public:
                     CSignalManager();
                    ~CSignalManager();

   bool              Init(string db_path, string symbol, int magic,
                          ENUM_LOT_TYPE lot_type, double lot_val, double max_loss, string start_time_jst);
   void              Deinit();

   // Основной цикл обработки (вызывается из OnTimer)
   void              OnTick();

private:
   void              HandleNewSignals();
   void              HandleModifySignals();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSignalManager::CSignalManager() : m_log("SignalManager")
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSignalManager::~CSignalManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Инициализация всех подсистем                                     |
//+------------------------------------------------------------------+
bool CSignalManager::Init(string db_path, string symbol, int magic,
                          ENUM_LOT_TYPE lot_type, double lot_val, double max_loss, string start_time_jst)
{
   m_symbol = symbol;
   m_magic = magic;
   m_lot_type = lot_type;
   m_lot_value = lot_val;
   m_max_daily_loss = max_loss;

   m_log.Info(StringFormat("Инициализация: DB=%s, Symbol=%s, Magic=%d", db_path, symbol, magic));

   if(!m_db.Open(db_path)) 
   {
      m_log.Error("Не удалось открыть базу данных");
      return false;
   }
   
   if(!m_risk.Init(symbol, start_time_jst)) 
   {
      m_log.Error("Не удалось инициализировать RiskManager");
      return false;
   }
   
   if(!m_trade.Init(symbol, magic)) 
   {
      m_log.Error("Не удалось инициализировать TradeEngine");
      return false;
   }

   m_log.Info("Все модули успешно инициализированы.");
   return true;
}

//+------------------------------------------------------------------+
//| Деинициализация                                                  |
//+------------------------------------------------------------------+
void CSignalManager::Deinit()
{
   m_db.Close();
}

//+------------------------------------------------------------------+
//| Основной метод, вызываемый по таймеру                            |
//+------------------------------------------------------------------+
void CSignalManager::OnTick()
{
   // 1. Проверяем лимиты риска ( Daily Loss + JST Time)
   m_risk.CheckDailyLoss(m_max_daily_loss);

   if(!m_risk.IsTradingAllowed())
   {
      m_log.Debug("Торговля заблокирована (лимиты или время). Ожидание...");
      // Если лимит превышен - закрываем всё (согласно ТЗ)
      m_trade.CloseAll();
      return;
   }

   // 2. Управление существующими позициями (перенос в БУ)
   m_trade.ManageBreakeven();

   // 3. Обработка новых сигналов из БД
   HandleNewSignals();
}

//+------------------------------------------------------------------+
//| Обработка сигналов со статусом PROCESS или MODIFY                |
//+------------------------------------------------------------------+
void CSignalManager::HandleNewSignals()
{
   SSignalData signals[];
   int count = m_db.GetPendingSignals(signals);
   
   if(count == 0)
   {
      // Если сигналов нет - логгируем в Debug, чтобы не спамить
      m_log.Debug("В базе данных нет сигналов для обработки (PROCESS/MODIFY).");
   }

   for(int i = 0; i < count; i++)
   {
      m_log.Info(StringFormat("Обработка сигнала ID:%lld [%s] Статус:%s", 
                 signals[i].id, signals[i].symbol, 
                 (signals[i].status == STATUS_PROCESS ? "PROCESS" : "MODIFY")));

      // Валидация символа
      if(signals[i].symbol != m_symbol && signals[i].symbol != "XAUUSD" && signals[i].symbol != "GOLD")
      {
         m_log.Warn(StringFormat("Сигнал ID:%lld игнорируется: несоответствие символа (%s != %s)", 
                    signals[i].id, signals[i].symbol, m_symbol));
         continue;
      }

      // Проверяем условия входа (диапазон + допуск 0.03)
      double current_price = 0;
      if(m_trade.CheckEntryRange(signals[i], current_price))
      {
         m_log.Info(StringFormat("Цена %.5f в диапазоне для сигнала ID:%lld. Подготовка к входу.", current_price, signals[i].id));
         // Рассчитываем лот
         double lot = m_risk.CalculateLot(current_price, signals[i].stop_loss, m_lot_type, m_lot_value);
         
         // Если риск в %, делим лот пополам, так как открываем две позиции (TP1 и TP2)
         if(m_lot_type == LOT_RISK_PERCENT)
         {
            lot = m_risk.NormalizeLot(lot / 2.0);
         }

         // Исполняем сигнал (OpenDualPosition закроет старые сделки сам)
         if(m_trade.OpenDualPosition(signals[i], lot))
         {
            PrintFormat("SM: Сигнал ID:%lld успешно исполнен.", signals[i].id);
            m_db.UpdateStatus(signals[i].id, STATUS_DONE);
         }
         else
         {
            m_db.UpdateStatus(signals[i].id, STATUS_ERROR);
         }
      }
      else
      {
         // Если цена ушла слишком далеко - по ТЗ игнорируем, но пометим в БД как DONE,
         // чтобы не пытаться войти бесконечно, пока статус PROCESS
         PrintFormat("SM: Цена %.5f вне диапазона для сигнала ID:%lld. Пропуск.", current_price, signals[i].id);
         m_db.UpdateStatus(signals[i].id, STATUS_DONE);
      }
   }
}
