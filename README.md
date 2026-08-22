# FalconEA v3.0

Expert Advisor MetaTrader 5 (MQL5). Multi-symboles - Filtre de news - Sorties partielles - Gestion du risque integree.

> **Nouveau en v3** : 8 bugs corriges (dont 2 qui empechaient purement et simplement certaines fonctions de marcher) + 3 modes de signal. Voir [CHANGELOG_v3.md](CHANGELOG_v3.md).

---

## Avertissement

Le trading automatise comporte un **risque eleve de perte en capital**. Ce projet est educatif, ce n'est pas un conseil financier.

```
Backtest (1 an minimum)  ->  Demo (4-8 semaines)  ->  Reel (petit capital)
```

---

## 1. Architecture

```
                        +--------------------------+
                        |      FalconEA.mq5        |  <- chef d'orchestre
                        +------------+-------------+
          +-----------------+--------+------+------------------+
          v                 v               v                  v
 +----------------+ +--------------+ +-------------+ +---------------+
 | SignalEngine   | | RiskManager  | |TradeManager | |  NewsFilter   |
 | "Quand entrer?"| | "Combien     | | "Ouvrir et  | | "Est-ce le    |
 | 3 modes        | |  risquer ?"  | |  gerer"     | |  bon moment?" |
 +----------------+ +--------------+ +-------------+ +---------------+
```

| Fichier | Role |
|---|---|
| `Experts/FalconEA.mq5` | Boucle principale, filtres, envoi des ordres |
| `Include/FalconEA/SignalEngine.mqh` | Quand entrer (3 modes de signal) |
| `Include/FalconEA/RiskManager.mqh` | Taille de lot, perte journaliere, spread, marge |
| `Include/FalconEA/TradeManager.mqh` | Ordres, TP1 partiel, break-even, trailing |
| `Include/FalconEA/NewsFilter.mqh` | Blocage autour des annonces economiques |

---

## 2. Installation

**Etape 1** - Dans MT5 : `Ctrl+Shift+D` -> ouvre le dossier de donnees -> entrer dans `MQL5/`

**Etape 2** - Copier les fichiers :

```
   DEPOT                                    MQL5/
   Experts/FalconEA.mq5            ---->    Experts/FalconEA.mq5
   Include/FalconEA/*.mqh          ---->    Include/FalconEA/*.mqh
                                                     ^ sous-dossier OBLIGATOIRE
```

**Etape 3** - MetaEditor -> ouvrir `FalconEA.mq5` -> `F7` -> `0 errors, 0 warnings`

**Etape 4** - MT5 -> `Ctrl+N` (Navigateur) -> Expert Consultants -> glisser **FalconEA** sur un graphique -> cocher **Autoriser le trading algorithmique** -> bouton **Trading Algo** actif

> Si une ancienne version tourne deja : retire-la d'abord (clic droit sur le graphique -> Liste des Experts -> Supprimer), sinon deux robots avec le meme magic number se marchent dessus.

---

## 3. Logique de decision

```
  Nouvelle bougie cloturee
            |
            v
   Historique/indicateurs prets ? --non--> on attend (message au journal)
            | oui
            v
   Session horaire OK ? --non--> on attend
            | oui
            v
   Cooldown ecoule ? --non--> on attend
            | oui
            v
   +--------------------------------------+
   | SIGNAL selon le mode choisi          |
   |  CROSS         : croisement strict   |
   |  CROSS_WINDOW  : croisement + N bars |
   |  PULLBACK      : repli sur EMA rapide|
   |  + filtre EMA200 + filtre RSI        |
   +----------+---------------------------+
              v signal detecte
   News ? --oui--> bloque (log)
              | non
   Spread <= 20% de l'ATR ? --non--> ignore (log)
              | oui
   Places disponibles ? --non--> ignore (log)
              | oui
   Marge suffisante ? --non--> ignore (log)
              | oui
              v
   SL = 1.5xATR   TP = 3xATR   Lot = 1% du capital
   SL/TP ajustes au stops level du broker
              v
         ORDRE ENVOYE
```

Puis pendant la vie du trade (a chaque tick) :

```
  Gain atteint 50 % du chemin vers le TP
        -> TP1 : 50 % du volume cloture + SL au prix d'entree
  Gain atteint 1 x ATR
        -> break-even confirme
  Gain atteint 1.5 x ATR
        -> trailing stop a 1 x ATR du prix
```

Le signal est calcule sur des **barres cloturees** uniquement : ce que montre le backtest correspond a ce que fait le robot en reel (aucun repaint).

---

## 4. Parametres principaux

### Signal
| Parametre | Defaut | Explication |
|---|---|---|
| `InpSignalMode` | CROSS_WINDOW | Mode de detection. PULLBACK = beaucoup plus de trades |
| `InpCrossWindow` | 3 | Combien de barres un croisement reste exploitable |
| `InpEmaFast/Slow/Trend` | 9/21/200 | Les trois moyennes mobiles |
| `InpUseTrendFilter` | true | N'acheter qu'au-dessus de l'EMA200 |
| `InpUseRsiFilter` | true | Eviter surachat/survente. `false` = plus de trades |
| `InpSlAtrMult` / `InpTpAtrMult` | 1.5 / 3.0 | SL et TP en multiples d'ATR (ratio 1:2) |
| `InpCooldownBars` | 2 | Barres d'attente entre deux trades sur le meme symbole |

### Risque
| Parametre | Defaut | Explication |
|---|---|---|
| `InpRiskPercent` | 1.0 | % du capital risque par trade |
| `InpMaxDailyLoss` | 4.0 | Perte journaliere max -> tout est ferme |
| `InpMaxSpreadAtrPct` | 20 | Spread max en % de l'ATR (s'adapte au symbole) |
| `InpMaxPosTotal` | 3 | 3 positions x 1 % = **3 % expose simultanement** |

### Break-even & trailing (en multiples d'ATR)
| Parametre | Defaut | Explication |
|---|---|---|
| `InpBeTriggerAtr` | 1.0 | BE quand le gain atteint 1x l'ATR |
| `InpTrailStartAtr` | 1.5 | Trailing demarre a 1.5x l'ATR |
| `InpTrailDistAtr` | 1.0 | Le SL suit a 1x l'ATR de distance |

### Sorties partielles
| Parametre | Defaut | Explication |
|---|---|---|
| `InpUsePartial` | true | Activer le TP1 |
| `InpPartialTrigger` | 0.5 | A mi-chemin du TP |
| `InpPartialPct` | 50 | 50 % du volume encaisse |

---

## 5. Depannage

| Symptome | Solution |
|---|---|
| `cannot open include file` | Les `.mqh` doivent etre dans `MQL5/Include/FalconEA/` |
| Smiley triste sur le graphique | Bouton **Trading Algo** + case "Autoriser le trading algorithmique" |
| Aucun trade | Regarde l'onglet **Experts** : le robot dit pourquoi il n'entre pas. Sinon passe en `MODE_PULLBACK` ou descends en M15 |
| `(chargement...)` dans le panneau | Normal quelques secondes, le temps que MT5 telecharge l'historique du symbole |
| Ordres refuses | Corrige en v3 (stops level). Si ca persiste : augmente `InpSlAtrMult` |
| Deux robots en conflit | Un seul EA par magic number. Utilise `InpSymbols = EURUSD,XAUUSD` sur **une** instance |

---

## 6. Ou regarder

- **Onglet Experts** (en bas de MT5) : chaque decision loggee (achat, vente, news, spread, limite, cooldown)
- **Panneau** en haut a gauche du graphique : mode actif, positions, perte du jour, spread et ATR par symbole
- **Onglet Trade** : SL/TP qui bougent en direct

---

## 7. Backtest obligatoire avant tout

`Ctrl+R` -> Expert `FalconEA` -> XAUUSD -> H1 -> modelisation **"Chaque tick basee sur les vraies ticks"** -> 1 an minimum.

Objectifs a viser : **profit factor > 1.3**, **drawdown < 20 %**. Compare les configurations decrites dans [CHANGELOG_v3.md](CHANGELOG_v3.md) avant de choisir.

---

## Licence

MIT - voir [LICENSE](LICENSE).
