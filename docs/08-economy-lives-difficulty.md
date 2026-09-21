# 08. Economy, inhabitants, difficulty, survival, score

## Starting values [code: `_finitbalancedata`]

| Difficulty (`CurrentTitul`) | Menu item | Inhabitants (`_vlifes`) | Gold |
|---|---|---|---|
| 0 — normal | `new` | 100 | 200 |
| 1 — "Defenser – Hero" | `hard` | 25 | 200 |
| 2 — "Defenser – Legend" | `insane` | 1 | 500 |
| Survival | `hardcore` | 100 | 250, experience 100, location 2, title 0 |

Difficulties unlock sequentially: after finishing the campaign
`CurrentTitul += 1` (up to 2) and `MenusOpened = max(MenusOpened, CurrentTitul)`; finishing it
at title 2 sets `MasterFlag = 1` ("Master of Defense") [code: `_floadfinaltitres`].
The title image in the menu is `Data/Menu/titul<MenusOpened+MasterFlag>.png`.

Quick F5/F9 only work on titles 0–1 and not in survival; on title 2 they're disabled,
and the Save/Load buttons on the panel are always hidden (on other titles Save is only visible between
raids) [code: `_fmainloop`, `_fhandlelevels`, `_fesetvisible(…,1)` = hide].

## Gold (`_vgold`)

| Event | Change | Code |
|---|---|---|
| Killing a monster | `+raid\gold` (healer: ×2 / ÷10 in a boss raid) | `_fdeleteenemy` |
| End of raid (campaign) | `+Round(goldRate·100)`, goldRate 0.6..1.0 | `_fnextlevel` |
| End of raid (survival) | `+Round(goldRate·lifes)` | `_fnextlevel` |
| Building/upgrading | `−price` | `_fdecgold` |
| Selling | `+Round(sellRate·spent)` | `_freturngold` |
| Moving to location L | `gold = 200 + 20·L` (L=5: 350); before this, any excess > 200 → inhabitants | `_fnextlocation` |

Helps.txt claims income depends on the number of inhabitants — in the campaign this is
**not the case** (only in survival).

## Inhabitants = lives (`_vlifes`)

- A monster that reaches the end: `−Round(life% / (3·resistance + 33))`, boss ×5
  (see [04](04-enemies-raids.md)). An inhabitant that reaches the end: `+1`.
- **Hiring inhabitants with gold** [code: `_fnextlocation`, `_fhandlemapmenu`]: when moving to
  the next location, if `gold > 200`: `goldToSpend = gold − 100`,
  `extraLifes += goldToSpend \ 100`. These inhabitants aren't added immediately; instead they **walk
  onto the road one at a time** over the following raids (once the wait timer reaches 6.0) and must reach
  the end. The map shows "You have spent N gold to employ K people".
  After the final location, the remaining `extraLifes` and `(gold−100)\100` are added directly to
  the inhabitant count (`_fnextlocation` branch L=6, `_fcreatehighscoresmenu`).
- Game over when `lifes < 1` (campaign: Restart location / To menu screen; survival:
  the high-score screen).
- `_voldlifes` — inhabitants at the start of the raid; the difference is written to `missed[level]`.

## Monster health auto-balance [code: `_fhandlebalance`, `_vunitslifemultyplier`]

The multiplier `m` (starts at 1.0, reset on restart) is applied as
`maxLife = m · raid\life`. After every campaign raid:

```
if missed[level] > 0:               m -= missed[level] / 100        ; lost inhabitants → easier
if level > 3 and missed[level] = missed[level-1] = missed[level-2] = 0:
                                    m += 0.03                        ; three clean raids → harder
ceiling = 1 + location/10 ;  floor = 0.8
title 1: floor = 0.95, ceiling *= 1.1
title 2: floor = 1.0,  ceiling *= 1.2
m = clamp(m, floor, ceiling)
if lifes >= 201: m = 1.3
elif lifes < 20 and title = 0: m = 0.7
```

`missed[level]` is the number of **inhabitants lost** during raid `level` (not the number of
monsters that broke through). Auto-balance doesn't apply in survival (m = 1).

## Survival [code: `_finitsurvival`, `_floaddata`, `_fnextlevel`]

- Location 2, title 0, 100 inhabitants, 250 gold, 100 experience. The balloon is unavailable.
- Raids are generated randomly: raid n has `n\18 + 10` monsters of type `Rand(1,30)`
  (including flying ones); parameters come from `RaidsData7.csv` (column n): Life 85·n, Speed
  `1 + 0.021·n`, Armor n, Gold `(n−1)\20 + 1`. Flying units get armor ×0.8.
- There are no boss raids (every raid has ≥ 10 monsters).
- Income `Round(goldRate·lifes)`; experience +20 per raid; raids up to 200 (array), after that
  it reads past the array bounds [assumption: practically unreachable]. A raid past 200
  repeats the characteristics of the table's last row.
- Saving/loading `Survival.sav` only via buttons. Score = raid number.

## Score and high-score table [code: `_fcreatehighscoresmenu`, `_fsubmithighscores`]

- Campaign: `score = lifes` after the same gold gets converted twice:
  `_fnextlocation` (location 6 completed) unconditionally adds
  `(gold−100)\100 + extralifes`, then `_fcreatehighscoresmenu` adds `(gold−100)\100` again, if `gold > 200`.
- Survival: `score = _vcurlevel`.
- Submission: the string `TowerDefence|<name>|<score>|<mode>` → Base64 →
  `HiScoreURL?One=<b64>` (campaign) or `?Two=<b64>` (survival), opened in the browser
  via `ExecFile`. There's no local table.

## Restarts [code: `_frestartgame`, `_frestartlocation`]

- "Restart location" (game over / in-game menu): all objects are cleared,
  `curlevel = first[location]`, then `Location<L>.sav` is loaded (a snapshot of the moment the location
  was entered: gold/inhabitants/skills/towers at that time). Balance multiplier = 1.
- `_fclearlocationsaves` deletes `Location1..5.sav` and `Automatic.sav` (loop up to 5 —
  `Location6.sav` is kept), but not `Save.sav`; it's only called from the defeat screen
  ("to menu") and after the final credits. The in-game menu's "To menu" only writes
  `Automatic.sav` (if no enemies are alive) — "Continue" remains available.
- "Continue" in the main menu loads `Automatic.sav`.
