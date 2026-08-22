//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh |
//|  FalconEA v3 - Filtre d'annonces economiques                     |
//|  CORRECTIF v3 : cache par symbole (le cache v2 etait global et   |
//|  renvoyait le resultat d'un autre symbole pendant 60 s).         |
//+------------------------------------------------------------------+
#property copyright "FalconEA"
#property strict

enum ENUM_NEWS_LEVEL
  {
   NEWS_LEVEL_HIGH   = 0,  // Haute importance uniquement
   NEWS_LEVEL_MEDIUM = 1,  // Moyenne + haute
   NEWS_LEVEL_ALL    = 2   // Toutes
  };

class CNewsFilter
  {
private:
   bool              m_enabled;
   ENUM_NEWS_LEVEL   m_level;
   int               m_minBefore, m_minAfter;
   int               m_cacheSeconds;

   //--- CORRECTIF v3 : un cache par symbole (tableaux paralleles)
   string            m_cSym[];
   datetime          m_cTime[];
   bool              m_cRes[];
   string            m_cName[];

   int               FindSlot(const string symbol)
     {
      for(int i = 0; i < ArraySize(m_cSym); i++)
         if(m_cSym[i] == symbol) return(i);
      int n = ArraySize(m_cSym);
      ArrayResize(m_cSym, n+1);  ArrayResize(m_cTime, n+1);
      ArrayResize(m_cRes, n+1);  ArrayResize(m_cName, n+1);
      m_cSym[n]=symbol; m_cTime[n]=0; m_cRes[n]=false; m_cName[n]="";
      return(n);
     }

public:
                     CNewsFilter(void) : m_cacheSeconds(60) {}

   void              Init(const bool enabled, const ENUM_NEWS_LEVEL level,
                          const int minBefore, const int minAfter)
     {
      m_enabled   = enabled;
      m_level     = level;
      m_minBefore = minBefore;
      m_minAfter  = minAfter;
     }

   string            LastNewsName(const string symbol)
     {
      int s = FindSlot(symbol);
      return(m_cName[s]);
     }

   bool              IsBlocked(const string symbol)
     {
      if(!m_enabled) return(false);
      if(MQLInfoInteger(MQL_TESTER)) return(false);   // pas de calendrier au backtest

      int s = FindSlot(symbol);
      if((TimeCurrent() - m_cTime[s]) < m_cacheSeconds) return(m_cRes[s]);

      m_cTime[s] = TimeCurrent();
      m_cRes[s]  = CheckCalendar(symbol, m_cName[s]);
      return(m_cRes[s]);
     }

private:
   bool              CheckCalendar(const string symbol, string &outName)
     {
      string base   = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      string profit = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);

      datetime from = TimeCurrent() - m_minAfter *60;
      datetime to   = TimeCurrent() + m_minBefore*60;

      MqlCalendarValue values[];
      if(CalendarValueHistory(values, from, to) <= 0) return(false);

      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;

         if(m_level==NEWS_LEVEL_HIGH   && ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
         if(m_level==NEWS_LEVEL_MEDIUM && ev.importance == CALENDAR_IMPORTANCE_LOW)  continue;

         MqlCalendarCountry ct;
         if(!CalendarCountryById(ev.country_id, ct)) continue;

         if(ct.currency==base || ct.currency==profit)
           {
            outName = ct.currency + " - " + ev.name;
            return(true);
           }
        }
      outName = "";
      return(false);
     }
  };
//+------------------------------------------------------------------+
