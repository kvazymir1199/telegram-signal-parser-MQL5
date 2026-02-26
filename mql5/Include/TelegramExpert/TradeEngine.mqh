//+------------------------------------------------------------------+
//|                                                  TradeEngine.mqh |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property strict

#include "Defines.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Класс для исполнения торговых операций и управления позициями    |
//+------------------------------------------------------------------+
class CTradeEngine
{
private:
   CTrade            m_trade;          // Класс для совершения сделок
   CPositionInfo     m_position;       // Класс для получения инфо о позициях
   CSymbolInfo       m_symbol;         // Класс для данных символа
   int               m_magic;          // Magic Number
   double            m_entry_range;    // Допуск входа (в единицах цены)
   CLogger           m_log;            // Логгер

public:
                     CTradeEngine();
                    ~CTradeEngine();

   bool              Init(string symbol_name, int magic, int entry_range_points = 300);

   // Проверка условий входа (диапазон + настраиваемый допуск)
   bool              CheckEntryRange(const SSignalData &signal, double &current_price);

   // Открытие двух позиций по сигналу
   bool              OpenDualPosition(const SSignalData &signal, double lot1, double lot2);

   // Мониторинг безубытка (после TP1)
   void              ManageBreakeven();

   // Закрытие всех позиций по Magic Number
   void              CloseAll();

private:
   bool              IsPositionExists(long signal_id, double tp_target);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeEngine::CTradeEngine() : m_magic(0), m_entry_range(0), m_log("TradeEngine")
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTradeEngine::~CTradeEngine()
{
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CTradeEngine::Init(string symbol_name, int magic, int entry_range_points)
{
   if(!m_symbol.Name(symbol_name)) return false;
   m_magic = magic;
   m_entry_range = entry_range_points * m_symbol.Point();
   m_trade.SetExpertMagicNumber(magic);
   m_trade.SetTypeFillingBySymbol(symbol_name);
   m_log.Info(StringFormat("Entry range tolerance: %d points (%.2f price units)", entry_range_points, m_entry_range));
   return true;
}

//+------------------------------------------------------------------+
//| Проверка диапазона входа с настраиваемым допуском                |
//+------------------------------------------------------------------+
bool CTradeEngine::CheckEntryRange(const SSignalData &signal, double &current_price)
{
   if(!m_symbol.RefreshRates()) return false;

   current_price = (signal.direction == DIR_BUY) ? m_symbol.Ask() : m_symbol.Bid();

   // Расширенный диапазон: [entry_min - допуск, entry_max + допуск]
   double range_min = signal.entry_min - m_entry_range;
   double range_max = signal.entry_max + m_entry_range;

   if(current_price >= range_min && current_price <= range_max)
      return true;

   m_log.Debug(StringFormat("Price %.5f out of extended range [%.5f - %.5f] (original [%.5f - %.5f] +%.2f tolerance).",
               current_price, range_min, range_max, signal.entry_min, signal.entry_max, m_entry_range));
   return false;
}

//+------------------------------------------------------------------+
//| Открытие двух позиций по одному сигналу                          |
//+------------------------------------------------------------------+
bool CTradeEngine::OpenDualPosition(const SSignalData &signal, double lot1, double lot2)
{
   // Очищаем рынок перед новым сигналом (согласно ТЗ)
   CloseAll();

   string comment = StringFormat("ID:%lld", signal.id);
   bool res1 = false, res2 = false;

   if(signal.direction == DIR_BUY)
   {
      res1 = m_trade.Buy(lot1, m_symbol.Name(), m_symbol.Ask(), signal.stop_loss, signal.take_profit_1, comment + "_TP1");
      res2 = m_trade.Buy(lot2, m_symbol.Name(), m_symbol.Ask(), signal.stop_loss, signal.take_profit_2, comment + "_TP2");
   }
   else
   {
      res1 = m_trade.Sell(lot1, m_symbol.Name(), m_symbol.Bid(), signal.stop_loss, signal.take_profit_1, comment + "_TP1");
      res2 = m_trade.Sell(lot2, m_symbol.Name(), m_symbol.Bid(), signal.stop_loss, signal.take_profit_2, comment + "_TP2");
   }

   // Если хоть один ордер открылся без SL или вообще не открылся - закрываем всё для безопасности
   if(!res1 || !res2)
   {
      m_log.Error(StringFormat("Dual position error. Order1: %s, Order2: %s",
                  res1 ? "OK" : m_trade.ResultRetcodeDescription(),
                  res2 ? "OK" : m_trade.ResultRetcodeDescription()));
      CloseAll();
      return false;
   }

   m_log.Info(StringFormat("Dual position opened for Signal ID:%lld. Tickets: %lld, %lld", 
               signal.id, m_trade.ResultOrder(), m_trade.ResultDeal()));
   return true;
}

//+------------------------------------------------------------------+
//| Логика переноса в безубыток после TP1                            |
//+------------------------------------------------------------------+
void CTradeEngine::ManageBreakeven()
{
   bool tp1_exists = false;
   long ticket_tp2 = 0;
   double open_price_tp2 = 0;
   double current_sl_tp2 = 0;

   // Просматриваем все открытые позиции советника
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(m_position.SelectByTicket(ticket))
      {
         if(m_position.Magic() == m_magic && m_position.Symbol() == m_symbol.Name())
         {
            string comment = m_position.Comment();
            if(StringFind(comment, "_TP1") >= 0) tp1_exists = true;
            if(StringFind(comment, "_TP2") >= 0)
            {
               ticket_tp2 = (long)ticket;
               open_price_tp2 = m_position.PriceOpen();
               current_sl_tp2 = m_position.StopLoss();
            }
         }
      }
   }

   // Если TP1 закрылся (его нет в рынке), а TP2 еще в рынке и его SL еще не в безубытке
   if(!tp1_exists && ticket_tp2 > 0)
   {
      // Проверяем, не в безубытке ли уже позиция (чтобы не спамить модификациями)
      if(MathAbs(current_sl_tp2 - open_price_tp2) > m_symbol.Point())
      {
         if(m_trade.PositionModify(ticket_tp2, open_price_tp2, m_position.TakeProfit()))
         {
            PrintFormat("TE: TP1 closed. Moving position #%lld to breakeven at %.5f", ticket_tp2, open_price_tp2);
         }
         else
         {
            PrintFormat("TE: Breakeven modification error: %s", m_trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Закрытие всех позиций и удаление ордеров                         |
//+------------------------------------------------------------------+
void CTradeEngine::CloseAll()
{
   // Закрываем позиции
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(m_position.SelectByTicket(ticket))
      {
         if(m_position.Magic() == m_magic)
         {
            if(!m_trade.PositionClose(ticket))
               PrintFormat("TE: Position close error #%lld: %s", ticket, m_trade.ResultRetcodeDescription());
         }
      }
   }

   // Удаляем отложенные ордера (на всякий случай, если они будут использоваться)
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == m_magic)
         {
            if(!m_trade.OrderDelete(ticket))
               PrintFormat("TE: Order delete error #%lld: %s", ticket, m_trade.ResultRetcodeDescription());
         }
      }
   }
}
