# FalconEA v3 - Installation rapide

> Version courte. Guide complet dans [README.md](README.md), detail des correctifs dans [CHANGELOG_v3.md](CHANGELOG_v3.md).

## 1. Retirer l'ancienne version

Si une version precedente tourne : clic droit sur chaque graphique -> **Liste des Experts** -> **Supprimer**.

Deux EA partageant le meme magic number se marchent dessus (notamment sur la limite de perte journaliere).

## 2. Copier les fichiers

`Ctrl+Shift+D` dans MT5 -> dossier `MQL5/` :

| Depuis le depot | Vers |
|---|---|
| `Experts/FalconEA.mq5` | `MQL5/Experts/` |
| `Include/FalconEA/*.mqh` (4 fichiers) | `MQL5/Include/FalconEA/` |

Ecraser les anciens fichiers. Le sous-dossier `Include/FalconEA/` est obligatoire : le code fait `#include <FalconEA\...>`.

## 3. Compiler

MetaEditor -> ouvrir `FalconEA.mq5` -> **F7** -> attendu : `0 errors, 0 warnings`.

Si `cannot open include file` : les `.mqh` sont mal places, retour a l'etape 2.

## 4. Lancer

`Ctrl+N` (Navigateur) -> **Expert Consultants** -> glisser **FalconEA** sur un graphique -> cocher **Autoriser le trading algorithmique** -> verifier que le bouton **Trading Algo** de la barre d'outils est actif.

Pour le multi-symboles : **une seule instance**, avec `InpSymbols = EURUSD,XAUUSD`.

## 5. Backtester AVANT le reel

`Ctrl+R` -> XAUUSD -> H1 -> "Chaque tick basee sur les vraies ticks" -> 1 an minimum.

Viser : profit factor > 1.3, drawdown < 20 %.

Puis : demo 4-8 semaines, puis reel avec un petit capital.
