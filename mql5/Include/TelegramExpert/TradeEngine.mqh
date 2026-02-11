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

public:
                     CTradeEngine();
                    ~CTradeEngine();

   bool              Init(string symbol_name, int magic);

   // Проверка условий входа (диапазон + допуск 0.03)
   bool              CheckEntryRange(const SSignalData &signal, double &current_price);

   // Открытие двух позиций по сигналу
   bool              OpenDualPosition(const SSignalData &signal, double lot);

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
CTradeEngine::CTradeEngine() : m_magic(0)
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
bool CTradeEngine::Init(string symbol_name, int magic)
{
   if(!m_symbol.Name(symbol_name)) return false;
   m_magic = magic;
   m_trade.SetExpertMagicNumber(magic);
   m_trade.SetTypeFillingBySymbol(symbol_name);
   return true;
}

//+------------------------------------------------------------------+
//| Проверка диапазона входа согласно ТЗ                             |
//+------------------------------------------------------------------+
bool CTradeEngine::CheckEntryRange(const SSignalData &signal, double &current_price)
{
   if(!m_symbol.RefreshRates()) return false;

   current_price = (signal.direction == DIR_BUY) ? m_symbol.Ask() : m_symbol.Bid();

   // 1. Прямое попадание в диапазон
   if(current_price >= signal.entry_min && current_price <= signal.entry_max)
      return true;

   // 2. Проверка допуска 0.03 (30 pips)
   if(signal.direction == DIR_BUY)
   {
      // Для BUY цена не должна быть выше entry_max более чем на 0.03
      if(current_price > signal.entry_max && (current_price - signal.entry_max) <= MAX_ENTRY_DEVIATION)
         return true;
   }
   else if(signal.direction == DIR_SELL)
   {
      // Для SELL цена не должна быть ниже entry_min более чем на 0.03
      if(current_price < signal.entry_min && (signal.entry_min - current_price) <= MAX_ENTRY_DEVIATION)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Открытие двух позиций по одному сигналу                          |
//+------------------------------------------------------------------+
bool CTradeEngine::OpenDualPosition(const SSignalData &signal, double lot)
{
   // Очищаем рынок перед новым сигналом (согласно ТЗ)
   CloseAll();

   string comment = StringFormat("ID:%lld", signal.id);
   bool res1 = false, res2 = false;

   if(signal.direction == DIR_BUY)
   {
      res1 = m_trade.Buy(lot, m_symbol.Name(), m_symbol.Ask(), signal.stop_loss, signal.take_profit_1, comment + "_TP1");
      res2 = m_trade.Buy(lot, m_symbol.Name(), m_symbol.Ask(), signal.stop_loss, signal.take_profit_2, comment + "_TP2");
   }
   else
   {
      res1 = m_trade.Sell(lot, m_symbol.Name(), m_symbol.Bid(), signal.stop_loss, signal.take_profit_1, comment + "_TP1");
      res2 = m_trade.Sell(lot, m_symbol.Name(), m_symbol.Bid(), signal.stop_loss, signal.take_profit_2, comment + "_TP2");
   }

   // Если хоть один ордер открылся без SL или вообще не открылся - закрываем всё для безопасности
   if(!res1 || !res2)
   {
      PrintFormat("TE: Ошибка открытия дуальной позиции. Ордер1: %s, Ордер2: %s",
                  res1 ? "OK" : m_trade.ResultRetcodeDescription(),
                  res2 ? "OK" : m_trade.ResultRetcodeDescription());
      CloseAll();
      return false;
   }

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
            PrintFormat("TE: Ордер TP1 закрыт. Перенос позиции #%lld в безубыток на %.5f", ticket_tp2, open_price_tp2);
         }
         else
         {
            PrintFormat("TE: Ошибка переноса в безубыток: %s", m_trade.ResultRetcodeDescription());
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
               PrintFormat("TE: Ошибка закрытия позиции #%lld: %s", ticket, m_trade.ResultRetcodeDescription());
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
               PrintFormat("TE: Ошибка удаления ордера #%lld: %s", ticket, m_trade.ResultRetcodeDescription());
         }
      }
   }
}
