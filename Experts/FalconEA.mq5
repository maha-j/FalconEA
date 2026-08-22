//+------------------------------------------------------------------+
//|                                                     FalconEA.mq5 |
//|  FalconEA v3.0 - Expert Advisor multi-symboles                   |
//|                                                                  |
//|  CORRECTIFS v3 par rapport a v2 :                                |
//|   #1 Sortie partielle qui ne se declenchait jamais (XAUUSD)      |
//|   #2 Break-even / trailing en points fixes -> multiples d'ATR    |
//|   #3 Stops refuses par le broker (stops level non verifie)       |
//|   #4 Signal perdu si bloque une barre -> fenetre de validite     |
//|   #5 Indicateurs lus avant d'etre calcules (symbole hors chart)  |
//|   #6 Compteur de perte journaliere remis a zero au redemarrage   |
//|   #7 Cache du filtre de news partage entre symboles              |
//|   #8 Filtre de spread inadapte a XAUUSD                          |
//|   + Mode PULLBACK pour beaucoup plus d'opportunites              |
//|   + Anti-doublon : une seule entree par barre et par symbole     |
//|                                                                  |
//|  Usage educatif. Backtest -> demo -> reel. Pas un conseil.       |
//+------------------------------------------------------------------+
#property copyright "FalconEA"
#property version   "3.00"
#property strict

#include <FalconEA\SignalEngine.mqh>
#include <FalconEA\RiskManager.mqh>
#include <FalconEA\TradeManager.mqh>
#include <FalconEA\NewsFilter.mqh>

//--- ========================== INPUTS ==========================
input group "=== Symboles ==="
input string  InpSymbols        = "";      // Paires (ex: EURUSD,XAUUSD) - vide = graphique
input int     InpMaxPosPerSym   = 1;       // Positions max PAR symbole
input int     InpMaxPosTotal    = 3;       // Positions max TOTALES

input group "=== Signal ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT;   // Unite de temps
input ENUM_SIGNAL_MODE InpSignalMode = MODE_CROSS_WINDOW; // Mode de signal
input int     InpCrossWindow    = 3;       // Barres de validite du croisement
input int     InpEmaFast        = 9;       // EMA rapide
input int     InpEmaSlow        = 21;      // EMA lente
input int     InpEmaTrend       = 200;     // EMA de tendance
input bool    InpUseTrendFilter = true;    // Filtre de tendance EMA200
input bool    InpUseRsiFilter   = true;    // Filtre RSI
input int     InpRsiPeriod      = 14;      // Periode RSI
input int     InpRsiBuyMax      = 70;      // RSI max pour acheter
input int     InpRsiSellMin     = 30;      // RSI min pour vendre
input int     InpAtrPeriod      = 14;      // Periode ATR
input double  InpSlAtrMult      = 1.5;     // SL = ATR x
input double  InpTpAtrMult      = 3.0;     // TP = ATR x
input int     InpCooldownBars   = 2;       // Barres d'attente entre 2 trades (meme symbole)

input group "=== Filtre de news ==="
input bool    InpUseNews        = true;    // Activer le filtre de news
input ENUM_NEWS_LEVEL InpNewsLevel = NEWS_LEVEL_HIGH; // Importance minimale
input int     InpNewsMinBefore  = 30;      // Minutes de blocage AVANT
input int     InpNewsMinAfter   = 30;      // Minutes de blocage APRES

input group "=== Sorties partielles ==="
input bool    InpUsePartial     = true;    // Activer le TP1 partiel
input double  InpPartialTrigger = 0.5;     // Declenchement (0.5 = 50% du chemin vers TP)
input double  InpPartialPct     = 50.0;    // % du volume cloture au TP1

input group "=== Risque ==="
input double  InpRiskPercent    = 1.0;     // Risque par trade (% du capital)
input double  InpMaxDailyLoss   = 4.0;     // Perte journaliere max (%) - 0 = off
input double  InpMaxSpreadAtrPct= 20.0;    // Spread max en % de l'ATR - 0 = off
input double  InpMaxSpreadPts   = 0;       // Spread max en points (si ATR% = 0)

input group "=== Break-even & Trailing (en multiples d'ATR) ==="
input bool    InpUseBreakEven   = true;    // Activer le break-even
input double  InpBeTriggerAtr   = 1.0;     // BE declenche a X x ATR de gain
input double  InpBeOffsetAtr    = 0.1;     // Offset du BE (X x ATR)
input bool    InpUseTrailing    = true;    // Activer le trailing stop
input double  InpTrailStartAtr  = 1.5;     // Trailing demarre a X x ATR de gain
input double  InpTrailDistAtr   = 1.0;     // Distance du trailing (X x ATR)

input group "=== Sessions ==="
input bool    InpUseSessions    = false;   // Limiter aux heures definies
input int     InpStartHour      = 8;       // Heure de debut (serveur)
input int     InpEndHour        = 20;      // Heure de fin (serveur)

input group "=== Divers ==="
input ulong   InpMagic          = 202600;  // Magic number
input string  InpComment        = "FalconEA v3"; // Commentaire des ordres
input bool    InpVerboseLog     = true;    // Journal detaille

//--- ==================== CONTEXTE PAR SYMBOLE ====================
class CSymbolContext
  {
public:
   string            symbol;
   CSignalEngine     signal;
   datetime          lastBarTime;
   datetime          lastTradeBar;    // anti-doublon + cooldown
   bool              ready;

                     CSymbolContext(void) : lastBarTime(0), lastTradeBar(0), ready(false) {}

   bool              Init(const string sym)
     {
      symbol = sym;
      if(!SymbolSelect(sym, true))
        {
         Print("Symbole absent du Market Watch : ", sym);
         return(false);
        }
      //--- amorce le chargement de l'historique du symbole
      datetime dummy[];
      CopyTime(sym, InpTimeframe, 0, 10, dummy);

      return(signal.Init(sym, InpTimeframe,
                         InpEmaFast, InpEmaSlow, InpEmaTrend,
                         InpRsiPeriod, InpAtrPeriod,
                         InpRsiBuyMax, InpRsiSellMin,
                         InpUseTrendFilter, InpUseRsiFilter,
                         InpSignalMode, InpCrossWindow));
     }

   //--- CORRECTIF v3 : a la toute premiere barre on n'entre pas
   //--- (lastBarTime = 0 renvoyait "nouvelle barre" au demarrage)
   bool              IsNewBar(void)
     {
      datetime t = iTime(symbol, InpTimeframe, 0);
      if(t == 0) return(false);
      if(lastBarTime == 0) { lastBarTime = t; return(false); }
      if(t != lastBarTime) { lastBarTime = t; return(true); }
      return(false);
     }

   bool              CooldownOK(void)
     {
      if(InpCooldownBars <= 0 || lastTradeBar == 0) return(true);
      int barsSince = Bars(symbol, InpTimeframe, lastTradeBar, lastBarTime);
      return(barsSince >= InpCooldownBars);
     }
  };

//--- ========================= GLOBALS =========================
CSymbolContext *g_ctx[];
CRiskManager    g_risk;
CTradeManager   g_trades;
CNewsFilter     g_news;
bool            g_dailyStop = false;
datetime        g_lastPanel = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Controles de coherence
   if(InpEmaFast >= InpEmaSlow)
     { Print("EMA rapide doit etre < EMA lente."); return(INIT_PARAMETERS_INCORRECT); }
   if(InpTpAtrMult <= InpSlAtrMult)
      Print("Attention : TP <= SL, ratio risque/rendement defavorable.");
   if(InpPartialTrigger <= 0.0 || InpPartialTrigger >= 1.0)
     { Print("InpPartialTrigger doit etre entre 0 et 1."); return(INIT_PARAMETERS_INCORRECT); }

   //--- Liste des symboles
   string symbols[];
   string raw = InpSymbols;
   StringTrimLeft(raw); StringTrimRight(raw);

   if(raw == "")
     { ArrayResize(symbols,1); symbols[0] = _Symbol; }
   else
     {
      int n = StringSplit(raw, ',', symbols);
      for(int i=0;i<n;i++){ StringTrimLeft(symbols[i]); StringTrimRight(symbols[i]); }
     }

   int ok = 0;
   ArrayResize(g_ctx, ArraySize(symbols));
   for(int i=0;i<ArraySize(symbols);i++)
     {
      g_ctx[i] = new CSymbolContext();
      if(g_ctx[i].Init(symbols[i])) ok++;
      else { delete g_ctx[i]; g_ctx[i] = NULL; }
     }
   if(ok == 0) { Print("Aucun symbole valide."); return(INIT_FAILED); }

   g_risk.Init(InpMagic, InpRiskPercent, InpMaxDailyLoss, InpMaxSpreadPts, InpMaxSpreadAtrPct);
   g_trades.Init(InpMagic,
                 InpUseBreakEven, InpBeTriggerAtr, InpBeOffsetAtr,
                 InpUseTrailing, InpTrailStartAtr, InpTrailDistAtr,
                 InpUsePartial, InpPartialTrigger, InpPartialPct);
   g_news.Init(InpUseNews, InpNewsLevel, InpNewsMinBefore, InpNewsMinAfter);

   EventSetTimer(1);

   string modeName = (InpSignalMode==MODE_CROSS) ? "CROISEMENT"
                   : (InpSignalMode==MODE_CROSS_WINDOW) ? "CROISEMENT+FENETRE" : "PULLBACK";
   Print("FalconEA v3 initialise | ", ok, " symbole(s) | mode ", modeName,
         " | equite de reference du jour : ", DoubleToString(g_risk.DayStartEquity(),2));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i=0;i<ArraySize(g_ctx);i++)
      if(g_ctx[i] != NULL) delete g_ctx[i];
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()  { Process(); }
void OnTimer() { Process(); }

//+------------------------------------------------------------------+
void Process()
  {
   g_risk.UpdateDay();

   static int lastDay = -1;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != lastDay) { lastDay = dt.day_of_year; g_dailyStop = false; }

   if(!g_dailyStop && g_risk.DailyLossReached())
     {
      g_dailyStop = true;
      g_trades.CloseAll();
      Print("STOP : perte journaliere de ", DoubleToString(g_risk.DayLossPct(),2),
            "% atteinte. Positions fermees, trading suspendu jusqu'a demain.");
     }

   for(int i=0;i<ArraySize(g_ctx);i++)
     {
      if(g_ctx[i] == NULL) continue;
      string sym = g_ctx[i].symbol;

      double atr = g_ctx[i].signal.Atr();

      //--- 1) Gestion des positions ouvertes : a chaque tick
      g_trades.Manage(sym, atr);

      //--- 2) Entrees : uniquement sur nouvelle barre cloturee
      if(g_dailyStop)          continue;
      if(!g_ctx[i].IsNewBar()) continue;

      if(!g_ctx[i].signal.IsReady())
        {
         if(InpVerboseLog) Print("[", sym, "] historique/indicateurs pas encore prets.");
         continue;
        }
      if(!SessionOK()) continue;
      if(!g_ctx[i].CooldownOK())
        {
         if(InpVerboseLog) Print("[", sym, "] cooldown actif.");
         continue;
        }

      //--- Le signal d'abord : on ne consulte le calendrier que si utile
      ENUM_SIGNAL sig = g_ctx[i].signal.GetSignal();
      if(sig == SIGNAL_NONE) continue;

      if(atr <= 0.0) { Print("[", sym, "] ATR indisponible."); continue; }

      if(g_news.IsBlocked(sym))
        { Print("NEWS [", sym, "] entree bloquee : ", g_news.LastNewsName(sym)); continue; }

      if(!g_risk.SpreadOK(sym, atr))
        {
         if(InpVerboseLog)
            Print("[", sym, "] spread trop large (", DoubleToString(g_risk.CurrentSpread(sym),0),
                  " pts) : entree ignoree.");
         continue;
        }

      if(g_trades.CountPositions(sym) >= InpMaxPosPerSym) continue;
      if(g_trades.CountAllPositions() >= InpMaxPosTotal)
        {
         if(InpVerboseLog) Print("Limite de ", InpMaxPosTotal, " positions atteinte.");
         continue;
        }

      double slDist = atr * InpSlAtrMult;
      double tpDist = atr * InpTpAtrMult;
      double lot    = g_risk.CalcLot(sym, slDist);
      if(lot <= 0.0) { Print("[", sym, "] lot nul, entree ignoree."); continue; }

      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double ask    = SymbolInfoDouble(sym, SYMBOL_ASK);
      double bid    = SymbolInfoDouble(sym, SYMBOL_BID);

      if(sig == SIGNAL_BUY)
        {
         if(!g_risk.MarginOK(sym, lot, ORDER_TYPE_BUY))
           { Print("[", sym, "] marge insuffisante."); continue; }
         double sl = NormalizeDouble(ask - slDist, digits);
         double tp = NormalizeDouble(ask + tpDist, digits);
         if(g_trades.OpenBuy(sym, lot, sl, tp, InpComment))
           {
            g_ctx[i].lastTradeBar = g_ctx[i].lastBarTime;
            Print("ACHAT [", sym, "] lot=", DoubleToString(lot,2),
                  " SL=", DoubleToString(sl,digits), " TP=", DoubleToString(tp,digits),
                  " ATR=", DoubleToString(atr,digits));
           }
        }
      else
        {
         if(!g_risk.MarginOK(sym, lot, ORDER_TYPE_SELL))
           { Print("[", sym, "] marge insuffisante."); continue; }
         double sl = NormalizeDouble(bid + slDist, digits);
         double tp = NormalizeDouble(bid - tpDist, digits);
         if(g_trades.OpenSell(sym, lot, sl, tp, InpComment))
           {
            g_ctx[i].lastTradeBar = g_ctx[i].lastBarTime;
            Print("VENTE [", sym, "] lot=", DoubleToString(lot,2),
                  " SL=", DoubleToString(sl,digits), " TP=", DoubleToString(tp,digits),
                  " ATR=", DoubleToString(atr,digits));
           }
        }
     }

   UpdatePanel();
  }

//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(TimeCurrent() == g_lastPanel) return;
   g_lastPanel = TimeCurrent();

   string modeName = (InpSignalMode==MODE_CROSS) ? "Croisement"
                   : (InpSignalMode==MODE_CROSS_WINDOW) ? "Croisement+fenetre" : "Pullback";

   string txt = StringFormat(
      "FalconEA v3  |  Mode: %s  |  Positions: %d/%d  |  Perte jour: %.2f%%  %s\n",
      modeName, g_trades.CountAllPositions(), InpMaxPosTotal,
      g_risk.DayLossPct(), g_dailyStop ? "STOP" : "");

   for(int i=0;i<ArraySize(g_ctx);i++)
     {
      if(g_ctx[i]==NULL) continue;
      string sym = g_ctx[i].symbol;
      double atr = g_ctx[i].signal.Atr();
      int    dg  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      txt += StringFormat("%-10s pos:%d  spread:%.0f  ATR:%s  %s\n",
                          sym,
                          g_trades.CountPositions(sym),
                          g_risk.CurrentSpread(sym),
                          DoubleToString(atr, dg),
                          g_ctx[i].signal.IsReady() ? "" : "(chargement...)");
     }
   Comment(txt);
  }

//+------------------------------------------------------------------+
bool SessionOK()
  {
   if(!InpUseSessions) return(true);
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(InpStartHour <= InpEndHour)
      return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
   return(dt.hour >= InpStartHour || dt.hour < InpEndHour);
  }
//+------------------------------------------------------------------+
