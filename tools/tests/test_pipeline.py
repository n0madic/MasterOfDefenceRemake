"""The unified pipeline's plumbing (tools/build_assets.py): sound probing, the import stage's
up-to-date check, the Godot tree sync and the launcher icon set."""
from __future__ import annotations

import os
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import testpaths  # noqa: F401  (puts tools/ on sys.path)

from PIL import Image

import source_import
from audio import audio_sources, wav_info
from icons import ADAPTIVE_ART_SIZE, ADAPTIVE_LAYERS, ADAPTIVE_SIZE, ANDROID_SIZES, APP_STORE, IOS_SIZES, generate_icons
from targets.godot import GODOT_ICONS, sync_tree


def write_wav(path: Path, format_tag: int, rate: int, bits: int, frames: int, channels: int = 1) -> None:
    block = channels * max(bits, 8) // 8
    fmt = struct.pack("<HHIIHH", format_tag, channels, rate, rate * block, block, bits)
    data = b"\0" * frames * block
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)


class TempDirTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()


class AudioTests(TempDirTestCase):
    def test_wav_info(self) -> None:
        cases = [
            ("pcm8.wav", 1, 8000, 8, 8000, True, 1.0),
            ("pcm16.wav", 1, 22050, 16, 11025, True, 0.5),
            ("mp3.wav", 0x55, 11025, 0, 100, False, None),
        ]
        for name, tag, rate, bits, frames, pcm, seconds in cases:
            with self.subTest(name):
                write_wav(self.root / name, tag, rate, bits, frames)
                info = wav_info(self.root / name)
                self.assertEqual((info.format_tag, info.rate, info.bits, info.pcm), (tag, rate, bits, pcm))
                if seconds is not None:
                    self.assertAlmostEqual(info.seconds, seconds)
        (self.root / "junk.wav").write_bytes(b"not a wav")
        self.assertIsNone(wav_info(self.root / "junk.wav"))

    def test_audio_sources_are_flat_and_sorted(self) -> None:
        for rel in ("Sounds/menu.wav", "Sounds/menu.ogg", "Sounds/click.wav", "Menu/readme.txt"):
            (self.root / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.root / rel).write_bytes(b"x")
        sources = audio_sources(self.root)
        self.assertEqual(list(sources), ["click.wav", "menu.ogg", "menu.wav"])
        self.assertEqual(sources["menu.ogg"], self.root / "Sounds" / "menu.ogg")


class SyncTreeTests(TempDirTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.src, self.dst = self.root / "src", self.root / "dst"
        for rel, content in {"models/a.glb": b"a", "textures/t.png": b"t"}.items():
            (self.src / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.src / rel).write_bytes(content)

    def test_mirrors_links_and_skips_unchanged(self) -> None:
        self.assertEqual(sync_tree(self.src, self.dst), 2)
        self.assertEqual((self.dst / "models" / "a.glb").read_bytes(), b"a")
        self.assertEqual(os.stat(self.dst / "models" / "a.glb").st_ino, os.stat(self.src / "models" / "a.glb").st_ino)
        self.assertEqual(sync_tree(self.src, self.dst), 0)

    def test_replaced_source_is_placed_again(self) -> None:
        sync_tree(self.src, self.dst)
        (self.src / "models" / "a.glb").unlink()
        (self.src / "models" / "a.glb").write_bytes(b"new")
        self.assertEqual(sync_tree(self.src, self.dst), 1)
        self.assertEqual((self.dst / "models" / "a.glb").read_bytes(), b"new")

    def test_orphans_go_with_their_sidecars_and_kept_dirs_stay(self) -> None:
        sync_tree(self.src, self.dst)
        (self.dst / "textures" / "t.png.import").write_text("[remap]\n")
        (self.dst / "textures" / "old.png").write_bytes(b"o")
        (self.dst / "textures" / "old.png.import").write_text("[remap]\n")
        (self.dst / "textures" / "gone.jpg.import").write_text("[remap]\n")
        (self.dst / "audio").mkdir()
        (self.dst / "audio" / "click.wav").write_bytes(b"w")
        (self.dst / "stale").mkdir()
        (self.dst / "stale" / "x.glb").write_bytes(b"x")
        sync_tree(self.src, self.dst, keep=("audio",))
        left = sorted(p.relative_to(self.dst).as_posix() for p in self.dst.rglob("*") if p.is_file())
        self.assertEqual(left, ["audio/click.wav", "models/a.glb", "textures/t.png", "textures/t.png.import"])
        self.assertFalse((self.dst / "stale").exists())


class ImportStageTests(TempDirTestCase):
    STEPS = ("convert_models", "copy_textures", "export_data", "generate_icons")

    def run_stage(self, **kwargs) -> dict[str, mock.MagicMock]:
        mocks = {name: mock.MagicMock(return_value={"b3d": {}, "md2": {}, "missing_textures": {}})
                 for name in self.STEPS}
        with mock.patch.multiple(source_import, **mocks):
            source_import.run_import(self.data, self.root / "import", **kwargs)
        return mocks

    def setUp(self) -> None:
        super().setUp()
        self.data = self.root / "Data"
        self.data.mkdir()
        (self.data / "Units.csv").write_text("a;b\n")

    def test_skipped_while_inputs_are_unchanged(self) -> None:
        self.assertTrue(self.run_stage()["convert_models"].called)
        self.assertFalse(self.run_stage()["convert_models"].called)
        self.assertTrue(self.run_stage(force=True)["convert_models"].called)

    def test_rerun_on_changed_data_or_options(self) -> None:
        self.run_stage()
        (self.data / "Units.csv").write_text("a;b;c\n")
        self.assertTrue(self.run_stage()["convert_models"].called)
        self.assertTrue(self.run_stage(skin=False)["convert_models"].called)


class IconsTests(TempDirTestCase):
    def test_every_platform_icon_from_the_master(self) -> None:
        master = self.root / "master.png"
        image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        image.paste((200, 30, 30, 255), (16, 16, 48, 48))
        image.save(master)
        out = self.root / "icons"
        names = generate_icons(master, out)
        expected = {"icon_256.png", "icon.icns", "icon.ico", APP_STORE, *ADAPTIVE_LAYERS.values(),
                    *(f"android_{s}.png" for s in ANDROID_SIZES), *(f"ios_{s}.png" for s in IOS_SIZES)}
        self.assertEqual(set(names), expected)
        self.assertLessEqual(set(GODOT_ICONS), expected)
        for size in ANDROID_SIZES:
            with Image.open(out / f"android_{size}.png") as icon:
                self.assertEqual(icon.size, (size, size))
        for name in (APP_STORE, *(f"ios_{s}.png" for s in IOS_SIZES)):
            with Image.open(out / name) as icon:
                self.assertEqual(icon.mode, "RGB", name)  # iOS icons must be opaque
        with Image.open(out / ADAPTIVE_LAYERS["foreground"]) as fg:
            self.assertEqual(fg.size, (ADAPTIVE_SIZE, ADAPTIVE_SIZE))
            margin = (ADAPTIVE_SIZE - ADAPTIVE_ART_SIZE) // 2
            self.assertGreaterEqual(fg.getchannel("A").getbbox()[0], margin)  # art inside the safe zone
            alpha = fg.getchannel("A").tobytes()
        with Image.open(out / ADAPTIVE_LAYERS["monochrome"]) as mono:
            self.assertEqual(mono.getchannel("A").tobytes(), alpha)
            self.assertEqual({rgb for rgb, a in zip(mono.convert("RGB").getdata(), mono.getchannel("A").getdata()) if a},
                             {(255, 255, 255)})


if __name__ == "__main__":
    unittest.main()
