"""Shared paths for the unittest test suite (replaces the old pytest conftest.py)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

DATA_DIR = ROOT / "MasterOfDefense_unpacked" / "Data"
GODOT_DIR = ROOT / "godot"
DOCS_DATA = ROOT / "docs" / "data"
