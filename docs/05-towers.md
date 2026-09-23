# 05. Towers

## Types

| id | UI name | Files | Targets | Notes |
|---|---|---|---|---|
| 1 | Land tower | `Military.b3d`, `MilitaryPlace.b3d`, bullets `military1..5.b3d`, effect `MilitaryEff.b3d` | ground only | TargetMethod 2, 10 upgrades |
| 2 | Magic tower | `Magic.b3d`, `magic1..5.b3d`, `MagicEff.b3d` | air only | 5 upgrades; ignites at Fire Magic 6 |
| 3 | Plant | `Nature.b3d`, `nature1..5.b3d`, `NatureEff.b3d`/`PoisonEff.b3d` | both | 10 upgrades; poisons at Poison Magic |
| 4 | Icerock | `Freeze.b3d`, `freeze1..5.b3d`, `FreezeEff.b3d` | both | available at Cold Magic ≥ 1; freezes; "Stop attack" button |
| 5 | Flame | `Fire.b3d`, `FirePlace.b3d`, burn effect `MagicEff.b3d` (`_vfireexplprototype`; the `FireEff.b3d` in the data is an empty stub with alpha 0 and isn't loaded) | ground | available at Fire Magic ≥ 1; placed **on the road**; no bullets, ignites everything within radius 5 |
| 6 | (Balloon) | `Balloon.b3d` | — | created by `_fcreatetower(6)` only as a prototype object; the balloon itself — see [07](07-balloon.md) |

All per-level numeric parameters — `data/towers.json` (from Tower1..5.csv). In short:

| Tower | Damage (lvl0→10) | Radius | Period (ms, lvl0→max) | Price (build, upg1..) |
|---|---|---|---|---|
| Land | 20→220 (ground) | 10·1.1^lvl (10→25.9) | 982→300 | 30; 20,20,20,35,40,50,50,50,60,70 |
| Magic | 20→120 (air, 5 lvl) | 10·1.1^lvl | 828→468 | 30; 20,20,30,40,50 |
| Plant | 10→110 (both) | 10·1.1^lvl | 973→200 | 30; 20,25,30,35,40,50,60,70,80,90 |
| Icerock | 5→30 (both, 5 lvl); freeze 15→40 | 10·1.2^lvl (10→24.9) | 806→440 | 30; 30,30,30,30,40 |
| Flame | 0.3→1.2 (3 lvl); fire 55→220 | 5 | 366→266 | 10; 15,20,40 |

The displayed "Attack speed" = `(1000 - RateOfFire) / 10` [code: `_ftowerinfo`].

## Building [code: `_fbuildtower`, `_fcreatetower`, `_fplacetower`, `_fpositiontower`, `_fdecgold`]

1. Button/key 1–5: if `gold < price[lvl0]` — sound `oops2.wav`; otherwise a level-0
   tower is created in placement mode (`_vplacemode = 1`), tutorial step 2.
2. `_fcreatetower(type, level, hidden)`: a copy of the model, marker `*Place.b3d`, hitbox
   2.8×8.4×2.8; 21 sequences of 10 frames are extracted from the model
   (`ExtractAnimSeq(0..210 step 10)`; 1-based numbering: seq k = frames 10(k−1)..10k, i.e.
   level 0 idle = frames 0–10, upgrade to level 1 = 10–20, level 1 idle = 20–30); child `fire1` — the
   projectile launch point, `dno` — the base (texture `dno<L>.png`). Parameters are copied from the
   prototype `towerprototype[type][level]`; the range circle `range.b3d` is scaled by `range·2`.
   The animation `seq = 2·level+1` (idle) is started. `_vtowersamount += 1`.
   `hidden=1` — two hidden towers (Icerock and Flame) at (-100,100,-100) for the preview in the skills
   window; they aren't written to the save, and Tab skips them.
3. Every tick in placement mode: the marker follows the cursor across the location, a zone
   check runs (see [03](03-levels-locations.md)); LMB on an allowed spot (and not over buttons) →
   `_fpositiontower`: the tower is placed on the marker with a **random rotation** `Rnd(0,360)`,
   the base is tinted the location's color (Icerock outside location 3 uses (0,110,255)),
   `gold -= price`, `tower\spent += price`, sound `<type>_build.wav`, the tower is selected.
   RMB — cancel.

## Upgrading [code: `_fupgradetower`, `_fhandletowers`, `_ffinishtowerupgrade`]

- The "Upgrade"/U/R button/key for the selected tower: requires `level+1 <= maxUpgrades` and the tower
  to be in its idle animation (`AnimSeq = 2·level+1`). If `gold < price[level+1]` — `oops2`,
  otherwise `level += 1`, `gold -= price`, `spent += price`, a "start animation" flag is set.
- Then in `_fhandletowers`: when `AnimTime = 10` while idle — `seq = 2·level` is started
  (upgrade animation, speed 0.1 → 100 ticks); the progress bar = `AnimTime·10`.
  When it finishes → `Animate(seq 2·level+1)`, message "Tower upgraded", sound
  `update.wav`; **only at this point** does `_ffinishtowerupgrade` copy over the new
  level's parameters (damage, radius, period, freeze, fire, poison, splash, maxUpgrades, bullet) and
  rescale the range circle. During the animation the tower fires with the old parameters.
- "No more upgrades" when `level = maxUpgrades`.

## Selling [code: `_fselltower`, `_freturngold`, `_fdeletetower`]

`gold += Round(sellRate · spent)`, where `spent` is everything spent on the tower (build +
upgrades; when loading a save it's recomputed as the sum of level 0..level prices),
`sellRate` 0.75 → 1.0 via the Disassemble skill. The tower's flying bullets are removed.

## Target selection [code: `_fhandletowers`]

Every tick `tower\timer += 16` (ms). If the tower isn't stopped (`stopped = 0`):

- **TargetMethod 1** (Magic, Plant, Icerock, Flame): among non-inhabitant enemies within
  `range` that the tower can hit (air → `airDamage > 0`, ground →
  `landDamage > 0`), the **nearest** one is chosen; a monster the player has selected, if in range, gets
  absolute priority.
- **TargetMethod 2** (Land): if the current target is still in range, keep it; otherwise walk the
  enemy list **from the end** (last created → first) and take the first eligible one in
  range. The target is only remembered in `tower\target` if `_fshoot` returned 1.
- Clicking a monster assigns it as the target for every tower.

## Firing [code: `_fshoot(tower, enemy)`]

Returns 0 (can't: wrong target type/stopped), otherwise 1. Fires if
`timer > rateOfFire`, then `timer = 0`.

**Flame (type 5)** — no projectile: `enemy\burnTime = min(fireMagic,5) · tower\fire`,
`enemy\burnDamage = tower\landDamage` (0.3..1.2 per tick), the visual fire effect is sized
`(level+1)·0.3`. Radius 5, targets via TargetMethod 1.

**Everything else** — a bullet is created:

```
bullet\entity  = CopyEntity(bulletModel) at point fire1, PointEntity → enemy
bullet\target  = enemy;  bullet\speed = 0.4 units/tick;  bullet\tower = tower
bullet\damage  = air ? tower\airDamage : tower\landDamage
bullet\burn    = (fireMagic = 6 and tower.type = 2) ? damage·5 : 0
bullet\freeze  = coldMagic · tower\freeze
bullet\poison  = tower\poisonCoof · poisonMagic
sound: Land → exp1.wav, Magic/Icerock → exp2.wav (3D, from the tower)
```

## Bullet flight and impact [code: `_fupdatebullets`, `_fbulletdistance`]

Every tick: if a bullet is farther than `tower\range` from the tower, it's removed (as an
explosion). Otherwise it turns toward the target (for flying targets — toward the point
`y+3`), and if `_fbulletdistance < 1`:

```
if damage > armor: enemy\life -= (damage - armor)        ; otherwise no damage
if freeze > 0:     enemy\freeze = freeze                  ; overwritten, not summed
if poison > enemy\poisonTime: enemy\poisonTime = poison; poison effect (0.8); enemy\poisonDamage = tower\poisonDamage
if burn   > enemy\burnTime:   enemy\burnTime = burn; fire effect ((level+1)·0.3); enemy\burnDamage = 1.0
remove the bullet with an explosion (_fcreateexplosion: <type>Eff.b3d, scale max(0.1, level/maxUpg·0.7))
```

If the target has already died (`target = null`), the bullet flies straight until it leaves the radius.
`_fbulletdistance`: for ground targets — `EntityDistance`, for flying targets — distance to the target's point `(x, y+3, z)` [code: `_fbulletdistance`].

## Tower info (panel) [code: `_ftowerinfo`]

Lines: name `[level/max]`, Land Damage, Air Damage, Attack range (rounded), Attack speed
`(1000-rate)/10`, Freeze power `freeze·coldMagic`, Fire power
`Round(min(fm,5)·landDamage·fire)/10` (for Magic at fm=6: `airDamage·0.5`), Poison power
`Round(poisonMagic·poisonDamage·poisonCoof)/10`; Cost is shown in the tooltip. The
"Stop attack/Start attack" button is only shown on towers with freeze (`freeze·coldMagic > 0`).

## Other

- Selection: LMB on a tower (pick mode 3 for all towers, entity name = the object's handle),
  `selection.b3d` under the tower, the range circle is only visible on the selected tower.
- Tab (`_fswitchtonexttower`): moves to the next non-hidden tower in the list, the camera
  pans to it; active when `_vtowersamount > 3` (i.e. ≥ 2 real towers).
- RMB clears the selection and the panel.
- Global skills (damage/speed/radius) are applied multiplicatively to the prototypes and to
  existing towers — see [06](06-magic-skills.md).
