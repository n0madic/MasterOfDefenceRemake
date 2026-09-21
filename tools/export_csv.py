#!/usr/bin/env python3
"""Convert the game's CSV tables into JSON using the same semantics as Main.exe.

Mirrors _floaddata / _floadtowerprototipesdata / _finitlocationsinfo:
- Units.csv: 34 monsters (ids 1..34), rows Air/Name/AnimSpeed/Healer/Worker.
- Tower1..5.csv: 11 upgrade levels each (level index 0..10); Tower6.csv is not loaded.
- Raids.csv: rows Raid1..Raid205, up to 25 monster ids each; only 1..180 are reachable.
- RaidsData<loc>.csv: Life/Speed/Armor/Gold per raid, mapped onto the global raid index
  via the per-location first raid (1, 16, 46, 71, 101, 136); RaidsData7 = survival table.
Rows the engine never reads (Общий коэф, *Coof, BaseModel, ...) are left out on purpose.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

LOCATION_FIRST_RAID = {1: 1, 2: 16, 3: 46, 4: 71, 5: 101, 6: 136}
LAST_CAMPAIGN_RAID = 180
LOCATIONS = {
    1: {"x1": 50, "x2": 70, "z1": 0, "z2": 40, "paths": 1, "ground_texture": "dno1.png", "tower_tint_rgb": [255, 255, 255]},
    2: {"x1": 10, "x2": 110, "z1": 0, "z2": 100, "paths": 1, "ground_texture": "dno2.png", "tower_tint_rgb": [255, 255, 255]},
    3: {"x1": 10, "x2": 70, "z1": 0, "z2": 85, "paths": 1, "ground_texture": "dno3.png", "tower_tint_rgb": [255, 255, 255]},
    4: {"x1": 75, "x2": 140, "z1": 5, "z2": 100, "paths": 1, "ground_texture": "dno4.png", "tower_tint_rgb": [255, 255, 255]},
    5: {"x1": 50, "x2": 145, "z1": 0, "z2": 100, "paths": 1, "ground_texture": "dno5.png", "tower_tint_rgb": [255, 255, 255]},
    6: {"x1": 5, "x2": 105, "z1": 0, "z2": 150, "paths": 1, "ground_texture": "dno6.png", "tower_tint_rgb": [255, 255, 255]},
}
TOWER_NAMES = {1: "land", 2: "magic", 3: "plant", 4: "freeze", 5: "fire"}


def rows(path: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for line in path.read_text(encoding="cp1251").splitlines():
        cells = line.split(";")
        if cells and cells[0].strip():
            out[cells[0].strip().lower()] = [c.strip() for c in cells[1:]]
    return out


def num(s: str, kind=float):
    return kind(s) if s else kind(0)


def load_units(data_dir: Path) -> list[dict]:
    u = rows(data_dir / "Units.csv")
    units = []
    for i in range(34):
        healer = num(u["healer:"][i], int)
        name = u["name:"][i]
        units.append({
            "id": i + 1, "name": name, "air": bool(num(u["air:"][i], int)),
            "anim_speed": num(u["animspeed:"][i]), "healer": healer, "worker": bool(num(u["worker:"][i], int)),
            "model": f"Monsters/{name}.b3d" if healer else f"Monsters/{name}.md2",
            "texture": None if healer else f"Monsters/{name}.jpg",
        })
    return units


def load_towers(data_dir: Path) -> dict[str, dict]:
    towers = {}
    for t in range(1, 6):
        r = rows(data_dir / f"Tower{t}.csv")
        levels = []
        for lv in range(11):
            levels.append({
                "level": lv,
                "land_damage": num(r["landdamage"][lv]), "air_damage": num(r["airdamage"][lv]),
                "range": num(r["attackrange"][lv]), "rate_of_fire_ms": num(r["rateoffire"][lv], lambda s: int(float(s))),
                "freeze": num(r["freeze"][lv], int), "fire": num(r["fire"][lv], int),
                "poison_coof": num(r["poisoncoof"][lv], int), "poison_damage": num(r["poisondamage"][lv]),
                "target_method": num(r["targetmethod"][lv], int), "place_on_road": bool(num(r["placeonroad"][lv], int)),
                "price": num(r["price"][lv], int), "bullet_model": r["bulletnames"][lv] or None,
            })
        towers[TOWER_NAMES[t]] = {"type_id": t, "max_upgrades": num(r["maxupgradesamount"][0], int), "levels": levels}
    return towers


def load_raids(data_dir: Path) -> dict:
    """Return {"locations", "location_first_raid", "campaign", "unreachable_rows", "survival"}."""
    raids_rows = rows(data_dir / "Raids.csv")
    raids: dict[int, dict] = {}
    for n in range(1, 206):
        cells = raids_rows.get(f"raid{n}", [])
        monsters = []
        for c in cells[:25]:
            v = num(c, int)
            if v == 0:
                break
            monsters.append(v)
        raids[n] = {"raid": n, "monsters": monsters, "boss": len(monsters) < 4}
    for loc in range(1, 7):
        r = rows(data_dir / f"RaidsData{loc}.csv")
        first = LOCATION_FIRST_RAID[loc]
        last = LOCATION_FIRST_RAID[loc + 1] - 1 if loc < 6 else LAST_CAMPAIGN_RAID
        for col, n in enumerate(range(first, last + 1)):
            raids[n].update({
                "location": loc, "life": num(r["life:"][col], int), "speed": num(r["speed:"][col]),
                "armor": num(r["armor:"][col], int), "gold": num(r["gold:"][col], int),
            })
    campaign = [raids[n] for n in range(1, LAST_CAMPAIGN_RAID + 1)]
    unused = [raids[n] for n in range(LAST_CAMPAIGN_RAID + 1, 206)]
    r7 = rows(data_dir / "RaidsData7.csv")
    survival = [{"raid": n, "monsters_count": n // 18 + 10, "life": num(r7["life:"][n - 1], int),
                 "speed": num(r7["speed:"][n - 1]), "armor": num(r7["armor:"][n - 1], int),
                 "gold": num(r7["gold:"][n - 1], int)} for n in range(1, 201)]
    return {"locations": LOCATIONS, "location_first_raid": LOCATION_FIRST_RAID, "campaign": campaign,
            "unreachable_rows": unused, "survival": survival}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir", type=Path)
    ap.add_argument("out_dir", type=Path)
    args = ap.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "units.json").write_text(json.dumps(load_units(args.data_dir), indent=1, ensure_ascii=False))
    (args.out_dir / "towers.json").write_text(json.dumps(load_towers(args.data_dir), indent=1))
    (args.out_dir / "raids.json").write_text(json.dumps(load_raids(args.data_dir), indent=1))
    print("ok")


if __name__ == "__main__":
    main()
