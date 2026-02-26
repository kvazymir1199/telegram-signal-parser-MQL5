//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property strict

enum ENUM_LOG_LEVEL
{
   LOG_DEBUG,
   LOG_INFO,
   LOG_WARN,
   LOG_ERROR
};

class CLogger
{
private:
   string            m_prefix;
   ENUM_LOG_LEVEL    m_level;

public:
                     CLogger(string prefix = "EA") : m_prefix(prefix), m_level(LOG_INFO) {}
                    ~CLogger() {}

   void              SetLevel(ENUM_LOG_LEVEL level) { m_level = level; }
   
   void              Debug(string msg) { if(m_level <= LOG_DEBUG) Log("DEBUG", msg); }
   void              Info(string msg)  { if(m_level <= LOG_INFO)  Log("INFO",  msg); }
   void              Warn(string msg)  { if(m_level <= LOG_WARN)  Log("WARN",  msg); }
   void              Error(string msg) { if(m_level <= LOG_ERROR) Log("ERROR", msg); }

private:
   void              Log(string level_name, string msg)
   {
      string full_msg = StringFormat("[%s][%s] %s: %s", m_prefix, level_name, TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS), msg);
      Print(full_msg);
   }
};
