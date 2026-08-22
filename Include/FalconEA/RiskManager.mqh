//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|  FalconEA v3 - Gestion du risque                                 |
//|                                                                  |
//|  CORRECTIFS v3 :                                                 |
//|   - L'equite de debut de journee est PERSISTANTE (variable       |
//|     globale MT5) : redemarrer l'EA ne remet plus le compteur     |
//|     de perte journaliere a zero.                                 |
//|   - Spread max exprimable en % de l'ATR (adapte a XAUUSD)        |
//|   - Lot valide contre la marge disponible avant l'ordre          |
//+------------------------------------------------------------------+
#property copyright "FalconEA"
#property strict

class CRiskManager
  {
private:
   double            m_riskPercent;
   double            m_maxDailyLossPct;
   double            m_maxSpreadPoints;   // 0 = off
   double            m_maxSpreadAtrPct;   // 0 = off ; ex 15 => spread <= 15% de l'ATR
   ulong             m_magic;

   double            m_dayStartEquity;
   int               m_dayOfYear;

   string            GVName(void)     { return("FalconEA_DayEq_"  + (string)m_magic); }
   string            GVDayName(void)  { return("FalconEA_DayNum_" + (string)m_magic); }

public:
                     CRiskManager(void) : m_dayStartEquity(0.0), m_dayOfYear(-1) {}

   void              Init(const ulong magic, const double riskPercent, const double maxDailyLossPct,
                          const double maxSpreadPoints, const double maxSpreadAtrPct)
     {
      m_magic           = magic;
      m_riskPercent     = riskPercent;
      m_maxDailyLossPct = maxDailyLossPct;
      m_maxSpreadPoints = maxSpreadPoints;
      m_maxSpreadAtrPct = maxSpreadAtrPct;
      LoadOrResetDay();
     }

   //--- CORRECTIF v3 : on recupere l'equite de reference si elle existe
   //--- deja pour la journee en cours (survit a un redemarrage de l'EA).
   void              LoadOrResetDay(void)
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int today = dt.day_of_year;

      if(GlobalVariableCheck(GVDayName()) && GlobalVariableCheck(GVName()))
        {
         int storedDay = (int)GlobalVariableGet(GVDayName());
         if(storedDay == today)
           {
            m_dayStartEquity = GlobalVariableGet(GVName());
            m_dayOfYear      = today;
            return;
           }
        }
      ResetDay();
     }

   void              ResetDay(void)
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      m_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayOfYear      = dt.day_of_year;
      GlobalVariableSet(GVName(),    m_dayStartEquity);
      GlobalVariableSet(GVDayName(), (double)m_dayOfYear);
     }

   void              UpdateDay(void)
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_year != m_dayOfYear) ResetDay();
     }

   double            DayStartEquity(void) { return(m_dayStartEquity); }

   double            DayLossPct(void)
     {
      if(m_dayStartEquity <= 0.0) return(0.0);
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return((m_dayStartEquity - eq) / m_dayStartEquity * 100.0);
     }

   bool              DailyLossReached(void)
     {
      if(m_maxDailyLossPct <= 0.0) return(false);
      return(DayLossPct() >= m_maxDailyLossPct);
     }

   //--- CORRECTIF v3 : sur XAUUSD un spread de 30 points est courant,
   //--- l'ancien filtre bloquait presque toutes les entrees. On accepte
   //--- desormais un plafond relatif a la volatilite.
   bool              SpreadOK(const string symbol, const double atr)
     {
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);

      if(m_maxSpreadAtrPct > 0.0 && atr > 0.0 && point > 0.0)
        {
         double atrPoints = atr / point;
         return(spread <= atrPoints * m_maxSpreadAtrPct / 100.0);
        }
      if(m_maxSpreadPoints > 0.0)
         return(spread <= m_maxSpreadPoints);
      return(true);
     }

   double            CurrentSpread(const string symbol)
     {
      return((double)SymbolInfoInteger(symbol, SYMBOL_SPREAD));
     }

   //--- Lot pour risquer m_riskPercent sur une distance de SL donnee
   double            CalcLot(const string symbol, const double slDistancePrice)
     {
      if(slDistancePrice <= 0.0) return(0.0);

      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * m_riskPercent / 100.0;

      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0) return(0.0);

      double lossPerLot = slDistancePrice / tickSize * tickValue;
      if(lossPerLot <= 0.0) return(0.0);

      double lot = riskMoney / lossPerLot;

      double lotMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double lotMax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(lotStep > 0.0) lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(lotMin, MathMin(lotMax, lot));

      return(NormalizeDouble(lot, 2));
     }

   //--- CORRECTIF v3 : verifier la marge AVANT d'envoyer l'ordre,
   //--- sinon on recolte des "Not enough money" dans le journal.
   bool              MarginOK(const string symbol, const double lot, const ENUM_ORDER_TYPE type)
     {
      double price = (type == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(symbol, SYMBOL_BID);
      double margin = 0.0;
      if(!OrderCalcMargin(type, symbol, lot, price, margin)) return(true);
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      return(margin < free * 0.9);
     }
  };
//+------------------------------------------------------------------+
