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
   bool              m_include_manual; // Учитывать ручные сделки в P/L
   CLogger           m_log;            // Логгер

public:
                     CRiskManager();
                    ~CRiskManager();

   bool              Init(string symbol_name, string start_time_jst, bool include_manual = false);

   // Проверка возможности торговли (время и лимиты)
   bool              IsTradingAllowed();

   // Расчет лота
   double            CalculateLot(double entry_price, double sl_price, ENUM_LOT_TYPE type, double lot_value);

   // Мониторинг эквити
   void              CheckDailyLoss(double max_loss_percent, long magic);

   // Получение текущего времени JST
   datetime          GetJSTTime() { return TimeGMT() + JST_OFFSET; }

   // Методы для инфо-панели
   double            GetStartingEquity(long magic);
   double            GetDailyPnL(long magic);
   double            GetDailyPnLPercent(long magic);
   bool              IsLocked()           const { return m_trading_locked; }

   // Нормализация лота под требования брокера
   double            NormalizeLot(double lot);

private:
   void              UpdateResetTime();
   double            CalculateDailyPnL(long magic);
   
   // Хелперы для расчета профита
   double            GetPriceAtTime(string symbol, datetime time_gmt);
   double            CalculateProfit(string symbol, ENUM_POSITION_TYPE type, double lot, double price_open, double price_close);

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
   m_include_manual(false),
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
bool CRiskManager::Init(string symbol_name, string start_time_jst, bool include_manual)
{
   if(!m_symbol.Name(symbol_name)) return false;

   m_include_manual = include_manual;
   m_trading_locked = false;

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
         m_log.Info("Limits reset. Trading allowed.");
         m_trading_locked = false;
      }
      m_starting_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      UpdateResetTime();
   }
   
   if(m_trading_locked)
   {
      m_log.Warn("Trading locked due to daily loss limit excess.");
   }

   return !m_trading_locked;
}

//+------------------------------------------------------------------+
//| Расчет лота (Только Фикс)                                        |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLot(double entry_price, double sl_price, ENUM_LOT_TYPE type, double lot_value)
{
   // Теперь всегда фиксированный лот, нормализуем под требования брокера
   return NormalizeLot(lot_value);
}

//+------------------------------------------------------------------+
//| Проверка дневного убытка (динамический расчет по Magic)           |
//+------------------------------------------------------------------+
void CRiskManager::CheckDailyLoss(double max_loss_percent, long magic)
{
   if(m_trading_locked) return;

   double daily_pnl = CalculateDailyPnL(magic);
   double start_equity = AccountInfoDouble(ACCOUNT_EQUITY) - daily_pnl;
   
   if(start_equity <= 0) return;

   double draw_down = -daily_pnl / start_equity * 100.0;

   if(draw_down >= max_loss_percent)
   {
      m_trading_locked = true;
      m_log.Error(StringFormat("CRITICAL LOSS (Magic:%lld)! %.2f%% >= %.2f%%. Trading locked until next session (JST).",
                  magic, draw_down, max_loss_percent));
   }
}

//+------------------------------------------------------------------+
//| Геттеры для инфо-панели                                          |
//+------------------------------------------------------------------+
double CRiskManager::GetStartingEquity(long magic) 
{
   return AccountInfoDouble(ACCOUNT_EQUITY) - CalculateDailyPnL(magic);
}

double CRiskManager::GetDailyPnL(long magic)
{
   return CalculateDailyPnL(magic);
}

double CRiskManager::GetDailyPnLPercent(long magic)
{
   double start_equity = GetStartingEquity(magic);
   return (start_equity > 0) ? (CalculateDailyPnL(magic) / start_equity * 100.0) : 0;
}

//+------------------------------------------------------------------+
//| Расчет P/L дня (Realized + Floating) по Magic                    |
//+------------------------------------------------------------------+
double CRiskManager::CalculateDailyPnL(long magic)
{
   double total_pnl = 0;
   
   // Рассчитываем время начала дня в серверных часах
   datetime start_of_day_gmt = m_next_reset_time - 86400;
   int server_offset = (int)(TimeCurrent() - TimeGMT());
   datetime start_of_day_server = start_of_day_gmt + server_offset;

   // 1. Считаем закрытые сделки из истории за сегодня (относительно 07:10 JST)
   // Сначала собираем тикеты закрытия, т.к. HistorySelectByPosition сбрасывает контекст HistorySelect.
   if(HistorySelect(start_of_day_server, TimeCurrent()))
   {
      int total_deals = HistoryDealsTotal();

      // Фаза 1: Собираем тикеты закрывающих сделок (OUT/INOUT)
      ulong out_tickets[];
      ArrayResize(out_tickets, 0);

      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         long deal_magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(m_include_manual || deal_magic == magic)
         {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
            {
               int size = ArraySize(out_tickets);
               ArrayResize(out_tickets, size + 1);
               out_tickets[size] = ticket;
            }
         }
      }

      // Фаза 2: Обрабатываем собранные тикеты
      for(int j = 0; j < ArraySize(out_tickets); j++)
      {
         // Восстанавливаем контекст полной истории за день перед чтением каждого тикета
         HistorySelect(start_of_day_server, TimeCurrent());

         ulong ticket = out_tickets[j];
         long pos_id = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         double lot = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         ENUM_POSITION_TYPE pos_type = (HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

         // Находим сделку входа для этой позиции (меняет контекст — поэтому восстанавливаем выше)
         if(HistorySelectByPosition(pos_id))
         {
            int d_total = HistoryDealsTotal();
            datetime entry_time = 0;
            for(int d = 0; d < d_total; d++)
            {
               ulong d_ticket = HistoryDealGetTicket(d);
               if(HistoryDealGetInteger(d_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
               {
                  entry_time = (datetime)HistoryDealGetInteger(d_ticket, DEAL_TIME);
                  pos_type = (HistoryDealGetInteger(d_ticket, DEAL_TYPE) == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
                  break;
               }
            }

            if(entry_time > 0)
            {
               if(entry_time < start_of_day_server)
               {
                  // Сделка была открыта ВЧЕРА. Берем цену на момент сброса.
                  double p_reset = GetPriceAtTime(symbol, start_of_day_gmt);
                  double p_out = HistoryDealGetDouble(ticket, DEAL_PRICE);
                  if(p_reset > 0)
                     total_pnl += CalculateProfit(symbol, pos_type, lot, p_reset, p_out);
                  else
                     total_pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
               }
               else
               {
                  // Сделка открыта и закрыта СЕГОДНЯ. Берем профит полностью.
                  total_pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
                  total_pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                  total_pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
               }
            }
         }
      }
   }

   // 2. Считаем текущие открытые позиции
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         if(m_include_manual || pos_magic == magic)
         {
            datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);
            string symbol = PositionGetString(POSITION_SYMBOL);
            double lot = PositionGetDouble(POSITION_VOLUME);
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            if(pos_time < start_of_day_server)
            {
               // Позиция открыта ВЧЕРА. Считаем профит относительно цены на момент сброса.
               double p_reset = GetPriceAtTime(symbol, start_of_day_gmt);
               double p_now = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
               if(p_reset > 0)
                  total_pnl += CalculateProfit(symbol, pos_type, lot, p_reset, p_now);
               else
                  total_pnl += PositionGetDouble(POSITION_PROFIT); // Fallback
            }
            else
            {
               // Позиция открыта СЕГОДНЯ. Считаем ее плавающий профит полностью.
               total_pnl += PositionGetDouble(POSITION_PROFIT);
               total_pnl += PositionGetDouble(POSITION_SWAP);
            }
         }
      }
   }

   return total_pnl;
}

//+------------------------------------------------------------------+
//| Получение цены инструмента на конкретный момент времени          |
//+------------------------------------------------------------------+
double CRiskManager::GetPriceAtTime(string symbol, datetime time_gmt)
{
   int server_offset = (int)(TimeCurrent() - TimeGMT());
   datetime server_time = time_gmt + server_offset;
   
   return iClose(symbol, PERIOD_M1, iBarShift(symbol, PERIOD_M1, server_time));
}

//+------------------------------------------------------------------+
//| Математический расчет профита                                    |
//+------------------------------------------------------------------+
double CRiskManager::CalculateProfit(string symbol, ENUM_POSITION_TYPE type, double lot, double price_open, double price_close)
{
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_size <= 0) return 0;
   
   double points = (type == POSITION_TYPE_BUY) ? (price_close - price_open) : (price_open - price_close);
   return (points / tick_size) * tick_value * lot;
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

   PrintFormat("RM: Limits will be reset at %02d:%02d JST (GMT: %s)",
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
