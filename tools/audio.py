"""The original's sounds and the codec helpers the port exporters encode them with.

Every port encodes straight from the original files (`audio_sources`), once, in the form its
engine plays best: see tools/targets/godot.py and tools/targets/defold/export.py.
"""
from __future__ import annotations

import logging
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

LOG = logging.getLogger("audio")

AUDIO_SUFFIXES = {".wav", ".ogg"}
WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT = 1, 3
# libvorbis quality (oggenc -q): the music lands near the original's 96 kbps mono streams.
VORBIS_QUALITY = 3


@dataclass(frozen=True)
class WavInfo:
    format_tag: int
    rate: int
    bits: int
    seconds: float

    @property
    def pcm(self) -> bool:
        return self.format_tag in (WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT)


def wav_info(path: Path) -> WavInfo | None:
    """Format, sample rate, bits per sample and duration of a RIFF wav from its `fmt ` and
    `data` chunks; None if the file is not a RIFF wav (oops2.wav is MP3 inside RIFF: its
    format tag says so and its duration comes from the MP3 byte rate)."""
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return None
    format_tag = rate = bits = byte_rate = size = 0
    pos = 12
    while pos + 8 <= len(data):
        chunk, length = data[pos:pos + 4], int.from_bytes(data[pos + 4:pos + 8], "little")
        if chunk == b"fmt ":
            format_tag = int.from_bytes(data[pos + 8:pos + 10], "little")
            rate = int.from_bytes(data[pos + 12:pos + 16], "little")
            byte_rate = int.from_bytes(data[pos + 16:pos + 20], "little")
            bits = int.from_bytes(data[pos + 22:pos + 24], "little")
        elif chunk == b"data":
            size = length
        pos += 8 + length + (length & 1)
    return WavInfo(format_tag, rate, bits, size / byte_rate if byte_rate else 0.0)


def audio_sources(data_dir: Path) -> dict[str, Path]:
    """Every sound of the original by its shipped (flat) file name, sorted by name."""
    found = {p.name: p for p in data_dir.rglob("*") if p.is_file() and p.suffix.lower() in AUDIO_SUFFIXES}
    return dict(sorted(found.items()))


def transcode_wav(src: Path, dst: Path, rate: int | None = None) -> None:
    """Re-encode to 16-bit PCM with ffmpeg (or afconvert on macOS when no resampling is
    asked), resampled to `rate` when given."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    resample = ["-ar", str(rate)] if rate else []
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), *resample, "-acodec", "pcm_s16le", str(dst)],
                       check=True)
    except FileNotFoundError:
        if rate:
            raise
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", str(src), str(dst)], check=True)


def remux_ogg(src: Path, dst: Path) -> None:
    """Stream-copy the Ogg Vorbis file without its comment header: the originals carry a
    "Sonic Foundry OggVorbis Beta 3" comment with no '=' that Godot warns about on load."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-map_metadata", "-1", "-c", "copy", str(dst)],
            check=True,
        )
    except FileNotFoundError:
        LOG.warning("ffmpeg not found, copying %s with its malformed comment header", src.name)
        shutil.copy2(src, dst)


def encode_vorbis(src: Path, dst: Path, rate: int | None) -> None:
    """Re-encode `src` as Ogg Vorbis with libvorbis (oggenc), keeping its channel count;
    ffmpeg decodes it, resampled to `rate` when given."""
    resample = ["-ar", str(rate)] if rate else []
    decode = ["ffmpeg", "-loglevel", "error", "-i", str(src), "-map_metadata", "-1", "-fflags", "+bitexact", *resample,
              "-sample_fmt", "s16", "-f", "wav", "-"]
    with subprocess.Popen(decode, stdout=subprocess.PIPE) as decoder:
        subprocess.run(["oggenc", "-Q", "-q", str(VORBIS_QUALITY), "-o", str(dst), "-"], stdin=decoder.stdout, check=True)
    if decoder.returncode:
        raise subprocess.CalledProcessError(decoder.returncode, decode)


def encode_ffmpeg_vorbis(src: Path, dst: Path) -> None:
    """ffmpeg's own (experimental, stereo-only) Vorbis encoder: the fallback without oggenc."""
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-ac", "2", "-c:a", "vorbis",
                    "-strict", "-2", "-q:a", "5", str(dst)], check=True)
