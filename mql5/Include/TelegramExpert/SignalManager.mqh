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
   double            m_max_daily_loss; // Лимит убытка (%)
   double            m_max_sl_dist;    // Макс. дистанция SL
   double            m_lot1;           // Лот для первого ордера (фиксированный)
   double            m_lot2;           // Лот для второго ордера (фиксированный)
   CLogger           m_log;            // Логгер

public:
                     CSignalManager();
                    ~CSignalManager();

   bool              Init(string db_path, string symbol, int magic,
                          double lot_val1, double lot_val2, 
                          double max_loss, double max_sl_dist, string start_time_jst);
   void              Deinit();

   // Основной цикл обработки (вызывается из OnTimer)
   void              OnTick();

private:
   void              HandleNewSignals();
   void              HandleModifySignals();
   void              UpdateDashboard();
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
                          double lot_val1, double lot_val2, 
                          double max_loss, double max_sl_dist, string start_time_jst)
{
   m_symbol = symbol;
   m_magic = magic;
   m_lot1 = lot_val1;
   m_lot2 = lot_val2;
   m_max_daily_loss = max_loss;
   m_max_sl_dist = max_sl_dist;

   m_log.Info(StringFormat("Initialization: DB=%s, Symbol=%s, Magic=%d", db_path, symbol, magic));

   if(!m_db.Open(db_path)) 
   {
      m_log.Error("Could not open database");
      return false;
   }
   
   if(!m_risk.Init(symbol, start_time_jst)) 
   {
      m_log.Error("Could not initialize RiskManager");
      return false;
   }
   
   if(!m_trade.Init(symbol, magic)) 
   {
      m_log.Error("Could not initialize TradeEngine");
      return false;
   }

   m_log.Info("All modules successfully initialized.");
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
   m_risk.CheckDailyLoss(m_max_daily_loss, m_magic);

   if(!m_risk.IsTradingAllowed())
   {
      m_log.Debug("Trading locked (limits or time). Waiting...");
      // Если лимит превышен - закрываем всё (согласно ТЗ)
      m_trade.CloseAll();
      return;
   }

   // 2. Управление существующими позициями (перенос в БУ)
   m_trade.ManageBreakeven();

   // 3. Обработка новых сигналов из БД
   HandleNewSignals();

   // 4. Обновление инфо-панели
   UpdateDashboard();
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
      // m_log.Debug("No pending signals in database (PROCESS/MODIFY).");
   }

   for(int i = 0; i < count; i++)
   {
      m_log.Info(StringFormat("Processing signal ID:%lld [%s] Status:%s", 
                 signals[i].id, signals[i].symbol, 
                 (signals[i].status == STATUS_PROCESS ? "PROCESS" : "MODIFY")));

      // Валидация символа
      if(signals[i].symbol != m_symbol && signals[i].symbol != "XAUUSD" && signals[i].symbol != "GOLD")
      {
         m_log.Warn(StringFormat("Signal ID:%lld ignored: symbol mismatch (%s != %s)", 
                    signals[i].id, signals[i].symbol, m_symbol));
         continue;
      }
      
      // Валидация дистанции стоп-лосса (Option 2)
      double sl_dist = 0;
      if(signals[i].direction == DIR_BUY)
         sl_dist = MathAbs(signals[i].entry_max - signals[i].stop_loss);
      else if(signals[i].direction == DIR_SELL)
         sl_dist = MathAbs(signals[i].stop_loss - signals[i].entry_min);
         
      if(sl_dist > m_max_sl_dist)
      {
         m_log.Warn(StringFormat("Signal ID:%lld REJECTED: SL distance (%.2f) exceeds limit (%.2f)", 
                    signals[i].id, sl_dist, m_max_sl_dist));
         m_db.UpdateStatus(signals[i].id, STATUS_INVALID);
         continue;
      }

      // Проверяем условия входа (диапазон + допуск 0.03)
      double current_price = 0;
      if(m_trade.CheckEntryRange(signals[i], current_price))
      {
         m_log.Info(StringFormat("Price %.5f within range for signal ID:%lld. Preparing to enter.", current_price, signals[i].id));
         // Используем фиксированные лоты напрямую (нормализованные)
         double lot1 = m_risk.NormalizeLot(m_lot1);
         double lot2 = m_risk.NormalizeLot(m_lot2);

         // Исполняем сигнал (OpenDualPosition закроет старые сделки сам)
         if(m_trade.OpenDualPosition(signals[i], lot1, lot2))
         {
            PrintFormat("SM: Signal ID:%lld successfully executed.", signals[i].id);
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
         PrintFormat("SM: Price %.5f out of range for signal ID:%lld. Skipping.", current_price, signals[i].id);
         m_db.UpdateStatus(signals[i].id, STATUS_DONE);
      }
   }
}

//+------------------------------------------------------------------+
//| Обновление инфо-панели на графике                                |
//+------------------------------------------------------------------+
void CSignalManager::UpdateDashboard()
{
   string status = m_risk.IsLocked() ? "LOCKED (Limit Exceeded)" : "TRADING ALLOWED";
   datetime jst = m_risk.GetJSTTime();
   
   double start_equity = m_risk.GetStartingEquity(m_magic);
   double daily_pnl = m_risk.GetDailyPnL(m_magic);
   double daily_perc = m_risk.GetDailyPnLPercent(m_magic);
   
   double limit_usd = start_equity * (m_max_daily_loss / 100.0);
   double remaining_usd = limit_usd + daily_pnl; // daily_pnl отрицательный при убытке
   
   string text = "=== Telegram Signal Expert Dashboard ===\n";
   text += StringFormat("JST Time: %s\n", TimeToString(jst, TIME_MINUTES|TIME_SECONDS));
   text += StringFormat("Status: %s (Magic: %d)\n", status, m_magic);
   text += "----------------------------------------\n";
   text += StringFormat("Starting Equity: %.2f\n", start_equity);
   text += StringFormat("Day P/L: %.2f USD (%.2f%%)\n", daily_pnl, daily_perc);
   text += StringFormat("Loss Limit: %.2f USD (%.2f%%)\n", limit_usd, m_max_daily_loss);
   
   if(!m_risk.IsLocked())
      text += StringFormat("Room to Limit: %.2f USD\n", remaining_usd);
   else
      text += "!!! TRADING LOCKED UNTIL 07:10 JST !!!\n";

   Comment(text);
}
