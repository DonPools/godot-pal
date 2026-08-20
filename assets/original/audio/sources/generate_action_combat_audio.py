#!/usr/bin/env python3
"""Generate the original short music and combat cues used by the G4 slice."""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 22_050
ROOT = Path(__file__).resolve().parents[1]


def write_wav(name: str, samples: list[float]) -> None:
    path = ROOT / name
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        payload = bytearray()
        for sample in samples:
            value = max(-1.0, min(1.0, sample))
            payload.extend(struct.pack("<h", round(value * 32767.0)))
        output.writeframes(payload)


def music(seconds: float, notes: list[float], pulse: float) -> list[float]:
    total = round(seconds * SAMPLE_RATE)
    result: list[float] = []
    note_seconds = seconds / len(notes)
    for index in range(total):
        time = index / SAMPLE_RATE
        note_index = min(int(time / note_seconds), len(notes) - 1)
        frequency = notes[note_index]
        local = (time % note_seconds) / note_seconds
        envelope = min(local * 10.0, 1.0) * min((1.0 - local) * 5.0, 1.0)
        base = math.sin(math.tau * frequency * time)
        fifth = math.sin(math.tau * frequency * 1.5 * time) * 0.28
        rhythm = 0.72 + 0.28 * (1.0 if (time * pulse) % 1.0 < 0.18 else 0.0)
        result.append((base + fifth) * envelope * rhythm * 0.16)
    return result


def sweep(seconds: float, start: float, end: float, noise: float = 0.0) -> list[float]:
    rng = random.Random(260818)
    total = round(seconds * SAMPLE_RATE)
    result: list[float] = []
    phase = 0.0
    for index in range(total):
        progress = index / max(total - 1, 1)
        frequency = start + (end - start) * progress
        phase += math.tau * frequency / SAMPLE_RATE
        envelope = (1.0 - progress) ** 2
        sample = math.sin(phase) * 0.42 + (rng.random() * 2.0 - 1.0) * noise
        result.append(sample * envelope)
    return result


def chord(seconds: float, notes: list[float], descending: bool = False) -> list[float]:
    total = round(seconds * SAMPLE_RATE)
    result: list[float] = []
    for index in range(total):
        progress = index / max(total - 1, 1)
        envelope = math.sin(math.pi * progress) * (1.0 - progress * 0.35)
        sample = 0.0
        for note_index, frequency in enumerate(notes):
            offset = -frequency * 0.18 * progress if descending else frequency * 0.05 * progress
            sample += math.sin(math.tau * (frequency + offset) * index / SAMPLE_RATE)
        result.append(sample / len(notes) * envelope * 0.28)
    return result


def main() -> None:
    write_wav(
        "mountain_path.wav",
        music(4.8, [220.0, 261.63, 293.66, 261.63, 220.0, 196.0], 2.0),
    )
    write_wav(
        "battle_pulse.wav",
        music(4.0, [146.83, 174.61, 196.0, 174.61, 220.0, 196.0, 174.61, 146.83], 4.0),
    )
    write_wav("wind_cast.wav", sweep(0.34, 260.0, 980.0, 0.04))
    write_wav("sword_hit.wav", sweep(0.18, 180.0, 72.0, 0.22))
    write_wav("dodge.wav", sweep(0.22, 720.0, 240.0, 0.05))
    write_wav("victory.wav", chord(0.72, [261.63, 329.63, 392.0]))
    write_wav("escaped.wav", chord(0.52, [220.0, 293.66], True))
    write_wav("defeat.wav", chord(0.85, [196.0, 155.56, 130.81], True))
    write_wav("charge_windup.wav", sweep(0.8, 82.41, 349.23, 0.035))
    write_wav("pillar_stagger.wav", sweep(0.62, 154.0, 42.0, 0.34))
    write_wav("breakthrough.wav", chord(1.18, [220.0, 293.66, 369.99, 440.0]))
    write_wav("array_restore.wav", chord(0.92, [196.0, 261.63, 329.63]))
    write_wav("array_salvage.wav", sweep(0.68, 520.0, 96.0, 0.14))


if __name__ == "__main__":
    main()
