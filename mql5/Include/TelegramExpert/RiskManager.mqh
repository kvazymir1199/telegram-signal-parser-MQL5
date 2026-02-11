//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"
#include <Trade\SymbolInfo.mqh>
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Класс для управления рисками, лотами и временем JST              |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   CSymbolInfo       m_symbol;         // Инструмент для расчетов
   double            m_starting_equity;// Эквити на начало торгового дня (07:10 JST)
   bool              m_trading_locked; // Флаг блокировки торговли
   datetime          m_next_reset_time;// Время следующего сброса лимитов (GMT)
   CLogger           m_log;            // Логгер

public:
                     CRiskManager();
                    ~CRiskManager();

   bool              Init(string symbol_name, string start_time_jst);

   // Проверка возможности торговли (время и лимиты)
   bool              IsTradingAllowed();

   // Расчет лота
   double            CalculateLot(double entry_price, double sl_price, ENUM_LOT_TYPE type, double lot_value);

   // Мониторинг эквити
   void              CheckDailyLoss(double max_loss_percent);

   // Получение текущего времени JST
   datetime          GetJSTTime() { return TimeGMT() + JST_OFFSET; }

   // Нормализация лота под требования брокера
   double            NormalizeLot(double lot);

private:
   void              UpdateResetTime();

   int               m_target_hour;    // Час сброса (JST)
   int               m_target_min;     // Минута сброса (JST)
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager() :
   m_starting_equity(0),
   m_trading_locked(false),
   m_next_reset_time(0),
   m_target_hour(7),
   m_target_min(10),
   m_log("RiskManager")
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CRiskManager::Init(string symbol_name, string start_time_jst)
{
   if(!m_symbol.Name(symbol_name)) return false;

   // Парсинг времени "HH:MM"
   string parts[];
   if(StringSplit(start_time_jst, ':', parts) == 2)
   {
      m_target_hour = (int)StringToInteger(parts[0]);
      m_target_min  = (int)StringToInteger(parts[1]);
   }

   UpdateResetTime();
   m_starting_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return true;
}

//+------------------------------------------------------------------+
//| Проверка возможности торговли                                    |
//+------------------------------------------------------------------+
bool CRiskManager::IsTradingAllowed()
{
   datetime current_gmt = TimeGMT();

   // Если наступило время сброса - разблокируем и обновляем точку отсчета эквити
   if(current_gmt >= m_next_reset_time)
   {
      if(m_trading_locked)
      {
         m_log.Info("Лимиты сброшены. Торговля разрешена.");
         m_trading_locked = false;
      }
      m_starting_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      UpdateResetTime();
   }
   
   if(m_trading_locked)
   {
      m_log.Warn("Торговля заблокирована из-за превышения дневного лимита убытка.");
   }

   return !m_trading_locked;
}

//+------------------------------------------------------------------+
//| Расчет лота (Фикс или % от риска)                                |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLot(double entry_price, double sl_price, ENUM_LOT_TYPE type, double lot_value)
{
   if(type == LOT_FIXED) return NormalizeLot(lot_value);

   // Обновляем данные символа (TickValue может меняться брокером)
   if(!m_symbol.RefreshRates()) return m_symbol.LotsMin();

   // Расчет на основе процента риска от эквити
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = equity * (lot_value / 100.0);

   double sl_dist_points = MathAbs(entry_price - sl_price) / m_symbol.Point();
   if(sl_dist_points <= 0) return m_symbol.LotsMin();

   // Расчет стоимости одного пункта лота 1.0
   double tick_value = m_symbol.TickValue();
   double tick_size = m_symbol.TickSize();
   double point = m_symbol.Point();

   if(tick_size <= 0 || tick_value <= 0)
   {
      Print("RM: Ошибка данных символа (TickSize/TickValue <= 0)");
      return m_symbol.LotsMin();
   }

   // Лот = (Сумма риска) / (Дистанция SL в пунктах * Стоимость пункта)
   double lot = risk_amount / (sl_dist_points * (tick_value * point / tick_size));

   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
//| Проверка дневного убытка                                         |
//+------------------------------------------------------------------+
void CRiskManager::CheckDailyLoss(double max_loss_percent)
{
   if(m_trading_locked) return;
   if(m_starting_equity <= 0) m_starting_equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double draw_down = (m_starting_equity - current_equity) / m_starting_equity * 100.0;

   if(draw_down >= max_loss_percent)
   {
      m_trading_locked = true;
      m_log.Error(StringFormat("КРИТИЧЕСКИЙ УБЫТОК! %.2f%% >= %.2f%%. Торговля заблокирована до следующего дня (JST).",
                  draw_down, max_loss_percent));
   }
}

//+------------------------------------------------------------------+
//| Расчет следующего времени сброса (JST -> GMT)                    |
//+------------------------------------------------------------------+
void CRiskManager::UpdateResetTime()
{
   datetime current_gmt = TimeGMT();

   // Конвертируем JST время в GMT для точки отсчета
   // JST = GMT + 9, значит GMT = JST - 9
   int target_gmt_hour = m_target_hour - 9;

   if(target_gmt_hour < 0)
      target_gmt_hour += 24;

   MqlDateTime dt;
   TimeToStruct(current_gmt, dt);

   dt.hour = target_gmt_hour;
   dt.min = m_target_min;
   dt.sec = 0;

   m_next_reset_time = StructToTime(dt);

   // Если расчетное время уже в прошлом, планируем на следующие сутки
   if(m_next_reset_time <= current_gmt)
   {
      m_next_reset_time += 86400;
   }

   PrintFormat("RM: Лимиты будут сброшены в %02d:%02d JST (GMT: %s)",
               m_target_hour, m_target_min, TimeToString(m_next_reset_time));
}

//+------------------------------------------------------------------+
//| Нормализация лота под правила брокера                            |
//+------------------------------------------------------------------+
double CRiskManager::NormalizeLot(double lot)
{
   double step = m_symbol.LotsStep();
   double min_lot = m_symbol.LotsMin();
   double max_lot = m_symbol.LotsMax();

   double normalized = MathFloor(lot / step) * step;

   if(normalized < min_lot) normalized = min_lot;
   if(normalized > max_lot) normalized = max_lot;

   return normalized;
}
