# 04. Enemies and raids

## Raid spawn [code: `_fhandlelevels`, `_fnextlevel`]

State between raids: `_vlevelfinished = 1`, timer `_vingametime` grows by
**0.01 per tick** (≈ 0.6/s at 60 Hz).

1. When `_vingametime >= 10` (≈ 16.7 s wait) → `_vcreateenemiesmode = 1`, timer = 0.
   The "Save game" button is only visible between raids and is hidden during spawning
   (`_fesetvisible(btn, 1)` = hide, confirmed by `_fegetvisible`); on difficulty 2
   Save/Load are always hidden.
2. In creation mode, every `0.4` (≈ 40 ticks ≈ 0.67 s) the next monster of
   raid `raids[_vcurlevel]\monsters[_venemiescreated+1]` is created; the first one plays
   the `start.wav` sound. If the raid has `< 4` monsters, they're all **bosses** (`_fcreateenemy(boss=1)`).
3. Once all are created — `_vcreateenemiesmode = 0`, `_vlevelfinished = 0`,
   `_venemiescreated = 0`. A raid counts as repulsed when `_venemiesamount` (the number of living
   non-inhabitants) reaches 0 upon deleting an enemy with flag `param_3=1` → `_fnextlevel`.
4. Extra inhabitants (`_vextralifes`, bought with gold when changing location) come out
   one at a time: once the wait timer passes `6.0` and `_vextralifes > 0`, an
   inhabitant is created (`_fworkerid()` = `Rand(32,33)`, `34` in GamedevMode).

The tutorial resets `_vingametime` every tick while it's open; when the tutorial closes on
location 1, the timer is set to **-5** (an extra pause).

## Enemy creation [code: `_fcreateenemy(boss, unitId)`]

```
enemy\ext      = CopyEntity(units[id]\mesh) → ext_initentity
enemy\entity   = ext\entity
enemy\pathCopy = CopyEntity(location\paths[Rand(1,pathsCount)]); MoveEntity(±1 on X, 0..1 on Z)
enemy\marker   = FindChild(pathCopy, "path"); HideEntity
AlignEntity(entity → marker)
enemy\speed    = raid\speed / 10                       ; units/tick
enemy\maxLife  = _vunitslifemultyplier * raid\life
enemy\armor    = raid\armor
enemy\gold     = raid\gold
enemy\life     = maxLife
enemy\air      = units[id]\air
enemy\animSpeed= units[id]\animSpeed
enemy\freeze   = 0
enemy\unitId   = id;  enemy\boss = boss
if survival and air: armor = Round(armor * 0.8)
enemy\healer   = units[id]\healer
if healer <> 0:
    if not boss: maxLife *= 2; gold *= 2      ; healer in a regular raid
    else:        maxLife /= 2; gold /= 10     ; healer in a boss raid
    life = maxLife
enemy\worker   = units[id]\worker
enemy\healthBar= CopyEntity(health.b3d, parent=entity); MoveEntity(0, air + 3.5, 0)
if location <> 6: enemy\shadow = CopyEntity(shadow.b3d, parent=entity)
scale = _vcurlevel / 250 ; boss → 0.64 ; clamp <= 0.64
ScaleEntity(entity, 1+scale)                            ; monsters grow with raid number, boss ×1.64
MD2:  AnimateMD2(entity, loop, animSpeed*speed - scale/7.5, 0, 10)   ; frame 10 in loop mode
      ; never shown: MD2Model blends frame 9 → frame 0 (render_b == last → first)
B3D (healer): Animate(entity, loop, animSpeed*speed - scale/10)
if not worker: _venemiesamount += 1
NameEntity(entity, handle)   ; for CameraPick
```

The height of flying monsters is **baked into the model** (the entity's position on the
road is y≈0; bullets aim at `y+3`, effects are offset by +3 on Y) [code: `_fupdatebullets`,
`_fcreateduration`].

## Movement and update [code: `_fupdateenemies`]

Every tick, for every enemy:

1. **Healer** (`healer > 0`): for every enemy `e` within distance `d < healer·10`
   (= 400 units for Health, i.e. practically everyone on the map), add
   `life += healer / (d·10)`, but only if the result wouldn't exceed maxLife (otherwise
   skip). At d=1 this is 4 HP/tick, at d=10 — 0.4 HP/tick: only nearby units are meaningfully healed.
2. **Movement**: if `freeze <= 0` — normal (see [03](03-levels-locations.md#enemy-path-path1b3d));
   if `freeze > 0` — step `speed / freeze · 2` and the marker `+ speed/4/freeze·2`, then
   `freeze -= 1`. (At freeze=30 the speed is 1/15, smoothly recovering; at freeze=1
   one tick of double speed.) The healer additionally rotates 90° in yaw
   (the model is oriented sideways).
3. **Burning**: if `burnTime > 0`: `life -= burnDamage`, `burnTime -= 1`; when it ends,
   the visual effect is removed (`duration`).
4. **Poison**: if `poisonTime > 0`: `life -= poisonDamage`, `poisonTime -= 1`.
5. Health bar: visible when `_vshowunitslifemode`; faces the camera;
   `SetAnimTime(bar, clamp(100 - life%, 1, 99))`; color from the gradient
   `Gradient.bmp` (`_alifegradient[100][3]`) by percentage.
6. Spawning-in: while `AnimTime(pathCopy) < 3` — `EntityColor` is darkened proportionally
   (fade-in).
7. **Death**: `life <= 0` → `_fdeleteenemy(e, killed=1, checkLevel=1)`.
8. **Reached the end** (`AnimTime > AnimLength − 1`, see [03](03-levels-locations.md#enemy-path-path1b3d)):
   - not an inhabitant: `dmg = Round( life% / (3·pplResistance + 33) )`, boss → `dmg·5`;
     `lifes -= dmg` (not below 0). If `dmg < 1` — "monster killed by inhabitants"
     (`_vmonsterskilledbyinhabitants++`, a message at the end of the raid), otherwise a random
     `kill1..4.wav`.
     Examples: full health at resistance 0 → 3 inhabitants; 50% → 2 (1.515); 40% → 1;
     < 16.5% → 0. At resistance 5 (max), full health → 2, < 24% → 0.
   - inhabitant: `lifes += 1`, `oldlifes = lifes`.
   - `lifes < 1` → game over (`_fcreategameovermenu`; in survival — the high-score screen).
   - the enemy is removed without gold (`killed=0`).

## Enemy death [code: `_fdeleteenemy`, `_fcreatedeathanim`]

- `killed=1`: `gold += enemy\gold`; if FPS > 15 — a death animation
  (`Death.b3d` or `Death2.b3d` when `DeathMode=1`; `Animate 3, 0.2`, every tick
  `_fupdatedeathanims` sets `EntityAlpha (30 − AnimTime)/10` — the last 10 frames
  fade out; a "ghost" — sphere `Sphere01` with `death.png` in spherical env-mapping, blend add,
  alpha 0.2), sound `death1..4.wav`, a floating "+gold" label (`_fcreategoldmsg`, 100 ticks).
- The selection is cleared, and the health bar, model, and path copy are removed.
- Not an inhabitant → `_venemiesamount -= 1`; if it reaches 0 and `checkLevel=1` → `_fnextlevel`.

## End of raid [code: `_fnextlevel`]

1. Demo: after raid 37 — autosave and the "buy" screen.
2. Messages: after raid 1 — "Well done! First raid is repulsed!", 3 — "Usual monster
   can kill 1..3", 4 — "Sometimes appears a big monster", 10/34/58 — a save-game hint
   ("You can save your game by clicking Save game…", Texts.txt line 51).
   Line "Next level — air enemies!" (39) isn't used by the code.
3. If `curlevel < lastRaidOfLocation` → `curlevel += 1`, otherwise
   `_fcreatecongratulationsmenu` (transition to the map/next location).
   The last raid of location L = `first[L+1]-1`, for L=6 — **180**. In survival — just `+1`.
4. `_vlevelfinished = 1`, `_vingametime = 0`.
5. Income: `gold += Round(goldRate · 100)` (campaign) or `Round(goldRate · lifes)`
   (survival). Message "You have received N gold". **The number of inhabitants doesn't
   affect income in the campaign** — despite Helps.txt/Tutorial.txt.
6. If the inhabitant count dropped: `missed[curlevel] = oldlifes - lifes`,
   message "N of your inhabitants were killed".
7. A message about monsters killed by inhabitants.
8. `_fhandlebalance` (health auto-balance, [08](08-economy-lives-difficulty.md)).
9. `experience += 20`.
10. Autosave `Automatic.sav` (campaign, if no enemies are alive).
11. `_fenablealltowers` — clears "Stop attack" on all towers.

## Selecting a monster [code: `_fhandleenemyselection`]

LMB on a monster (picking: flying — box, ground — sphere r=2..3): it becomes selected,
**every tower gets it as its current target** (`tower\target`), a portrait is shown
(`faces.b3d`, frame = unitId-1; for inhabitants frame 30.99) along with stats: Life (rounded),
Armor, Speed (= speed·100), Type ground/air [code: `_fshowenemyinfoondisplay`].
When a tower with target method 1 picks a target, the selected monster gets priority.

## Campaign boss raids

Raids with < 4 monsters: 6, 12, 26, 36, 45, 54, 60, 70, 84, 94, 100, 109, 116, 130, 135,
144, 151, 165, 170, 180 (their Life/Armor/Gold in `RaidsData` are sharply higher).
All compositions: `data/raids.json`.
