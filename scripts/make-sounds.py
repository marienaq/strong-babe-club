#!/usr/bin/env python3
"""Synthesizes the timer sounds (no samples, no third-party audio: no licensing
questions). Output: 16-bit mono 22.05 kHz WAV files, each well under the 30 s
limit for notification sounds.

    python3 scripts/make-sounds.py [OUT_DIR]

Default OUT_DIR: App/StrongBabeClub/Resources/Sounds

Five packs: boxing (gym bell), arcade (8-bit bleeps), chimes (wind chimes),
cowbell, marimba (soft). Each pack has four cues, written as
<pack>_<cue>.wav to match WorkoutCore's TimerCue.soundFile(pack:):
    work       "go": work / a new round starts
    bell_rest  round over, then the pack's calm "rest" cue
    bell_work  round over, then "go" (EMOM sets)
    finish     all rounds done

Deterministic: same script, same bytes.
"""

import math
import os
import struct
import sys
import wave

RATE = 22050  # plenty for these cues; keeps 20 files small


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def bell_strike(seconds=1.6, f0=740.0):
    """Struck metal: inharmonic partials with fast attack and exponential
    decay; higher partials die faster. Roughly a boxing-ring bell."""
    partials = [(1.0, 1.0, 1.6), (2.76, 0.55, 2.6), (5.40, 0.32, 4.0), (8.93, 0.18, 6.5), (1.5, 0.22, 2.0)]
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        attack = min(1.0, t / 0.002)
        s = 0.0
        for ratio, amp, decay in partials:
            s += amp * math.exp(-decay * t) * math.sin(2 * math.pi * f0 * ratio * t)
        # Tiny clank at the strike.
        s += 0.25 * math.exp(-60 * t) * math.sin(2 * math.pi * 3100 * t)
        out.append(attack * s)
    return out


def beep(freq, seconds, amp=0.8):
    """Rounded square-ish beep (odd harmonics) with short fades: punchy but not harsh."""
    n = int(RATE * seconds)
    fade = int(RATE * 0.012)
    out = []
    for i in range(n):
        t = i / RATE
        s = sum(math.sin(2 * math.pi * freq * k * t) / k for k in (1, 3, 5))
        env = min(1.0, i / fade, (n - i) / fade)
        out.append(amp * 0.75 * env * s)
    return out


def chime_soft(freq, seconds, amp=0.7):
    """Soft sine chime with a gentle decay (calm: time to rest)."""
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.02) * math.exp(-2.2 * t)
        s = math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(2 * math.pi * freq * 2 * t)
        out.append(amp * env * s)
    return out


def mix(*tracks):
    """tracks: (offset_seconds, samples)."""
    length = max(int(off * RATE) + len(x) for off, x in tracks)
    out = [0.0] * length
    for off, x in tracks:
        start = int(off * RATE)
        for i, v in enumerate(x):
            out[start + i] += v
    return out


def normalize(x, peak=0.89):
    m = max(abs(v) for v in x) or 1.0
    return [v * peak / m for v in x]


def write(path, samples):
    samples = normalize(samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in samples))


# ---------------------------------------------------------------- packs

def tone(freq, seconds, amp=0.7, decay=6.0, partials=((1, 1.0),), attack=0.004):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        out.append(amp * env * sum(a * math.sin(2 * math.pi * freq * r * t) for r, a in partials))
    return out


def square(freq, seconds, amp=0.5):
    n = int(RATE * seconds)
    fade = int(RATE * 0.006)
    return [amp * min(1.0, i / fade, (n - i) / fade) * (1.0 if math.sin(2 * math.pi * freq * i / RATE) >= 0 else -1.0)
            for i in range(n)]


def seq(notes, gap):
    """notes: list of sample lists played `gap` seconds apart."""
    return mix(*[(i * gap, x) for i, x in enumerate(notes)])


def cowbell(freq=560.0, seconds=0.5):
    # Two detuned square-ish partials with a fast, metallic decay.
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-9 * t)
        a = math.copysign(1, math.sin(2 * math.pi * freq * t))
        b = math.copysign(1, math.sin(2 * math.pi * freq * 1.48 * t))
        out.append(0.4 * env * (a + 0.8 * b) * (1 - math.exp(-t * 400)))
    return out


def marimba(freq, seconds=0.6):
    return tone(freq, seconds, amp=0.8, decay=7, partials=((1, 1.0), (4, 0.25), (10, 0.05)))


def chime(freq, seconds=2.0):
    return tone(freq, seconds, amp=0.5, decay=1.6, partials=((1, 1.0), (2.76, 0.4), (5.4, 0.15)))


def boxing():
    go = mix((0.0, beep(880, 0.16)), (0.22, beep(1320, 0.30)))
    end = mix((0.0, bell_strike(1.5)), (0.34, bell_strike(1.5)))
    rest = mix((0.0, chime_soft(659.25, 0.9)), (0.32, chime_soft(440.0, 1.2)))
    fin = mix((0.0, bell_strike(1.6)), (0.34, bell_strike(1.6)), (0.68, bell_strike(2.2)))
    return go, end, 1.05, rest, fin


def arcade():
    go = seq([square(f, 0.07) for f in (523.25, 659.25, 783.99, 1046.5)], 0.075)
    end = seq([square(987.77, 0.08), square(1318.5, 0.32)], 0.085)          # coin
    rest = seq([square(783.99, 0.14), square(523.25, 0.14), square(392.0, 0.3)], 0.15)
    fin = seq([square(f, 0.1) for f in (523.25, 659.25, 783.99, 1046.5, 783.99)] + [square(1046.5, 0.45)], 0.11)
    return go, end, 0.45, rest, fin


def wind_chimes():
    go = seq([chime(1567.98, 1.2), chime(2093.0, 1.4)], 0.12)
    end = seq([chime(f, 1.6) for f in (1318.5, 1760.0, 2349.3)], 0.09)
    rest = seq([chime(659.25, 2.0), chime(523.25, 2.2)], 0.35)
    fin = seq([chime(f, 1.8) for f in (2349.3, 2093.0, 1760.0, 1567.98, 1318.5, 1046.5)], 0.11)
    return go, end, 0.6, rest, fin


def cowbells():
    go = seq([cowbell(560, 0.25), cowbell(560, 0.45)], 0.16)
    end = seq([cowbell(560, 0.3), cowbell(560, 0.3), cowbell(560, 0.5)], 0.14)
    rest = cowbell(380, 0.9)
    fin = seq([cowbell(560, 0.22)] * 6 + [cowbell(560, 0.8)], 0.1)
    return go, end, 0.65, rest, fin


def soft_marimba():
    go = seq([marimba(f) for f in (523.25, 659.25, 783.99)], 0.11)
    end = seq([marimba(1046.5, 0.8), marimba(783.99, 0.9)], 0.16)
    rest = seq([marimba(f, 0.9) for f in (783.99, 659.25, 523.25)], 0.18)
    fin = seq([marimba(f) for f in (523.25, 659.25, 783.99, 1046.5)] + [marimba(1318.5, 1.2)], 0.12)
    return go, end, 0.5, rest, fin


PACKS = {"boxing": boxing, "arcade": arcade, "chimes": wind_chimes, "cowbell": cowbells, "marimba": soft_marimba}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "App", "StrongBabeClub", "Resources", "Sounds")
    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        if old.endswith(".wav"):
            os.remove(os.path.join(out_dir, old))
    for pack, build in PACKS.items():
        go, end, end_len, rest, fin = build()
        sounds = {
            "work": go,
            "bell_rest": mix((0.0, end), (end_len, rest)),
            "bell_work": mix((0.0, end), (end_len, go)),
            "finish": fin,
        }
        for cue, samples in sounds.items():
            name = f"{pack}_{cue}.wav"
            write(os.path.join(out_dir, name), samples)
            print(f"{name}: {len(samples) / RATE:.2f} s")


if __name__ == "__main__":
    main()
