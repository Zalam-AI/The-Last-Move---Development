#!/usr/bin/env python3
"""
THE LAST MOVE - procedural audio build.

Generates every sound effect, ambience loop and music cue in the game from scratch with
numpy, and synthesises the corporate PA voice lines with espeak-ng. Nothing is sampled
from a library, so the audio carries no third-party licensing obligations.

Usage:  python3 tools/generate_audio.py [--voice-only] [--no-voice]
"""
from __future__ import annotations

import math
import os
import random
import shutil
import subprocess
import sys
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
AMB = os.path.join(ROOT, "assets", "audio", "ambience")
MUS = os.path.join(ROOT, "assets", "audio", "music")
VOX = os.path.join(ROOT, "assets", "audio", "voice")
SR = 44100
MLOOP = 22050

for d in (SFX, AMB, MUS, VOX):
    os.makedirs(d, exist_ok=True)

rng = np.random.default_rng(20261109)


# --------------------------------------------------------------- utilities --
def write_wav(path: str, data: np.ndarray, sr: int = SR) -> None:
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) if data.size else 0.0
    if peak > 0:
        data = data / peak * 0.92
    pcm = (data * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def t_axis(seconds: float, sr: int = SR) -> np.ndarray:
    return np.linspace(0.0, seconds, int(seconds * sr), endpoint=False)


def noise(n: int) -> np.ndarray:
    return rng.normal(0.0, 1.0, n)


def env_exp(n: int, attack: float = 0.002, decay: float = 0.3, sr: int = SR) -> np.ndarray:
    a = max(1, int(attack * sr))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    d = np.exp(-np.arange(n - a) / max(1.0, decay * sr))
    e[a:] = d
    return e


def lowpass(x: np.ndarray, cutoff: float, sr: int = SR, order: int = 2) -> np.ndarray:
    try:
        from scipy.signal import butter, lfilter
    except ImportError:  # pragma: no cover
        return x
    b, a = butter(order, min(0.99, cutoff / (sr * 0.5)), btype="low")
    return lfilter(b, a, x)


def highpass(x: np.ndarray, cutoff: float, sr: int = SR, order: int = 2) -> np.ndarray:
    try:
        from scipy.signal import butter, lfilter
    except ImportError:  # pragma: no cover
        return x
    b, a = butter(order, min(0.99, cutoff / (sr * 0.5)), btype="high")
    return lfilter(b, a, x)


def bandpass(x: np.ndarray, lo: float, hi: float, sr: int = SR, order: int = 2) -> np.ndarray:
    try:
        from scipy.signal import butter, lfilter
    except ImportError:  # pragma: no cover
        return x
    b, a = butter(order, [min(0.99, lo / (sr * 0.5)), min(0.99, hi / (sr * 0.5))], btype="band")
    return lfilter(b, a, x)


def reverb(x: np.ndarray, seconds: float = 0.9, mix: float = 0.28, sr: int = SR) -> np.ndarray:
    n = int(seconds * sr)
    ir = noise(n) * np.exp(-np.arange(n) / (0.32 * sr))
    ir = lowpass(ir, 4200.0, sr)
    ir /= np.max(np.abs(ir)) + 1e-9
    wet = np.convolve(x, ir)[: len(x)]
    return (1.0 - mix) * x + mix * wet * 0.8


def thump(freq: float, seconds: float, decay: float, sr: int = SR) -> np.ndarray:
    t = t_axis(seconds, sr)
    sweep = freq * (1.0 + 0.6 * np.exp(-t * 26.0))
    ph = 2 * np.pi * np.cumsum(sweep) / sr
    return np.sin(ph) * np.exp(-t / decay)


def ring(freqs, seconds: float, decays, sr: int = SR) -> np.ndarray:
    t = t_axis(seconds, sr)
    out = np.zeros_like(t)
    for f, d in zip(freqs, decays):
        out += np.sin(2 * np.pi * f * t) * np.exp(-t / d)
    return out


# ------------------------------------------------------------------- sfx ----
def impact(material: str, variant: int) -> np.ndarray:
    """A collision sound. Heavier, duller materials ring shorter and lower."""
    rnd = random.Random(hash((material, variant)) & 0xFFFFFFFF)
    dur = {"wood": 0.45, "metal": 0.9, "glass": 0.7, "ceramic": 0.5,
           "fabric": 0.32, "paper": 0.25, "electronics": 0.6, "default": 0.4}.get(material, 0.4)
    n = int(dur * SR)
    base = {"wood": 160.0, "metal": 95.0, "glass": 320.0, "ceramic": 240.0,
            "fabric": 70.0, "paper": 120.0, "electronics": 140.0, "default": 120.0}.get(material, 120.0)
    out = thump(base * rnd.uniform(0.85, 1.15), dur, 0.09) * 0.85
    nz = noise(n) * env_exp(n, 0.001, 0.05)
    if material == "wood":
        out += bandpass(nz, 220, 2600) * 0.5
        out += ring([rnd.uniform(320, 420), rnd.uniform(700, 900)], dur, [0.12, 0.08]) * 0.18
    elif material == "metal":
        out += ring([rnd.uniform(520, 640), rnd.uniform(1180, 1320), rnd.uniform(2100, 2400),
                     rnd.uniform(3300, 3600)], dur, [0.42, 0.3, 0.18, 0.1]) * 0.3
        out += highpass(nz, 1800) * 0.22
    elif material == "glass":
        out += ring([rnd.uniform(1800, 2400), rnd.uniform(3100, 3800), rnd.uniform(4600, 5200)],
                    dur, [0.22, 0.16, 0.1]) * 0.3
        out += highpass(nz, 3000) * 0.3
    elif material == "ceramic":
        out += bandpass(nz, 900, 5000) * 0.45
        out += ring([rnd.uniform(900, 1200), rnd.uniform(1900, 2300)], dur, [0.16, 0.1]) * 0.2
    elif material == "fabric":
        out += lowpass(nz, 700) * 0.55
    elif material == "paper":
        out += highpass(nz, 1500) * 0.4
    elif material == "electronics":
        out += ring([rnd.uniform(180, 240), rnd.uniform(600, 700)], dur, [0.2, 0.1]) * 0.2
        out += lowpass(nz, 2000) * 0.3
    else:
        out += bandpass(nz, 200, 3000) * 0.4
    out[: int(0.001 * SR)] *= 0.2
    return reverb(out, 0.35, 0.12)


def shatter(material: str, variant: int) -> np.ndarray:
    rnd = random.Random(hash(("break", material, variant)) & 0xFFFFFFFF)
    dur = 1.1 if material in ("glass", "ceramic") else 0.7
    n = int(dur * SR)
    out = np.zeros(n)
    count = 16 if material in ("glass", "ceramic") else 9
    for i in range(count):
        start = int(rnd.uniform(0.0, 0.35) * SR)
        length = int(rnd.uniform(0.03, 0.18) * SR)
        if start + length >= n:
            continue
        freq = rnd.uniform(1200, 6000) if material in ("glass", "ceramic") else rnd.uniform(300, 1800)
        seg = ring([freq], length / SR, [rnd.uniform(0.02, 0.09)]) * rnd.uniform(0.2, 0.6)
        seg = seg[: length]
        if seg.size < length:
            seg = np.pad(seg, (0, length - seg.size))
        out[start:start + length] += seg
    out += highpass(noise(n) * env_exp(n, 0.001, 0.12), 1500) * 0.35
    return reverb(out, 0.6, 0.22)


def scrape(material: str, variant: int) -> np.ndarray:
    rnd = random.Random(hash(("scrape", material, variant)) & 0xFFFFFFFF)
    dur = 0.85
    n = int(dur * SR)
    base = noise(n)
    if material == "wood":
        x = bandpass(base, 260, 2200)
    elif material == "metal":
        x = bandpass(base, 900, 5000)
    elif material == "fabric":
        x = lowpass(base, 900)
    else:
        x = bandpass(base, 200, 3000)
    mod = 0.55 + 0.45 * np.sin(2 * np.pi * rnd.uniform(5, 12) * t_axis(dur))
    grit = 1.0 + 0.8 * (rng.random(n) > 0.985)
    out = x * mod * grit * env_exp(n, 0.05, 0.5)
    return reverb(out, 0.4, 0.16)


def footstep(kind: str, variant: int) -> np.ndarray:
    rnd = random.Random(hash(("foot", kind, variant)) & 0xFFFFFFFF)
    dur = 0.24 if kind != "crouch" else 0.18
    n = int(dur * SR)
    out = thump(rnd.uniform(70, 105) if kind != "crouch" else rnd.uniform(55, 75), dur, 0.045) * 0.5
    out += bandpass(noise(n) * env_exp(n, 0.001, 0.03), 400, 3800) * (0.32 if kind != "crouch" else 0.14)
    if kind == "run":
        out *= 1.35
    return out


def door(kind: str, variant: int) -> np.ndarray:
    rnd = random.Random(hash(("door", kind, variant)) & 0xFFFFFFFF)
    if kind in ("open", "close"):
        dur = 0.95
        t = t_axis(dur)
        n = len(t)
        creak_f = rnd.uniform(320, 520) * (1.0 + 0.25 * np.sin(2 * np.pi * rnd.uniform(1.5, 3.5) * t))
        creak = np.sin(2 * np.pi * np.cumsum(creak_f) / SR) * env_exp(n, 0.08, 0.4) * 0.35
        creak += bandpass(noise(n) * env_exp(n, 0.05, 0.35), 600, 3000) * 0.22
        out = creak
        if kind == "close":
            imp = impact("wood", variant)
            imp = imp[: len(out)]
            if imp.size < len(out):
                imp = np.pad(imp, (0, len(out) - imp.size))
            out = out * 0.7 + imp * 0.5
    elif kind == "slam":
        dur = 1.4
        n = int(dur * SR)
        out = impact("wood", variant)[:n]
        if out.size < n:
            out = np.pad(out, (0, n - out.size))
        out = out + thump(60, dur, 0.25) * 0.8
        out += bandpass(noise(n) * env_exp(n, 0.001, 0.2), 200, 2400) * 0.3
    else:  # locked
        dur = 0.5
        n = int(dur * SR)
        out = bandpass(noise(n) * env_exp(n, 0.001, 0.03), 800, 3500) * 0.5
        out += ring([240, 480, 720], dur, [0.1, 0.06, 0.04]) * 0.2
    return reverb(out, 0.8, 0.3)


def house_crease(variant: int) -> np.ndarray:
    rnd = random.Random(hash(("creak", variant)) & 0xFFFFFFFF)
    dur = 2.6
    t = t_axis(dur)
    n = len(t)
    f = rnd.uniform(70, 130) * (1.0 + 0.5 * np.sin(2 * np.pi * rnd.uniform(0.4, 1.2) * t))
    out = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.4, 1.1) * 0.5
    out += bandpass(noise(n) * env_exp(n, 0.5, 0.9), 150, 1400) * 0.25
    return reverb(out, 1.4, 0.4)


def whisper(variant: int) -> np.ndarray:
    rnd = random.Random(hash(("whisper", variant)) & 0xFFFFFFFF)
    dur = 2.2
    n = int(dur * SR)
    src = noise(n)
    # crude formant shaping for a breathy, wordless whisper
    out = bandpass(src, 700, 1600) * 0.5 + bandpass(src, 1900, 3200) * 0.35
    amp = 0.5 + 0.5 * np.sin(2 * np.pi * rnd.uniform(2.0, 4.0) * t_axis(dur))
    out = out * amp * env_exp(n, 0.35, 0.9)
    return reverb(out, 1.6, 0.45)


def ui_click(freq: float, dur: float = 0.07) -> np.ndarray:
    n = int(dur * SR)
    t = t_axis(dur)
    out = np.sin(2 * np.pi * freq * t) * env_exp(n, 0.001, 0.02)
    out += bandpass(noise(n) * env_exp(n, 0.001, 0.008), 1500, 6000) * 0.25
    return out


def radio_static(variant: int) -> np.ndarray:
    dur = 2.4
    n = int(dur * SR)
    out = bandpass(noise(n), 400, 4500) * 0.5
    out *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * t_axis(dur))
    gate = (rng.random(n) > 0.995).astype(float)
    out += gate * 0.3
    return reverb(out * env_exp(n, 0.05, 1.2), 0.5, 0.2)


def light_buzz(variant: int) -> np.ndarray:
    dur = 0.9
    t = t_axis(dur)
    n = len(t)
    out = (np.sin(2 * np.pi * 120 * t) * 0.4 + np.sin(2 * np.pi * 240 * t) * 0.2
           + np.sin(2 * np.pi * 60 * t) * 0.3)
    out *= (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 8 * t)))
    out += bandpass(noise(n), 2000, 7000) * 0.08
    return out * env_exp(n, 0.02, 0.5) * 0.5


def series(*items) -> np.ndarray:
    return np.concatenate([np.asarray(i) for i in items])


# --------------------------------------------------------------- ambience ---
def ambience(name: str) -> np.ndarray:
    """Loopable ambience beds (crossfaded tail so they loop cleanly)."""
    dur = 24.0
    sr = MLOOP
    n = int(dur * sr)
    t = np.linspace(0, dur, n, endpoint=False)
    out = np.zeros(n)
    rnd = random.Random(hash(name) & 0xFFFF)

    def bed(lo, hi, level, wobble=0.0, wob_freq=0.1):
        b = bandpass(noise(n), lo, hi, sr)
        if wobble:
            b *= 1.0 - wobble * 0.5 * (1 + np.sin(2 * np.pi * wob_freq * t))
        return b * level

    if name == "suburb_night":
        out += bed(80, 600, 0.22, 0.35, 0.05)          # wind
        out += bed(1200, 5000, 0.05, 0.6, 0.03)        # leaves
        crickets = np.zeros(n)
        for k in range(6):
            f = rnd.uniform(3600, 5200)
            phase = rnd.uniform(0, 1)
            pulse = np.maximum(0, np.sin(2 * np.pi * (0.7 + 0.4 * k) * t + phase * 6.28)) ** 24
            crickets += np.sin(2 * np.pi * f * t) * pulse * 0.05
        out += crickets
    elif name == "indoor_house":
        out += bed(40, 300, 0.2, 0.2, 0.07)
        out += bed(2000, 6000, 0.02)
    elif name == "hq_lobby":
        out += bed(50, 400, 0.14, 0.15, 0.05)
        hum = np.sin(2 * np.pi * 60 * t) * 0.05 + np.sin(2 * np.pi * 120 * t) * 0.03
        out += hum
        out += bed(3000, 9000, 0.015)
    elif name == "endless_hum":
        out += bed(40, 500, 0.2, 0.5, 0.04)
        out += np.sin(2 * np.pi * 41.0 * t) * 0.06
        out += np.sin(2 * np.pi * 82.5 * t) * 0.04
        out += bed(1500, 4000, 0.03, 0.8, 0.02)
    elif name == "mansion_creak":
        out += bed(50, 400, 0.16, 0.3, 0.05)
        for k in range(4):
            start = int(rnd.uniform(0, dur - 3) * sr)
            ln = int(2.2 * sr)
            seg = house_crease(k)[:ln]
            if start + ln < n:
                out[start:start + ln] += seg[:ln][: n - start] * 0.5
    elif name == "mansion_quiet":
        out += bed(40, 300, 0.12, 0.12, 0.03)
        out += bed(2500, 8000, 0.012)
    elif name == "water_ambience":
        out += bed(60, 700, 0.24, 0.5, 0.08)
        for k in range(14):                      # drips
            start = int(rnd.uniform(0, dur - 1) * sr)
            ln = int(0.35 * sr)
            f = rnd.uniform(500, 1400)
            seg = np.sin(2 * np.pi * f * np.linspace(0, 0.35, ln)) * np.exp(-np.linspace(0, 0.35, ln) / 0.05)
            out[start:start + ln] += seg[: max(0, min(ln, n - start))] * 0.25
    elif name == "hotel_hum":
        out += bed(50, 450, 0.18, 0.25, 0.04)
        out += np.sin(2 * np.pi * 100 * t) * 0.04
        out += np.sin(2 * np.pi * 50 * t) * 0.05
        out += bed(2000, 6000, 0.02, 0.5, 0.1)
    elif name == "organic_breathe":
        breath = 0.5 + 0.5 * np.sin(2 * np.pi * 0.12 * t)
        out += bed(40, 350, 0.24) * (0.4 + 0.9 * breath)
        out += bed(300, 1200, 0.06) * breath
        out += np.sin(2 * np.pi * 33 * t) * 0.06
    elif name == "last_customer":
        out += bed(30, 300, 0.22, 0.4, 0.02)
        out += np.sin(2 * np.pi * 28 * t) * 0.09
        out += np.sin(2 * np.pi * 55.7 * t) * 0.04
        out += bed(900, 2600, 0.02, 0.7, 0.03)
    else:
        out += bed(50, 500, 0.2)

    out = reverb(out, 1.2, 0.25, sr)
    # crossfade the loop point so it cycles without a click
    fade = int(1.5 * sr)
    head = out[:fade].copy()
    out[:fade] = out[:fade] * np.linspace(0, 1, fade) + out[-fade:] * np.linspace(1, 0, fade)
    out = out[:-fade]
    return out


# ------------------------------------------------------------------ music ---
def note(freq: float, dur: float, sr: int = MLOOP, kind: str = "sine") -> np.ndarray:
    t = np.linspace(0, dur, int(dur * sr), endpoint=False)
    if kind == "sine":
        x = np.sin(2 * np.pi * freq * t)
    elif kind == "tri":
        x = 2 * np.abs(2 * ((t * freq) % 1.0) - 1.0) - 1.0
    else:
        x = np.sign(np.sin(2 * np.pi * freq * t)) * 0.6
    a = max(1, int(0.02 * sr))
    e = np.ones_like(t)
    e[:a] = np.linspace(0, 1, a)
    e[-int(dur * sr * 0.3):] *= np.linspace(1, 0, int(dur * sr * 0.3))
    return x * e


def music_cue(name: str) -> np.ndarray:
    """Slow, restrained cues: pads, sparse arpeggios, low drones. 32 s loops."""
    sr = MLOOP
    dur = 32.0
    n = int(dur * sr)
    out = np.zeros(n)
    rnd = random.Random(hash(name) & 0xFFFF)
    A = 55.0
    scales = {
        "menu_corporate": ("major", 1.0, [0, 4, 7, 11, 12]),
        "hq_lobby": ("major", 1.15, [0, 4, 7, 9, 12]),
        "prop_calm": ("minor", 0.9, [0, 3, 7, 10, 12]),
        "prop_uneasy": ("minor", 0.8, [0, 3, 6, 7, 10]),
        "prop_tension": ("minor", 0.7, [0, 1, 3, 6, 8]),
        "prop_dread": ("minor", 0.6, [0, 1, 5, 6, 10]),
        "escape": ("minor", 1.3, [0, 3, 7, 8, 12]),
        "result_sting": ("major", 1.0, [0, 5, 7, 12]),
        "menu_sting": ("major", 1.0, [0, 4, 7]),
    }
    mode, energy, steps = scales.get(name, scales["prop_calm"])

    def place(buf, seg, start_s, gain=1.0, pan=0.0):
        s = int(start_s * sr)
        if s >= len(buf):
            return
        ln = min(len(seg), len(buf) - s)
        buf[s:s + ln] += seg[:ln] * gain * (1.0 - abs(pan) * 0.4)

    # chord pad
    roots = [0, -2, -4, -2]
    for i, r in enumerate(roots):
        start = i * dur / len(roots)
        base = A * 2 ** (r / 12.0)
        for k, s in enumerate(steps[:3]):
            f = base * 2 ** (s / 12.0)
            seg = note(f, dur / len(roots) + 1.5, sr, "tri") * 0.09
            place(out, seg, start)
            seg2 = note(f * 2, dur / len(roots) + 1.0, sr, "sine") * 0.05
            place(out, seg2, start)
        # low drone
        place(out, note(base / 2, dur / len(roots) + 2.0, sr, "sine") * 0.12, start)

    # sparse arpeggio / tension ticks
    ticks = int(dur / 2.0 * energy)
    for i in range(ticks):
        when = rnd.uniform(0, dur - 1.0)
        step = steps[rnd.randrange(len(steps))]
        octave = rnd.choice([1, 2, 2, 4])
        f = A * octave * 2 ** (step / 12.0)
        seg = note(f, rnd.uniform(0.4, 1.4), sr, "sine") * rnd.uniform(0.03, 0.07) * energy
        place(out, seg, when, 1.0, rnd.uniform(-0.5, 0.5))

    if name in ("prop_dread", "last_customer"):
        # sub-bass heartbeat
        for i in range(8):
            when = i * 4.0 + rnd.uniform(0, 0.3)
            seg = thump(40, 0.7, 0.12, sr) * 0.18
            place(out, seg, when)

    out = reverb(out, 2.0, 0.35, sr)
    out = lowpass(out, 7000, sr)
    fade = int(2.0 * sr)
    head = out[:fade].copy()
    out[:fade] = out[:fade] * np.linspace(0, 1, fade) + out[-fade:] * np.linspace(1, 0, fade)
    out = out[:-fade]
    return out


# ------------------------------------------------------------------ build ---
SFX_SETS = {
    "imp": (impact, ["wood", "metal", "glass", "ceramic", "fabric", "paper", "electronics", "default"], 3),
    "break": (shatter, ["wood", "metal", "glass", "ceramic"], 2),
    "scrape": (scrape, ["wood", "metal", "fabric", "default"], 3),
}
FOOT_KINDS = ["step", "run", "crouch"]
DOOR_KINDS = ["open", "close", "slam", "locked"]
AMBIENCES = ["suburb_night", "indoor_house", "hq_lobby", "endless_hum", "mansion_creak",
             "mansion_quiet", "water_ambience", "hotel_hum", "organic_breathe", "last_customer"]
MUSIC = ["menu_corporate", "hq_lobby", "prop_calm", "prop_uneasy", "prop_tension",
         "prop_dread", "escape", "result_sting"]


def build_sfx() -> None:
    for prefix, (fn, materials, count) in SFX_SETS.items():
        for mat in materials:
            for v in range(1, count + 1):
                write_wav(os.path.join(SFX, f"{prefix}_{mat}_{v:02d}.wav"), fn(mat, v))
    for kind in FOOT_KINDS:
        for v in range(1, 4):
            write_wav(os.path.join(SFX, f"foot_{kind}_{v:02d}.wav"), footstep(kind, v))
    for kind in DOOR_KINDS:
        for v in range(1, 3):
            write_wav(os.path.join(SFX, f"door_{kind}_{v:02d}.wav"), door(kind, v))
    for v in range(1, 4):
        write_wav(os.path.join(SFX, f"house_creak_{v:02d}.wav"), house_crease(v))
        write_wav(os.path.join(SFX, f"whisper_{v:02d}.wav"), whisper(v))
        write_wav(os.path.join(SFX, f"radio_static_{v:02d}.wav"), radio_static(v))
        write_wav(os.path.join(SFX, f"light_buzz_{v:02d}.wav"), light_buzz(v))
        write_wav(os.path.join(SFX, f"house_react_{v:02d}.wav"), house_crease(v + 10) * 0.8)

    simple = {
        "player_jump": lambda: series(thump(180, 0.28, 0.06), bandpass(noise(int(0.14 * SR)) *
                        env_exp(int(0.14 * SR), 0.001, 0.04), 400, 2500) * 0.3),
        "player_land": lambda: series(impact("fabric", 4) * 0.7, thump(80, 0.4, 0.12) * 0.6),
        "player_hurt": lambda: series(bandpass(noise(int(0.3 * SR)) * env_exp(int(0.3 * SR), 0.005, 0.05),
                                    300, 1500) * 0.5, thump(110, 0.35, 0.1) * 0.4),
        "grab": lambda: ui_click(420, 0.09),
        "revive": lambda: series(ui_click(520, 0.1), ui_click(780, 0.12)),
        "click": lambda: ui_click(900, 0.05),
        "click_denied": lambda: ui_click(180, 0.12),
        "ui_click": lambda: ui_click(1200, 0.045),
        "purchase": lambda: series(ui_click(660, 0.09), ui_click(990, 0.09), ui_click(1320, 0.14)),
        "paper": lambda: series(highpass(noise(int(0.4 * SR)) * env_exp(int(0.4 * SR), 0.02, 0.12), 1800) * 0.4),
        "vending": lambda: series(impact("metal", 7) * 0.6, ui_click(300, 0.1)),
        "truck_load": lambda: series(impact("wood", 5) * 0.8, thump(70, 0.5, 0.15) * 0.5),
        "truck_door": lambda: series(door("slam", 7) * 0.7, impact("metal", 2) * 0.5),
        "emote": lambda: series(ui_click(880, 0.08), ui_click(1180, 0.08)),
        "portal": lambda: series(highpass(noise(int(0.9 * SR)) * env_exp(int(0.9 * SR), 0.05, 0.25), 900) * 0.35,
                                 np.sin(2 * np.pi * 220 * t_axis(0.9)) * env_exp(int(0.9 * SR), 0.02, 0.15) * 0.2),
        "doll_move": lambda: series(bandpass(noise(int(0.35 * SR)) * env_exp(int(0.35 * SR), 0.002, 0.05), 900, 4500) * 0.4,
                                    thump(240, 0.2, 0.03) * 0.2),
        "doll_drop": lambda: series(impact("ceramic", 9) * 0.8, ui_click(1400, 0.06) * 0.3),
        "water_surge": lambda: series(lowpass(noise(int(1.6 * SR)), 900) * env_exp(int(1.6 * SR), 0.2, 0.6) * 0.6),
        "elevator": lambda: series(np.sin(2 * np.pi * 110 * t_axis(2.4)) * 0.18 * env_exp(int(2.4 * SR), 0.1, 1.6),
                                   ui_click(660, 0.12) * 0.5),
        "hotel_knock": lambda: series(impact("wood", 11) * 0.7, impact("wood", 12)[: int(0.2 * SR)] * 0.5,
                                      impact("wood", 13)[: int(0.2 * SR)] * 0.4),
        "break_wood_03": lambda: shatter("wood", 3),
        # --- creature voices: original, synthesised, deliberately unmusical ---
        "creature_growl": lambda: series(
            lowpass(noise(int(1.5 * SR)), 340) * env_exp(int(1.5 * SR), 0.25, 0.5) * 0.7,
            np.sin(2 * np.pi * 58 * t_axis(1.5) + 2.5 * np.sin(2 * np.pi * 3.1 * t_axis(1.5)))
            * env_exp(int(1.5 * SR), 0.2, 0.45) * 0.3),
        "creature_shriek": lambda: series(
            highpass(noise(int(1.1 * SR)) * env_exp(int(1.1 * SR), 0.01, 0.2), 1400) * 0.45,
            note(880, 1.0, SR, "saw") * np.linspace(0.2, 0.02, int(1.0 * SR)) * 0.25),
        "creature_breath": lambda: series(
            bandpass(noise(int(0.75 * SR)) * env_exp(int(0.75 * SR), 0.3, 0.35), 240, 1600) * 0.55),
        "creature_steps": lambda: series(
            thump(70, 0.5, 0.1) * 0.6,
            np.pad(thump(66, 0.5, 0.1) * 0.5, (int(0.55 * SR), max(0, int(1.6 * SR) - int(0.55 * SR) - len(thump(66, 0.5, 0.1)))))),
        "heartbeat": lambda: series(
            thump(48, 0.32, 0.07) * 0.9,
            np.pad(thump(44, 0.3, 0.06) * 0.6, (int(0.3 * SR), max(0, int(0.9 * SR) - int(0.3 * SR) - len(thump(44, 0.3, 0.06)))))),
    }
    for name, fn in simple.items():
        write_wav(os.path.join(SFX, f"{name}.wav"), fn())
    print(f"  sfx: {len(os.listdir(SFX))} files")


def build_ambience() -> None:
    for name in AMBIENCES:
        write_wav(os.path.join(AMB, f"{name}.wav"), ambience(name), MLOOP)
    print(f"  ambience: {len(os.listdir(AMB))} files")


def build_music() -> None:
    for name in MUSIC:
        write_wav(os.path.join(MUS, f"{name}.wav"), music_cue(name), MLOOP)
    print(f"  music: {len(os.listdir(MUS))} files")


def build_voice() -> None:
    """Corporate PA lines + a handful of training-video lines via espeak-ng."""
    espeak = shutil.which("espeak-ng") or shutil.which("espeak")
    if espeak is None:
        print("  voice: espeak-ng not found, skipping (game falls back to subtitles only)")
        return
    import json
    with open(os.path.join(ROOT, "resources", "flavor.json"), "r", encoding="utf-8") as f:
        flavor = json.load(f)
    lines = flavor.get("announcements", [])
    made = 0
    for i, text in enumerate(lines, start=1):
        out = os.path.join(VOX, f"announcement_{i:02d}.wav")
        subprocess.run([espeak, "-v", "en-us+f3", "-s", "152", "-p", "42", "-w", out, text],
                       check=False, capture_output=True)
        if os.path.exists(out):
            made += 1
    training = [
        ("training_01", "Welcome to LAST MOVE INCORPORATED. Before your first shift, please remember: the house is not alive. The house is not alive. The house is not alive."),
        ("training_02", "Lift with your legs. Do not lift with your colleagues. They are not insured."),
        ("training_03", "If a door closes behind you, that is normal. If a door closes in front of you, please log it on form twelve B."),
        ("training_04", "Reporting a supernatural incident does not pause the deadline. Nothing pauses the deadline."),
    ]
    for name, text in training:
        out = os.path.join(VOX, f"{name}.wav")
        subprocess.run([espeak, "-v", "en-us+m3", "-s", "140", "-p", "40", "-w", out, text],
                       check=False, capture_output=True)
        if os.path.exists(out):
            made += 1
    print(f"  voice: {made} lines")


def main() -> None:
    args = sys.argv[1:]
    if "--voice-only" not in args:
        print("[audio] synthesising sfx…")
        build_sfx()
        print("[audio] synthesising ambience…")
        build_ambience()
        print("[audio] composing music…")
        build_music()
    if "--no-voice" not in args:
        print("[audio] synthesising voice…")
        build_voice()
    if "--no-ogg" not in args:
        print("[audio] compressing loops to ogg…")
        compress_loops()
    print("[audio] done")


def compress_loops() -> None:
    """Godot streams .ogg natively; it keeps the project a sane size."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        print("  ffmpeg not found: leaving wav files in place")
        return
    converted = 0
    for folder, quality in ((AMB, "4"), (MUS, "4"), (VOX, "3")):
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".wav"):
                continue
            src = os.path.join(folder, name)
            dst = os.path.join(folder, name[:-4] + ".ogg")
            r = subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", src,
                                "-c:a", "libvorbis", "-q:a", quality, dst], capture_output=True)
            if r.returncode == 0 and os.path.exists(dst) and os.path.getsize(dst) > 1024:
                os.remove(src)
                converted += 1
    print(f"  compressed {converted} files to ogg")


if __name__ == "__main__":
    main()
