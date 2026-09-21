# 06. Experience and skills ("Magic and skills")

The window opens via the "Magic and skills" button, F2, or E, **starting only from location 2**
(on location 2 the tutorial opens it automatically, page 8). While the window is open, the game
is paused (`_fgamelogic` doesn't update the world), enemies are hidden (`_fhideallenemies`)
[code: `_fshowupgradeswindow`, `_fhandlegui`].

## Experience (`_vexperience`)

| Source | Value | Code |
|---|---|---|
| Raid repulsed | +20 | `_fnextlevel` |
| Moving to location L | +10·L | `_fnextlocation` |
| Survival start | = 100 | `_finitsurvival` |
| Buying a skill | −price | `_fdoupgrades` |
| Reverting a skill ("minus") | +price/2 | `_fdoupgrades` |
| Cancel (undoes all changes since the window was opened) | full refund | `_fcancelqueryupgrades` |

Killing monsters **doesn't** grant experience. Over the whole campaign: 180·20 + 10·(2+3+4+5+6) = 3800 exp.

## Skills [code: `_finitbalancedata`, `_fhandlegui`, `_fdoupgrades`, `_fupgradetowerbuildingskills`]

id — the internal upgrade-event code (`tupgradeseventt\type`).

| id | Button | Price (exp) | Max levels | Variable | Effect per level |
|---|---|---|---|---|---|
| 1 | Towers Damage | 50 | 10 (while `upgrader < 1.05`) | `_vtowersdamageupgrader` +0.005 | all `LandDamage`/`AirDamage` of prototypes and towers **×upgrader** (see below) |
| 2 | Towers Attack Speed | 80 | 5 | `_vtowersspeedupgrader` −0.02 | all `RateOfFire` ×upgrader (lower = faster) |
| 4 | Towers Attack Range | 50 | 12 (while `upgrader < 1.06`) | `_vtowersrangeupgrader` +0.005 | all `AttackRange` ×upgrader |
| 3 | Gold Income | 35 | 20 | `_vgolddiscountrate` 0.6 → +0.02 | income per raid `Round(rate·100)` (60 → 100 gold) |
| 5 | Disassemble Rate | 30 | 5 | `_vselldiscountrate` 0.75 → +0.05 (max 1.0) | refund on selling |
| 6 | Cold Magic | 100 | 5 | `_vcoldmagic` | unlocks Icerock; freeze strength `freeze·cold`; balloon bombs freeze for `30·cold` |
| 7 | Fire Magic | 100 | 5 | `_vfiremagic` | unlocks Flame; fire strength `min(fm,5)·fire` |
| 10 | Fire Magic level 6 | 200 | 1 (fm 5→6) | `_vfiremagic = 6` | Magic tower ignites: `burn = airDamage·5` ticks of 1 HP |
| 8 | Poison Magic | 100 | 5 | `_vpoisonmagic` | Plant poisons: `poisonTime = PoisonCoof·pm` ticks, damage `PoisonDamage`/tick |
| 9 | People's Resistance | 80 | 5 | `_vpplresistance` | divisor for damage to inhabitants `3·res + 33` |

Prices **don't grow** with level. `_2_begin` has other starting values (range max
1.05, speed 50, gold 50, …), but they're overwritten by `_finitbalancedata` before the game starts —
the values in the table are the ones that apply.

### How the multiplier is applied (important for an accurate remake)

`_fdoupgrades(downgrade, cancel)` on purchase: `upgrader += inc`, then
`_fupgradetowerbuildingskills(kind, 0)`, which multiplies **by the current upgrader**
all 5×11 prototypes and all built towers (`range` and its range circle, `rateOfFire`
with rounding, `landDamage`/`airDamage`). Since upgrader grows with every level,
the cumulative multiplier after n levels is:

- damage/radius: `Π_{k=1..n} (1 + 0.005·k)` (10 damage levels → ×1.3104; 12 radius levels → ×1.47)
- speed: `Π_{k=1..n} (1 − 0.02·k)` (5 levels → 0.98·0.96·0.94·0.92·0.90 = ×0.732 of the period).

Reverting divides by the current upgrader, then decreases it. After loading a save, multipliers
are rebuilt from scratch by level (`param_2 = 1`: loop `k=1..level`, `m = 1 + inc·k`,
`value *= m`) — the same products. **Original bug:** in this branch, for attack speed
the loop over *built towers* multiplies `rateOfFire` not by the cumulative `m`, but `level` times
by the global `_vtowersspeedupgrader` (already equal to `1 − 0.02·level`): after loading with
5 levels, prototypes get ×0.732 while existing towers get ×0.9⁵ = 0.59
[code: `_fupgradetowerbuildingskills`, branch `param_1 == 2 && param_2 == 1`].

Cost on reverting: `experience += price / 2` (a regular "minus") or `price`
(cancel fully refunds the purchase; canceling a revert charges half). The "minus"
buttons are only shown when level > 0. OK closes the window and clears the queue;
Cancel undoes every operation in the queue in reverse order.

Besides the skills themselves, Cold Magic = 0 hides the Icerock button, Fire Magic = 0 hides Flame; buttons
are dynamically laid out in a row (`_fupdateupgradebuttons`).
