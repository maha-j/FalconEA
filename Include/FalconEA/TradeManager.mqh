//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|  FalconEA v3 - Execution & gestion des positions                 |
//|                                                                  |
//|  CORRECTIFS v3 (importants) :                                    |
//|                                                                  |
//|  BUG #1 - Sortie partielle jamais declenchee                     |
//|    En v2 on detectait "partial deja faite ?" en regardant si le  |
//|    SL avait depasse le prix d'entree. Or sur XAUUSD le break-even|
//|    (200 points fixes) se declenchait AVANT le TP1 (50% de 3xATR),|
//|    donc le SL passait au BE, la condition devenait vraie, et la  |
//|    sortie partielle n'arrivait JAMAIS.                           |
//|    => On interroge maintenant l'historique des deals de la       |
//|       position : fiable, et survit a un redemarrage de l'EA.     |
//|                                                                  |
//|  BUG #2 - Break-even / trailing en points fixes                  |
//|    200 / 300 / 150 points sont absurdes selon le symbole :       |
//|    sur XAUUSD (point = 0.01) cela fait 2$ / 3$ / 1.5$ alors que  |
//|    l'ATR H1 vaut 8-15$. Le BE se declenchait donc quasi          |
//|    instantanement et coupait tous les trades a zero.             |
//|    => BE et trailing sont desormais des MULTIPLES D'ATR.         |
//|                                                                  |
//|  BUG #3 - Stops refuses par le broker                            |
//|    Aucune verification de SYMBOL_TRADE_STOPS_LEVEL / freeze.     |
//|    => SL et TP sont maintenant repousses au minimum autorise.    |
//+------------------------------------------------------------------+
#property copyright "FalconEA"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CTradeManager
  {
private:
   CTrade            m_trade;
   CPositionInfo     m_pos;
   ulong             m_magic;

   bool              m_useBE;
   double            m_beTriggerAtr;    // BE declenche a X x ATR de gain
   double            m_beOffsetAtr;     // offset du BE en X x ATR

   bool              m_useTrail;
   double            m_trailStartAtr;
   double            m_trailDistAtr;

   bool              m_usePartial;
   double            m_partialTrigger;  // fraction du chemin vers le TP
   double            m_partialPct;

public:
                     CTradeManager(void) {}

   void              Init(const ulong magic,
                          const bool useBE, const double beTriggerAtr, const double beOffsetAtr,
                          const bool useTrail, const double trailStartAtr, const double trailDistAtr,
                          const bool usePartial, const double partialTrigger, const double partialPct)
     {
      m_magic          = magic;
      m_useBE          = useBE;
      m_beTriggerAtr   = beTriggerAtr;
      m_beOffsetAtr    = beOffsetAtr;
      m_useTrail       = useTrail;
      m_trailStartAtr  = trailStartAtr;
      m_trailDistAtr   = trailDistAtr;
      m_usePartial     = usePartial;
      m_partialTrigger = partialTrigger;
      m_partialPct     = partialPct;

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetAsyncMode(false);
     }

   int               CountPositions(const string symbol)
     {
      int c = 0;
      for(int i = PositionsTotal()-1; i >= 0; i--)
         if(m_pos.SelectByIndex(i) && m_pos.Magic()==m_magic && m_pos.Symbol()==symbol) c++;
      return(c);
     }

   int               CountAllPositions(void)
     {
      int c = 0;
      for(int i = PositionsTotal()-1; i >= 0; i--)
         if(m_pos.SelectByIndex(i) && m_pos.Magic()==m_magic) c++;
      return(c);
     }

   //--- Distance minimale imposee par le broker entre le prix et un stop
   double            MinStopDistance(const string symbol)
     {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      long   stops = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long   freeze= SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      long   lvl   = MathMax(stops, freeze);
      if(lvl <= 0) lvl = 10;             // marge de securite si le broker renvoie 0
      return((double)lvl * point);
     }

   //--- CORRECTIF v3 : ajuste SL/TP pour respecter le stops level
   void              NormalizeStops(const string symbol, const ENUM_ORDER_TYPE type,
                                    const double price, double &sl, double &tp)
     {
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double minD   = MinStopDistance(symbol);

      if(type == ORDER_TYPE_BUY)
        {
         if(sl > 0.0 && price - sl < minD) sl = price - minD;
         if(tp > 0.0 && tp - price < minD) tp = price + minD;
        }
      else
        {
         if(sl > 0.0 && sl - price < minD) sl = price + minD;
         if(tp > 0.0 && price - tp < minD) tp = price - minD;
        }
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
     }

   bool              OpenBuy(const string symbol, const double lot, double sl, double tp, const string comment)
     {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      NormalizeStops(symbol, ORDER_TYPE_BUY, ask, sl, tp);
      m_trade.SetTypeFillingBySymbol(symbol);
      if(!m_trade.Buy(lot, symbol, 0.0, sl, tp, comment))
        {
         Print("ACHAT [", symbol, "] refuse : ", m_trade.ResultRetcodeDescription(),
               " (", m_trade.ResultRetcode(), ")");
         return(false);
        }
      return(true);
     }

   bool              OpenSell(const string symbol, const double lot, double sl, double tp, const string comment)
     {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      NormalizeStops(symbol, ORDER_TYPE_SELL, bid, sl, tp);
      m_trade.SetTypeFillingBySymbol(symbol);
      if(!m_trade.Sell(lot, symbol, 0.0, sl, tp, comment))
        {
         Print("VENTE [", symbol, "] refusee : ", m_trade.ResultRetcodeDescription(),
               " (", m_trade.ResultRetcode(), ")");
         return(false);
        }
      return(true);
     }

   void              CloseAll(void)
     {
      for(int i = PositionsTotal()-1; i >= 0; i--)
         if(m_pos.SelectByIndex(i) && m_pos.Magic()==m_magic)
            m_trade.PositionClose(m_pos.Ticket());
     }

   //--- CORRECTIF v3 (BUG #1) : detection fiable de la sortie partielle
   //--- via l'historique des deals de la position.
   bool              PartialAlreadyDone(const long positionId)
     {
      if(!HistorySelectByPosition(positionId)) return(false);
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0) continue;
         long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
            return(true);          // un deal de sortie existe deja => partial faite
        }
      return(false);
     }

   //--- Gestion continue. L'ATR est passe en parametre : BE et trailing
   //--- sont desormais proportionnels a la volatilite du symbole.
   void              Manage(const string symbol, const double atr)
     {
      if(atr <= 0.0) return;
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double minD   = MinStopDistance(symbol);

      for(int i = PositionsTotal()-1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))    continue;
         if(m_pos.Magic() != m_magic)   continue;
         if(m_pos.Symbol() != symbol)   continue;

         ulong  ticket = m_pos.Ticket();
         long   posId  = m_pos.Identifier();
         long   type   = m_pos.PositionType();
         double open   = m_pos.PriceOpen();
         double sl     = m_pos.StopLoss();
         double tp     = m_pos.TakeProfit();
         double volume = m_pos.Volume();
         double cur    = (type==POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(symbol, SYMBOL_BID)
                         : SymbolInfoDouble(symbol, SYMBOL_ASK);

         //--- 1) SORTIE PARTIELLE (TP1)
         if(m_usePartial && tp > 0.0 && !PartialAlreadyDone(posId))
           {
            double pathTotal = MathAbs(tp - open);
            double pathDone  = (type==POSITION_TYPE_BUY) ? (cur-open) : (open-cur);

            if(pathTotal > 0.0 && pathDone/pathTotal >= m_partialTrigger)
              {
               double lotMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
               double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
               double closeVol = volume * m_partialPct / 100.0;
               if(lotStep > 0.0) closeVol = MathFloor(closeVol/lotStep)*lotStep;

               if(closeVol >= lotMin && (volume-closeVol) >= lotMin)
                 {
                  if(m_trade.PositionClosePartial(ticket, closeVol))
                    {
                     Print("TP1 [", symbol, "] ", DoubleToString(closeVol,2),
                           " lot cloture (", DoubleToString(m_partialPct,0), "%) -> SL au break-even");
                     double be = NormalizeDouble(open, digits);
                     if(PositionSelectByTicket(ticket))
                        SafeModify(symbol, ticket, type, cur, be, tp, minD, digits);
                    }
                 }
               else
                 {
                  //--- Volume trop petit pour partialiser : on passe direct au BE
                  double be = NormalizeDouble(open, digits);
                  SafeModify(symbol, ticket, type, cur, be, tp, minD, digits);
                 }
              }
           }

         //--- Relire l'etat (le volume/SL a pu changer)
         if(!PositionSelectByTicket(ticket)) continue;
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);

         double gain = (type==POSITION_TYPE_BUY) ? (cur-open) : (open-cur);

         //--- 2) BREAK-EVEN (en multiples d'ATR - CORRECTIF BUG #2)
         if(m_useBE && gain >= atr * m_beTriggerAtr)
           {
            double be = (type==POSITION_TYPE_BUY)
                        ? open + atr*m_beOffsetAtr
                        : open - atr*m_beOffsetAtr;
            be = NormalizeDouble(be, digits);
            bool need = (type==POSITION_TYPE_BUY) ? (sl < be) : (sl==0.0 || sl > be);
            if(need) SafeModify(symbol, ticket, type, cur, be, tp, minD, digits);
           }

         //--- 3) TRAILING STOP (en multiples d'ATR)
         if(m_useTrail && gain >= atr * m_trailStartAtr)
           {
            if(!PositionSelectByTicket(ticket)) continue;
            sl = PositionGetDouble(POSITION_SL);
            double newSl = (type==POSITION_TYPE_BUY)
                           ? cur - atr*m_trailDistAtr
                           : cur + atr*m_trailDistAtr;
            newSl = NormalizeDouble(newSl, digits);
            bool better = (type==POSITION_TYPE_BUY) ? (newSl > sl) : (sl==0.0 || newSl < sl);
            if(better) SafeModify(symbol, ticket, type, cur, newSl, tp, minD, digits);
           }
        }
     }

private:
   //--- Modification de position respectant le stops level du broker
   void              SafeModify(const string symbol, const ulong ticket, const long type,
                                const double cur, double sl, double tp,
                                const double minD, const int digits)
     {
      if(type == POSITION_TYPE_BUY)
        {
         if(sl > 0.0 && cur - sl < minD) sl = cur - minD;
        }
      else
        {
         if(sl > 0.0 && sl - cur < minD) sl = cur + minD;
        }
      sl = NormalizeDouble(sl, digits);
      if(!m_trade.PositionModify(ticket, sl, tp))
        {
         int rc = (int)m_trade.ResultRetcode();
         if(rc != TRADE_RETCODE_NO_CHANGES)
            Print("Modif SL [", symbol, "] echec : ", m_trade.ResultRetcodeDescription());
        }
     }
  };
//+------------------------------------------------------------------+
