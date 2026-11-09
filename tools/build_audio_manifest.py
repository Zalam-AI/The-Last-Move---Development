#!/usr/bin/env python3
"""Builds assets/audio/manifest.json -- the authoritative list of audio the game loads.

Directory scanning works in the editor but is unreliable inside an exported .pck (the
imported resource names differ), so the shipped build reads this manifest instead.
Run this whenever tools/generate_audio.py has been run.

    python3 tools/build_audio_manifest.py
"""
from __future__ import annotations

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "assets", "audio")
OUT = os.path.join(AUDIO, "manifest.json")
BANKS = {"sfx": "sfx", "music": "music", "ambience": "ambience", "voice": "voice"}
EXTS = (".ogg", ".wav", ".mp3")


def base_name(stem: str) -> str:
    """imp_wood_02 -> imp_wood (variations are collected under one key)."""
    m = re.match(r"^(.*)_(\d{2})$", stem)
    return m.group(1) if m else stem


def scan(bank: str, strip_variants: bool) -> dict[str, list[str]]:
    folder = os.path.join(AUDIO, bank)
    out: dict[str, list[str]] = {}
    if not os.path.isdir(folder):
        return out
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith(EXTS):
            continue
        stem = os.path.splitext(name)[0]
        key = base_name(stem) if strip_variants else stem
        out.setdefault(key, []).append(f"res://assets/audio/{bank}/{name}")
    return out


def main() -> None:
    manifest = {}
    for bank in BANKS:
        manifest[bank] = scan(bank, strip_variants=(bank == "sfx"))
    total = sum(len(v) for b in manifest.values() for v in b.values())
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
    print(f"[manifest] {OUT}")
    for bank, entries in manifest.items():
        files = sum(len(v) for v in entries.values())
        print(f"  {bank}: {len(entries)} keys, {files} files")
    print(f"  total files: {total}")


if __name__ == "__main__":
    main()
