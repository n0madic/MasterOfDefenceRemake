# 10. Blitz type field layouts

A key for reading `reference/decomp/*.c`. A Blitz-type object is a pointer to a field block in
4-byte steps; in the decompiled output access looks like `*(int *)(*obj + 0xNN)`. Field names
have been reconstructed from usage (they don't exist in the exe), so this is an
**interpretation**, and types come from the operations performed (float/int/handle). **Field types have been verified against the type descriptors** in the
module itself (`BBObjType.fieldTypes`, see `tools/dump_types.py`; a full dump of all 60 types is in
`data/blitz_types.txt`): for each field int/float/str/obj/vec is known, but not the name.

## `tenemyt` — enemy (`_fcreateenemy`, `_fupdateenemies`)

| Offset | Name | Type | Meaning |
|---|---|---|---|
| 0x00 | ext | obj `text_entity` | B3D-extensions wrapper; `ext\entity` = mesh |
| 0x04 | entity | handle | monster mesh |
| 0x08 | air | int | flying |
| 0x0C | pathCopy | handle | copy of `Path1.b3d` |
| 0x10 | marker | handle | `path` child of the copy |
| 0x14 | healthBar | handle | `health.b3d` |
| 0x18 | speed | float | units/tick (`raid\speed/10`) |
| 0x1C | freeze | float | remaining freeze ticks |
| 0x20 | burnTime | float | burn ticks |
| 0x24 | burnDamage | float | damage/tick from fire |
| 0x28 | duration | obj `tdurationt` | fire/poison visual effect |
| 0x2C | poisonTime | float | poison ticks |
| 0x30 | poisonDamage | float | damage/tick from poison |
| 0x34 | duration2 | obj `tdurationt` | **unused**: a second effect slot, `_fcreateduration` only writes `+0x28` |
| 0x38 | maxLife | float | |
| 0x3C | life | float | |
| 0x40 | animSpeed | float | from Units.csv |
| 0x44 | shadow | handle | |
| 0x48 | armor | int | |
| 0x4C | healer | int | |
| 0x50 | worker | int | inhabitant |
| 0x54 | boss | int | |
| 0x58 | unitId | int | 1..34 |
| 0x5C | selected | int | |
| 0x60 | gold | int | |
| 0x64 | ? | int | unused (no accesses in the code) |

## `ttowert` — tower (`_fcreatetower`, `_fhandletowers`, `_fshoot`)

| Offset | Name | Type | Meaning |
|---|---|---|---|
| 0x00 | ext | obj | |
| 0x04 | entity | handle | |
| 0x08 | placeMarker | handle | `*Place.b3d` while in placement mode (then 0) |
| 0x0C | canPlace | int | |
| 0x10 | selected | int | |
| 0x14 | level | int | 0..maxUpgrades |
| 0x18 | rateOfFire | int | ms |
| 0x1C | timer | int | +16 per tick |
| 0x20 | firePoints[] | array | `fire1` (index 1 only) |
| 0x24 | landDamage | float | |
| 0x28 | airDamage | float | |
| 0x2C | range | float | |
| 0x30 | rangeMesh | handle | `range.b3d`, scale `range·2` |
| 0x34 | freeze | float | |
| 0x38 | fire | float | |
| 0x3C | poisonCoof | int | |
| 0x40 | poisonDamage | float | |
| 0x44 | splash | float | unused |
| 0x48 | placeOnRoad | int | |
| 0x4C | bulletMesh | handle | bullet prototype |
| 0x50 | targetMethod | int | |
| 0x54 | target | obj `tenemyt` | current target |
| 0x58 | type | int | 1..6 |
| 0x5C | upgradePending | int | 1 — start the upgrade animation |
| 0x60 | maxUpgrades | int | |
| 0x64 | explPrototype | handle | |
| 0x68 | spent | int | gold spent |
| 0x6C | dno | handle | base child node |
| 0x70 | texture | handle | freed on deletion |
| 0x74 | hidden | int | hidden preview tower |
| 0x78 | stopped | int | "Stop attack" |

## `ttowerprototypet` — `towerprototype[type][level]` (5×11 array, index `level·5 + type`)

| Offset | Name | CSV row |
|---|---|---|
| 0x00 | landDamage (f) | LandDamage |
| 0x04 | airDamage (f) | AirDamage |
| 0x08 | range (f) | AttackRange |
| 0x0C | freeze (i) | Freeze |
| 0x10 | fire (i) | Fire |
| 0x14 | poisonCoof (i) | PoisonCoof |
| 0x18 | poisonDamage (f) | PoisonDamage |
| 0x1C | splash (f) | Splash |
| 0x20 | targetMethod (i) | TargetMethod |
| 0x24 | placeOnRoad (i) | PlaceOnRoad |
| 0x28 | rateOfFire (i) | RateOfFire |
| 0x2C, 0x30 | baseModel, bangEffName (str) | **never populated**: the loader doesn't even look for `BaseModel`/`BangEffName` rows in the CSV [code: `_floadtowerprototipesdata`] |
| 0x34 | maxUpgrades (i) | MaxUpgradesAmount (column 1) |
| 0x38 | bulletMesh (handle) | BulletNames |
| 0x3C | price (i) | Price |

## `traidt` — `raids[1..200]`

| Offset | Name | Meaning |
|---|---|---|
| 0x00 | count | number of monsters |
| 0x04 | monsters[] | array of ids (1..25) |
| 0x08 | life (i) | |
| 0x0C | speed (f) | |
| 0x10 | armor (i) | |
| 0x14 | gold (i) | |

## `tmonstersprototypest` — `units[1..34]`

0x00 mesh, 0x04 texture, 0x08 air, 0x0C name (str), 0x10 animSpeed (f), 0x14 healer, 0x18 worker.

## `tlocationt` — `locations[1..6]`

0x00 x1, 0x04 x2, 0x08 z1, 0x0C z2, 0x10 scene (obj ext), 0x14 river, 0x18 border,
0x1C pathsCount, 0x20 paths[] (handles for `Path<k>.b3d`), 0x24 r, 0x28 g, 0x2C b,
0x30 dnoTexture, 0x34 firstRaid.

## `tbullett`

0x00 entity, 0x04 target (obj), 0x08 speed (f, 0.4), 0x0C damage (f), 0x10 freeze (f),
0x14 burn (f), 0x18 poison (f), 0x1C tower (obj).

## `tballoont` (`_vballoon`)

0x00 entity, 0x04/0x08/0x0C destX/Y/Z, 0x10 hereMarker, 0x14 shadow, 0x18 bombMesh,
0x1C enabled, 0x20 created, 0x24 timer.

## `tbombt`

0x00 entity, 0x04 damage (350), 0x08 freeze (30·cold).

## `tthegamet` (`_vgame`, order = field order in the save)

gold, lifes, curlevel, location, rangeUpgrader, speedUpgrader, damageUpgrader,
goldRate, sellRate, enemiesCreated, ingameTime, showUnitsLife, createEnemiesMode,
levelFinished, rangeLevel, speedLevel, damageLevel, goldLevel, sellLevel, coldMagic,
fireMagic, poisonMagic, pplResistance, experience, maxLocation, oldLifes,
balloonX, balloonY, balloonZ, extraLifes.

## `tvdengine` (`_vvde` — engine settings/state)

0x00 xres, 0x04 yres, 0x08 depth, 0x0C vsync, 0x10 windowed, 0x14 timeForWin,
0x18 gamma, 0x1C debugShow, 0x20 ?, 0x24 showHelp, 0x28 congrMenuShown, 0x2C soundVol,
0x30 musicVol, 0x34 playerName, 0x38 cursorOverEnemy, 0x3C ?, 0x40 **location**,
0x44 maxLocation, 0x48 mapMenuShown.

## Other

- `tframelimitt` (`_vfpsl`): 0x00 fps, 0x04 periodMs, 0x08 lastTime.
- `tmessaget`: 0x00 text, 0x04 alpha, 0x08 type, 0x0C..0x14 r,g,b, 0x18 endTimeMs.
- `tupgradeseventt`: 0x00 skillId; `tupgqueryt`: 0x00 skillId, 0x04 isDowngrade.
- `tgamesoundst`: 0x00 listener, followed by sound slots (see [09](09-ui-menus-tutorial.md#sounds)).
- Global arrays: `_araids[200]`, `_aunits[50]`, `_atowerprototype[5][10]` (5×11 in practice),
  `_alocations[10]`, `_amissedenemies[1000]`, `_alifegradient[100][3]`, `_asplit_params[17000]`.
