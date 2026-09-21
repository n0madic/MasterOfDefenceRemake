#!/usr/bin/env python3
"""Simulate enemy travel time along the exported paths (docs/data/enemy_paths.json).

Reproduces `_fupdateenemies` tick by tick:

    marker = P(t)                        # animated `path` node, t in frames
    if |body - marker| < 1: t += speed/4 # SetAnimTime(copy, AnimTime + speed/4)
    body += speed * dir(body -> marker)  # PointEntity + MoveEntity(0,0,speed), no clamping
    finished when t > frames - 1         # AnimTime > AnimLength - 1

P(t) interpolates linearly between the integer keyframes (blitz3d Animation::
getPosition). `speed` is the per-tick body speed = raid.speed / 10.
"""
from __future__ import annotations

import argparse
import json
import logging
import math
from pathlib import Path

LOG = logging.getLogger("simulate_path")

CATCH_UP_DISTANCE = 1.0
MARKER_FRAMES_PER_SPEED = 0.25
DEFAULT_TICK_HZ = 60
MAX_TICKS = 1_000_000

Vec = tuple[float, float, float]


def lerp(a: Vec, b: Vec, f: float) -> Vec:
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)


def dist(a: Vec, b: Vec) -> float:
    return math.dist(a, b)


def position_at(keys: list[Vec], t: float) -> Vec:
    i = int(math.floor(t))
    if i >= len(keys) - 1:
        return keys[-1]
    return lerp(keys[i], keys[i + 1], t - i)


def simulate(keys: list[Vec], frames: int, speed: float) -> int:
    """Return the number of ticks until the enemy reaches the end of the path."""
    t = 0.0
    body = keys[0]
    for tick in range(1, MAX_TICKS):
        marker = position_at(keys, t)
        if dist(body, marker) < CATCH_UP_DISTANCE:
            t += speed * MARKER_FRAMES_PER_SPEED
            marker = position_at(keys, t)
        d = dist(body, marker)
        if d > 0.0:
            body = lerp(body, marker, speed / d)  # may overshoot, like MoveEntity
        if t > frames - 1:
            return tick
    raise RuntimeError("enemy never reached the end of the path")


def path_length(keys: list[Vec], frames: int) -> float:
    return sum(dist(keys[i], keys[i + 1]) for i in range(min(frames, len(keys) - 1)))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths_json", type=Path)
    ap.add_argument("--raids-json", type=Path, help="use per-location min/max raid speed from raids.json")
    ap.add_argument("--speed", type=float, action="append", help="raid speed (CSV value, e.g. 1.03); repeatable")
    ap.add_argument("--hz", type=int, default=DEFAULT_TICK_HZ, help="logic ticks per second (default slider)")
    ap.add_argument("--json", type=Path, help="write results as JSON")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    paths = json.loads(args.paths_json.read_text())
    speeds_per_loc: dict[str, list[float]] = {}
    if args.raids_json:
        raids = json.loads(args.raids_json.read_text())
        for raid in raids["campaign"]:
            loc = f"location{raid['location']}"
            speeds_per_loc.setdefault(loc, []).append(raid["speed"])
    default_speeds = args.speed or [1.03, 1.5, 2.0, 3.0]

    result: dict[str, dict] = {}
    for loc, data in paths.items():
        keys = [tuple(w["pos"]) for w in data["waypoints"]]
        frames = data["anim_frames"]
        length = path_length(keys, frames - 1)  # the last frame is never reached
        speeds = sorted(set(speeds_per_loc.get(loc) or default_speeds))
        chosen = [speeds[0], speeds[-1]] if speeds_per_loc else speeds
        rows = []
        for csv_speed in chosen:
            ticks = simulate(keys, frames, csv_speed / 10.0)
            rows.append({"raid_speed": csv_speed, "ticks": ticks, "seconds": round(ticks / args.hz, 1)})
        result[loc] = {
            "frames": frames,
            "usable_length": round(length, 1),
            "mean_step": round(length / (frames - 1), 2),
            "runs": rows,
        }
        runs = ", ".join(f"speed {r['raid_speed']}: {r['ticks']} ticks = {r['seconds']} s" for r in rows)
        print(f"{loc}: {frames} frames, length {length:.1f} (step {length / (frames - 1):.2f}); {runs}")
    if args.json:
        args.json.write_text(json.dumps(result, indent=1) + "\n")
        LOG.info("wrote %s", args.json)


if __name__ == "__main__":
    main()
