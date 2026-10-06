#!/usr/bin/env python3
"""Synthesizes the timer sounds (no samples, no third-party audio: no licensing
questions). Output: 16-bit mono 44.1 kHz WAV files, each well under the 30 s
limit for notification sounds.

    python3 scripts/make-sounds.py [OUT_DIR]

Default OUT_DIR: App/StrongBabeClub/Resources/Sounds

Files (names must match WorkoutCore's TimerCue.soundFile):
    work.wav       "go": two short rising beeps (work / new round starts)
    bell_rest.wav  boxing-gym "ding-ding" (round over) then a soft, low,
                   falling two-note chime (rest starts)
    bell_work.wav  "ding-ding" (round over) then the go beeps (EMOM sets)
    finish.wav     three bell strikes (all rounds done)

Deterministic: same script, same bytes.
"""

import math
import os
import struct
import sys
import wave

RATE = 44100


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


def chime(freq, seconds, amp=0.7):
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


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "App", "StrongBabeClub", "Resources", "Sounds")
    os.makedirs(out_dir, exist_ok=True)

    go = mix((0.0, beep(880, 0.16)), (0.22, beep(1320, 0.30)))
    ding_ding = mix((0.0, bell_strike(1.5)), (0.34, bell_strike(1.5)))
    rest = mix((0.0, chime(659.25, 0.9)), (0.32, chime(440.0, 1.2)))

    sounds = {
        "work.wav": go,
        "bell_rest.wav": mix((0.0, ding_ding), (1.05, rest)),
        "bell_work.wav": mix((0.0, ding_ding), (0.95, go)),
        "finish.wav": mix((0.0, bell_strike(1.6)), (0.34, bell_strike(1.6)), (0.68, bell_strike(2.2))),
    }
    for name, samples in sounds.items():
        path = os.path.join(out_dir, name)
        write(path, samples)
        print(f"{name}: {len(samples) / RATE:.2f} s")


if __name__ == "__main__":
    main()
