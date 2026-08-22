//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|  FalconEA v3 - Moteur de signaux                                 |
//|                                                                  |
//|  CORRECTIFS v3 :                                                 |
//|   - Verification que les indicateurs sont CALCULES avant lecture |
//|     (indispensable pour les symboles hors graphique)             |
//|   - 3 modes de signal : CROSS / CROSS_WINDOW / PULLBACK          |
//|     => le signal n'est plus perdu s'il est bloque 1 barre        |
//|   - Filtre de tendance et RSI desactivables independamment       |
//+------------------------------------------------------------------+
#property copyright "FalconEA"
#property strict

enum ENUM_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

enum ENUM_SIGNAL_MODE
  {
   MODE_CROSS        = 0,  // Croisement strict (rare, prudent)
   MODE_CROSS_WINDOW = 1,  // Croisement valide N barres (recommande)
   MODE_PULLBACK     = 2   // Tendance + repli sur EMA rapide (frequent)
  };

class CSignalEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;

   int               m_hEmaFast, m_hEmaSlow, m_hEmaTrend, m_hRsi, m_hAtr;
   int               m_pEmaFast, m_pEmaSlow, m_pEmaTrend;

   int               m_rsiBuyMax, m_rsiSellMin;
   bool              m_useTrend, m_useRsi;
   ENUM_SIGNAL_MODE  m_mode;
   int               m_crossWindow;      // nb de barres pendant lesquelles un croisement reste valide

   //--- lecture securisee d'un buffer d'indicateur
   bool              Read(const int handle, const int start, const int count, double &buf[])
     {
      if(handle == INVALID_HANDLE) return(false);
      //--- CORRECTIF v3 : sur un symbole hors graphique, l'indicateur peut
      //--- ne pas etre encore calcule => CopyBuffer echouait en silence.
      int calc = BarsCalculated(handle);
      if(calc < start + count) return(false);
      return(CopyBuffer(handle, 0, start, count, buf) == count);
     }

public:
                     CSignalEngine(void) : m_hEmaFast(INVALID_HANDLE), m_hEmaSlow(INVALID_HANDLE),
                                           m_hEmaTrend(INVALID_HANDLE), m_hRsi(INVALID_HANDLE),
                                           m_hAtr(INVALID_HANDLE) {}
                    ~CSignalEngine(void) { Release(); }

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int emaFast, const int emaSlow, const int emaTrend,
                          const int rsiPeriod, const int atrPeriod,
                          const int rsiBuyMax, const int rsiSellMin,
                          const bool useTrend, const bool useRsi,
                          const ENUM_SIGNAL_MODE mode, const int crossWindow)
     {
      m_symbol = symbol;   m_tf = tf;
      m_pEmaFast = emaFast; m_pEmaSlow = emaSlow; m_pEmaTrend = emaTrend;
      m_rsiBuyMax = rsiBuyMax; m_rsiSellMin = rsiSellMin;
      m_useTrend = useTrend;   m_useRsi = useRsi;
      m_mode = mode;           m_crossWindow = MathMax(1, crossWindow);

      m_hEmaFast  = iMA(symbol, tf, emaFast,  0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow  = iMA(symbol, tf, emaSlow,  0, MODE_EMA, PRICE_CLOSE);
      m_hEmaTrend = iMA(symbol, tf, emaTrend, 0, MODE_EMA, PRICE_CLOSE);
      m_hRsi      = iRSI(symbol, tf, rsiPeriod, PRICE_CLOSE);
      m_hAtr      = iATR(symbol, tf, atrPeriod);

      if(m_hEmaFast==INVALID_HANDLE || m_hEmaSlow==INVALID_HANDLE || m_hEmaTrend==INVALID_HANDLE ||
         m_hRsi==INVALID_HANDLE || m_hAtr==INVALID_HANDLE)
        {
         Print("SignalEngine [", symbol, "] : handles KO. Err=", GetLastError());
         return(false);
        }
      return(true);
     }

   void              Release(void)
     {
      if(m_hEmaFast !=INVALID_HANDLE) IndicatorRelease(m_hEmaFast);
      if(m_hEmaSlow !=INVALID_HANDLE) IndicatorRelease(m_hEmaSlow);
      if(m_hEmaTrend!=INVALID_HANDLE) IndicatorRelease(m_hEmaTrend);
      if(m_hRsi     !=INVALID_HANDLE) IndicatorRelease(m_hRsi);
      if(m_hAtr     !=INVALID_HANDLE) IndicatorRelease(m_hAtr);
      m_hEmaFast=m_hEmaSlow=m_hEmaTrend=m_hRsi=m_hAtr=INVALID_HANDLE;
     }

   //--- Les donnees du symbole sont-elles pretes ?
   bool              IsReady(void)
     {
      int needed = MathMax(m_pEmaTrend, 60) + 10;
      if(Bars(m_symbol, m_tf) < needed) return(false);
      if(BarsCalculated(m_hEmaTrend) < needed) return(false);
      if(BarsCalculated(m_hAtr)      < 5)      return(false);
      return(true);
     }

   double            Atr(void)
     {
      double b[];
      if(!Read(m_hAtr, 1, 1, b)) return(0.0);
      return(b[0]);
     }

   double            EmaFastValue(void)
     {
      double b[];
      if(!Read(m_hEmaFast, 1, 1, b)) return(0.0);
      return(b[0]);
     }

   //--- Signal sur barres CLOTUREES uniquement (aucun repaint)
   ENUM_SIGNAL       GetSignal(void)
     {
      if(!IsReady()) return(SIGNAL_NONE);

      int need = m_crossWindow + 2;
      double fast[], slow[], trend[], rsi[];
      if(!Read(m_hEmaFast,  1, need, fast))  return(SIGNAL_NONE);
      if(!Read(m_hEmaSlow,  1, need, slow))  return(SIGNAL_NONE);
      if(!Read(m_hEmaTrend, 1, 1,    trend)) return(SIGNAL_NONE);
      if(!Read(m_hRsi,      1, 1,    rsi))   return(SIGNAL_NONE);

      //--- Read() renvoie du plus ANCIEN au plus RECENT.
      //--- Le dernier element = barre 1 (derniere cloturee).
      int    last     = need - 1;
      double fastCurr = fast[last], slowCurr = slow[last];
      double close1   = iClose(m_symbol, m_tf, 1);
      if(close1 <= 0.0) return(SIGNAL_NONE);

      bool trendUp   = (!m_useTrend) || (close1 > trend[0]);
      bool trendDown = (!m_useTrend) || (close1 < trend[0]);
      bool rsiBuyOK  = (!m_useRsi)   || (rsi[0] < m_rsiBuyMax);
      bool rsiSellOK = (!m_useRsi)   || (rsi[0] > m_rsiSellMin);

      bool bullState = (fastCurr > slowCurr);
      bool bearState = (fastCurr < slowCurr);

      //================= MODE 1 : croisement strict =================
      if(m_mode == MODE_CROSS)
        {
         bool up   = (fast[last-1] <= slow[last-1] && fastCurr >  slowCurr);
         bool down = (fast[last-1] >= slow[last-1] && fastCurr <  slowCurr);
         if(up   && trendUp   && rsiBuyOK)  return(SIGNAL_BUY);
         if(down && trendDown && rsiSellOK) return(SIGNAL_SELL);
         return(SIGNAL_NONE);
        }

      //====== MODE 2 : croisement encore valide sur N barres ========
      //--- CORRECTIF v3 : en v2, si le croisement tombait pendant une news,
      //--- un spread large ou le max de positions, le signal etait perdu
      //--- definitivement. Ici il reste exploitable m_crossWindow barres.
      if(m_mode == MODE_CROSS_WINDOW)
        {
         for(int k = last; k >= 1; k--)
           {
            bool up   = (fast[k-1] <= slow[k-1] && fast[k] >  slow[k]);
            bool down = (fast[k-1] >= slow[k-1] && fast[k] <  slow[k]);
            if(up)
              {
               if(bullState && trendUp && rsiBuyOK) return(SIGNAL_BUY);
               return(SIGNAL_NONE);   // croisement trouve mais conditions KO
              }
            if(down)
              {
               if(bearState && trendDown && rsiSellOK) return(SIGNAL_SELL);
               return(SIGNAL_NONE);
              }
           }
         return(SIGNAL_NONE);
        }

      //========= MODE 3 : tendance + repli sur l'EMA rapide =========
      //--- Beaucoup plus d'occasions : on n'attend plus le croisement,
      //--- on entre quand le prix revient toucher l'EMA rapide dans le
      //--- sens de la tendance etablie.
      double high1 = iHigh(m_symbol, m_tf, 1);
      double low1  = iLow (m_symbol, m_tf, 1);

      if(bullState && trendUp && rsiBuyOK)
        {
         bool touched = (low1 <= fastCurr);           // repli venu toucher l'EMA rapide
         bool closedAbove = (close1 > fastCurr);      // mais cloture repartie au-dessus
         if(touched && closedAbove) return(SIGNAL_BUY);
        }
      if(bearState && trendDown && rsiSellOK)
        {
         bool touched = (high1 >= fastCurr);
         bool closedBelow = (close1 < fastCurr);
         if(touched && closedBelow) return(SIGNAL_SELL);
        }
      return(SIGNAL_NONE);
     }
  };
//+------------------------------------------------------------------+
