#!/usr/bin/env python3
"""Render deterministic pickup chimes using only Python stdlib.

Run manually after editing the phrases; generated WAVs are shipped with the game.
"""
from array import array
import math
from pathlib import Path
import sys
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def note(buffer, start, duration, midi, gain, pan=0.0):
    frequency = 440.0 * 2 ** ((midi - 69) / 12)
    length = int(duration * RATE)
    offset = round(start * RATE)
    left = math.sqrt((1 - pan) / 2)
    right = math.sqrt((1 + pan) / 2)
    for i in range(length):
        frame = offset + i
        if frame >= len(buffer) // 2:
            break
        t = i / RATE
        phase = math.tau * frequency * t
        envelope = min(t / 0.008, 1.0) * math.exp(-5 * t / duration)
        envelope *= min((duration - t) / 0.035, 1.0)
        tone = (
            math.sin(phase)
            + 0.24 * math.sin(phase * 2) * math.exp(-9 * t)
            + 0.08 * math.sin(phase * 3) * math.exp(-15 * t)
        )
        index = frame * 2
        value = tone * envelope * gain
        buffer[index] += value * left
        buffer[index + 1] += value * right


def save(name, buffer, peak):
    maximum = max(abs(value) for value in buffer)
    pcm = array("h", (round(value / maximum * peak * 32767) for value in buffer))
    if sys.byteorder != "little":
        pcm.byteswap()
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    print(f"{name}: {len(buffer) / (RATE * 2):.2f}s, peak {peak:.2f}")


def main():
    phrases = {
        "pickup_red.wav": [72, 76],
        "pickup_green.wav": [72, 76, 79],
        "pickup_gold.wav": [76, 79, 84],
        "pickup_rainbow.wav": [72, 76, 79, 84],
    }
    for name, pitches in phrases.items():
        duration = (len(pitches) - 1) * 0.065 + 0.38
        chime = array("d", [0.0]) * (math.ceil(duration * RATE) * 2)
        for index, pitch in enumerate(pitches):
            note(chime, index * 0.065, 0.38, pitch, 0.35)
            note(chime, index * 0.065, 0.30, pitch - 12, 0.09)
        save(name, chime, 0.65)


if __name__ == "__main__":
    main()
