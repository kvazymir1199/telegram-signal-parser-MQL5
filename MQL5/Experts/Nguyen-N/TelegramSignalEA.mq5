//+------------------------------------------------------------------+
//|                                           TelegramSignalEA.mq5   |
//|                                  Copyright 2026, Nguyen-N        |
//|                                             https://example.com  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Nguyen-N"
#property link      "https://example.com"
#property version   "1.00"
#property strict

//--- Include custom modules
#include <Nguyen-N\SignalReader.mqh>
#include <Nguyen-N\RiskManager.mqh>
#include <Nguyen-N\TradeExecutor.mqh>
#include <Nguyen-N\PositionManager.mqh>

//--- Input parameters
input group             "Trading Settings"
input double            InpLotSize = 0.01;         // Lot size for each order
input int               InpMaxSlippage = 30;       // Max slippage (pips)
input int               InpMaxEntryDeviation = 30; // Max entry deviation (pips)
input long              InpMagicNumber = 123456;   // Magic number

input group             "Risk Management"
input double            InpMaxDailyLossPct = 3.0;  // Max daily loss (%)

input group             "File Settings"
input string            InpSignalFile = "signals.csv"; // Path to signal file (relative to MQL5/Files)

//--- Global objects
CSignalReader           *signalReader;
CRiskManager            *riskManager;
CTradeExecutor          *tradeExecutor;
CPositionManager        *positionManager;

long                    last_processed_signal_id = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialize objects
   signalReader    = new CSignalReader(InpSignalFile);
   riskManager     = new CRiskManager(InpMaxDailyLossPct);
   tradeExecutor   = new CTradeExecutor(InpLotSize, InpMaxSlippage, InpMaxEntryDeviation, InpMagicNumber);
   positionManager = new CPositionManager(InpMagicNumber);

   Print("Telegram Signal EA Initialized.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   delete signalReader;
   delete riskManager;
   delete tradeExecutor;
   delete positionManager;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Risk Management Check
   if(!riskManager.IsTradingAllowed())
     {
      // If risk limit reached, close all positions and stop
      if(riskManager.IsDisabled())
        {
         tradeExecutor.CloseAllPositions();
        }
      return;
     }

   // 2. Manage Existing Positions (TP1 to BE logic)
   positionManager.ManagePositions();

   // 3. Read New Signals
   TradingSignal signals[];
   if(signalReader.ReadSignals(signals))
     {
      // We take the latest signal from the file (last element)
      int last_idx = ArraySize(signals) - 1;
      TradingSignal current_signal = signals[last_idx];

      // Check if it's a new signal
      if(current_signal.id > last_processed_signal_id)
        {
         PrintFormat("New signal detected: ID %d, Symbol %s, Dir %s",
                     current_signal.id, current_signal.symbol, current_signal.direction);

         // 4. Close all existing positions before following new signal
         tradeExecutor.CloseAllPositions();

         // 5. Execute new signal
         if(tradeExecutor.ExecuteSignal(current_signal))
           {
            last_processed_signal_id = current_signal.id;
           }
        }
     }
  }
//+------------------------------------------------------------------+
