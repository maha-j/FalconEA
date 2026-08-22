# FalconEA v3.0 - Ce qui a ete corrige

## Les bugs trouves dans la v2 (et pourquoi ca ne tradait pas)

### Bug #1 - La sortie partielle ne se declenchait JAMAIS sur XAUUSD
**Cause.** La v2 detectait "TP1 deja pris ?" en regardant si le stop loss avait depasse le prix d'entree. Mais le break-even (declenche a 200 points fixes) arrivait **avant** le TP1 (declenche a 50 % de 3xATR). Sur l'or, 200 points = 2 $ alors que le TP est a ~30 $. Donc : BE d'abord -> SL au-dessus de l'entree -> la condition "deja fait" devenait vraie -> TP1 jamais execute.

**Correctif.** On interroge maintenant l'historique reel des deals de la position (`HistorySelectByPosition`). Fiable, et ca survit a un redemarrage de l'EA.

### Bug #2 - Break-even et trailing en points fixes
**Cause.** `InpBeTriggerPts = 200` est raisonnable sur EURUSD (20 pips) mais ridicule sur XAUUSD (2 $ quand l'ATR H1 vaut 10-15 $). Resultat : tous les trades passaient au break-even quasi immediatement puis se faisaient sortir a zero sur le moindre bruit.

**Correctif.** BE et trailing sont desormais des **multiples d'ATR** : `InpBeTriggerAtr = 1.0` signifie "BE quand le gain atteint 1x l'ATR", ce qui s'adapte automatiquement a chaque symbole.

### Bug #3 - Ordres refuses par le broker (`Invalid stops`)
**Cause.** Aucune verification de `SYMBOL_TRADE_STOPS_LEVEL`. Si le SL calcule tombait trop pres du prix, le broker refusait l'ordre.

**Correctif.** SL et TP sont repousses automatiquement a la distance minimale autorisee, a l'ouverture **et** a chaque modification.

### Bug #4 - Le signal etait perdu s'il etait bloque une seule barre
**Cause.** Le croisement EMA n'existe que sur **une** barre. Si a ce moment precis il y avait une news, un spread large ou 3 positions deja ouvertes, l'occasion disparaissait pour toujours.

**Correctif.** Nouveau mode `MODE_CROSS_WINDOW` (par defaut) : le croisement reste exploitable pendant N barres tant que la configuration reste valide.

### Bug #5 - Indicateurs lus avant d'etre calcules
**Cause.** Sur un symbole qui n'est pas celui du graphique, MT5 charge l'historique en arriere-plan. `CopyBuffer` echouait silencieusement et `GetSignal()` renvoyait "aucun signal" sans jamais rien dire.

**Correctif.** Controle `BarsCalculated()` + methode `IsReady()` + message dans le journal pendant le chargement.

### Bug #6 - La limite de perte journaliere se remettait a zero
**Cause.** L'equite de reference etait prise dans `OnInit()`. Tu perds 3 %, tu redemarres l'EA -> le compteur repart de zero, la protection saute.

**Correctif.** L'equite de reference est stockee dans une variable globale MT5, liee au jour et au magic number.

### Bug #7 - Cache du filtre de news partage entre symboles
**Cause.** Un seul cache global : si EURUSD etait verifie, XAUUSD recevait le meme resultat pendant 60 secondes.

**Correctif.** Un cache par symbole.

### Bug #8 - Filtre de spread inadapte
**Cause.** `InpMaxSpread = 30` points bloquait quasiment toutes les entrees sur l'or, ou le spread normal depasse souvent 30 points.

**Correctif.** Le spread max s'exprime maintenant en **% de l'ATR** (`InpMaxSpreadAtrPct = 20`), donc relatif a la volatilite du symbole.

---

## Nouveautes pour trader plus souvent

### 3 modes de signal (`InpSignalMode`)

| Mode | Frequence | Description |
|---|---|---|
| `MODE_CROSS` | Rare | Croisement strict - le comportement v2 |
| `MODE_CROSS_WINDOW` | Moyenne | Croisement valide N barres - **defaut recommande** |
| `MODE_PULLBACK` | Elevee | Pas besoin de croisement : entre des que le prix revient toucher l'EMA rapide dans le sens de la tendance |

### Anti-doublon et cooldown
`InpCooldownBars = 2` empeche le robot d'enchainer deux trades colles sur le meme symbole. Une seule entree par barre, garantie.

### Journal detaille (`InpVerboseLog`)
On voit maintenant **pourquoi** une entree est refusee : cooldown, spread, limite de positions, chargement en cours.

---

## Reglages recommandes

### Configuration prudente (pour commencer)
```
InpTimeframe     = H1
InpSignalMode    = MODE_CROSS_WINDOW
InpCrossWindow   = 3
InpUseTrendFilter= true
InpRiskPercent   = 0.5
InpMaxPosTotal   = 2
```
Quelques trades par semaine, selectifs.

### Configuration active (plus de trades)
```
InpTimeframe     = M15
InpSignalMode    = MODE_PULLBACK
InpUseTrendFilter= true
InpUseRsiFilter  = false
InpCooldownBars  = 3
InpRiskPercent   = 0.5
InpMaxPosTotal   = 3
```
Plusieurs trades par jour.

### Configuration rapide (M5 - uniquement apres un backtest concluant)
```
InpTimeframe     = M5
InpSignalMode    = MODE_PULLBACK
InpEmaFast       = 8
InpEmaSlow       = 21
InpEmaTrend      = 100
InpUseRsiFilter  = false
InpCooldownBars  = 5
InpMaxSpreadAtrPct = 25
InpRiskPercent   = 0.25
```
Beaucoup de trades. **Attention** : plus le timeframe est bas, plus le spread mange le resultat. Sur XAUUSD, le M5 est souvent non rentable a cause du spread. Le backtest le dira.

---

## La verite sur "trader vite"

Augmenter la frequence des trades n'augmente pas les gains - ca augmente **l'exposition au spread et au bruit du marche**. Un robot qui prend 3 trades par semaine avec 55 % de reussite gagne de l'argent. Le meme robot passe en M5 prendra 30 trades par semaine avec 48 % de reussite et perdra, parce que le spread est paye 10 fois plus souvent.

La seule facon de savoir ce qui marche **sur un broker donne, avec ses spreads reels** :

1. `Ctrl+R` -> Testeur de strategie
2. Expert `FalconEA`, symbole `XAUUSD`, periode `H1`
3. Modelisation : **"Chaque tick basee sur les vraies ticks"**
4. Periode : au moins **1 an**
5. Lancer chaque configuration ci-dessus et comparer : profit net, drawdown max, profit factor, nombre de trades

Ce qu'il faut regarder : un **profit factor > 1.3** et un **drawdown < 20 %**. Si une configuration fait +300 % avec 60 % de drawdown, elle explosera le compte en reel.

Ensuite seulement : demo 4 a 8 semaines, puis reel avec un petit capital.
