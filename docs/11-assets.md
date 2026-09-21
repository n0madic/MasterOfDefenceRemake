# 11. Asset inventory

Verification: all 97 paths hardcoded in the code exist, except `Data/Sounds/eagle.wav`.
Files not mentioned literally in the code are loaded either from a pattern (`Data/Location<L>/…`,
`Data/Monsters/<Name>.md2|jpg`, `Data/Tower<t>.csv`, `Data/RaidsData<n>.csv`,
`Data/Sounds/music<L>.ogg`, `Data/Menu/titul<n>.png`, `Data/Towers/<bullet>.b3d`), or
as textures from the `TEXS` chunks of B3D scenes (most jpg/png files in the location and menu folders).

| Category | Files | Usage |
|---|---|---|
| Location scenes | `Location<L>/Location<L>.b3d` + textures | terrain, zones (see [03](03-levels-locations.md)) |
| Paths | `Location<L>/Path1.b3d` | enemy movement; `Location1/birdpath1.b3d` — the eagle's flight path on location 2; `Location2/birdpath2.b3d` — unused |
| Monsters | `Monsters/*.md2` + `.jpg` (33), `Monsters/Health.b3d` (healer), `Gradient.bmp` (HP bar color) | |
| Towers | `Towers/{Military,Magic,Nature,Freeze,Fire}.b3d`, `*Place.b3d` (marker), `*Eff.b3d` (explosion), `PoisonEff.b3d`, bullets `military1-5`, `magic1-5`, `nature1-5`, `freeze1-5`, `fire1`; `range.b3d`, `selection.b3d`, `selmonster.b3d`, `shadow.b3d`, `here.b3d`, `Balloon.b3d`, `death.b3d`/`death2.b3d`, textures `dno1-6.png` | |
| Unused by the code | `Towers/Delete.b3d`, `Towers/sv.b3d`, `Tower6.csv`, `Sounds/oops.wav`, `Sounds/menu.wav`, `Location2/birdpath2.b3d`, the `Scores` key in the vdd | likely development leftovers |
| GUI | `gui.png` (button atlas), `window.png`, `wood.png`, `woodtext.png`, `updates.png` (skills window), `Lfon.png`, `Lines.png`, `money.png`, `lives.png`, `expa.png`, `health.png`, `timespeed.png`, `monsters.png` (portraits via `faces.b3d`), `Env.b3d` (3D panel with nodes `reset`, `window`, `updates`), `tutorial.b3d`, `td.ico` | |
| Menu | `Menu/*.b3d`, `*.png/jpg`, `Titul1-3.png`, `HarderModes.png`, `youwin.png`, `gameover.png`, `bfglogo.png`/`vdlogo.png` (publisher logos), `Demo.bmp`/`preved.png` (full-version marker) | |
| Demo/loader | `Loader/*` — the "buy full version" screen | demo only |
| Finale | `Additional/end.b3d`, `creditsEnd.png`, `loc1-5.jpg`, portraits | credits |
| Sounds | `Sounds/*.wav` (see [09](09-ui-menus-tutorial.md#sounds)), `music1-6.ogg`, `menu.ogg` | |
| Data | `Units.csv`, `Tower1-5.csv`, `Raids.csv`, `RaidsData1-7.csv`, `Texts.txt`, `Helps.txt`, `Storyline.txt`, `Tutorial.txt` | checked via CRC (`_fcheckgamefiles`) |

A full file listing with sizes can be obtained with `find MasterOfDefense_unpacked -type f`.
