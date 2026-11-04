"""Synthesised sounds for the Diwali greeting (no licensed audio: Freesound and Wikimedia are unreachable here).

usage: $MEDIA_PY media/projects/diwali-2026/sounds.py <out_dir> [--duration 20]

Writes <out_dir>/{drone,match,catch,catch-soft,bell}.mp3 for pipeline/mix.py:
  drone       tanpura-like drone (Pa-Sa-Sa-Sa plucks with a jawari bloom), for the whole film
  match       match strike: scrape, ignition, short flame hiss
  catch       a wick catching from another flame (soft breath of fire)
  catch-soft  the same, quieter and shorter, for lamps further along the row
  bell        a small brass hand bell (inharmonic partials, slow beating)
All made from numbers in this file; deterministic (fixed seeds).
"""
import argparse
import subprocess
from pathlib import Path

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 48000


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=SR, output="sos"), x)


def room(x, seconds=1.6, wet=0.22, seed=3):
    """small warm room: convolve with exponentially decaying filtered noise"""
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir = lp(r.standard_normal(n), 5000) * np.exp(-np.arange(n) / SR * 4.5)
    ir /= np.sqrt((ir ** 2).sum())
    return (1 - wet) * x + wet * fftconvolve(x, ir)[: len(x)]


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)


def pluck(f0, seconds, seed):
    """one tanpura string: rich harmonics, high ones bloom after the attack (the jawari buzz), slow decay"""
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 36):
        f = f0 * k * (1 + 0.0004 * r.standard_normal())
        if f > 9000:
            break
        bloom = 1 + 1.6 * (k > 4) * (1 - np.exp(-t / 0.35)) * np.exp(-t / (1.4 + 0.08 * k))
        a = (k ** -0.9) * bloom * np.exp(-t / (5.5 / (1 + 0.04 * k)))
        out += a * np.sin(2 * np.pi * f * t + r.uniform(0, 2 * np.pi))
    out *= np.minimum(t / 0.012, 1)
    return out


def drone(seconds):
    sa = 138.59  # C#3, a common male tanpura tuning
    pa = sa * 3 / 4  # Pa below Sa
    pattern = [(pa, 0.0), (sa * 2, 1.15), (sa * 2, 2.05), (sa, 2.95)]  # one cycle of four strings
    cycle = 4.2
    n = int(seconds * SR)
    out = np.zeros(n + 8 * SR)
    c, seed = 0.0, 0
    while c < seconds:
        for f, off in pattern:
            s = int((c + off) * SR)
            p = pluck(f, 7.0, seed) * (0.9 + 0.2 * np.random.default_rng(seed).random())
            out[s:s + len(p)] += p
            seed += 1
        c += cycle
    out = out[:n]
    out = lp(hp(out, 95, 4), 6500)
    t = np.arange(n) / SR
    out *= np.minimum(t / 2.5, 1) * np.minimum((seconds - t) / 1.5, 1).clip(0, 1)  # fade in, fade out
    return hp(room(out, 2.2, 0.3), 80, 4)


def match():
    r = np.random.default_rng(11)
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    noise = r.standard_normal(n)
    # scrape: grainy bursts over 90 ms
    scrape = bp(noise, 1500, 7000) * (t < 0.09) * (0.5 + 0.5 * (r.random(n) < 0.08))
    scrape *= np.exp(-np.maximum(t - 0.06, 0) / 0.02)
    # ignition: a quick flare, low-pass opening from 400 Hz to 3 kHz
    flare = np.zeros(n)
    s = int(0.085 * SR)
    seg = noise[s:]
    tt = np.arange(len(seg)) / SR
    chunks = []
    for i in range(0, len(seg), 960):
        fc = 400 + 2600 * min(tt[i] / 0.12, 1) * np.exp(-tt[i] / 0.5)
        chunks.append(lp(seg[i:i + 960], max(fc, 300)))
    flare[s:] = np.concatenate(chunks)[: len(seg)] * env(len(seg), 0.02, 0.35) * 1.4
    # crackle: sparse clicks
    crack = (r.random(n) < 0.0009) * r.standard_normal(n) * np.exp(-t / 0.6) * 3
    crack = hp(crack, 1500)
    out = 0.8 * scrape + flare + 0.5 * crack
    return hp(room(out, 1.2, 0.18), 160, 4)


def catch(seconds=1.4, gain=1.0, seed=21):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    x = lp(hp(r.standard_normal(n), 120), 1800, 3)
    x *= env(n, 0.18, seconds / 3.2)
    flick = hp((r.random(n) < 0.0006) * r.standard_normal(n), 2000) * np.exp(-np.arange(n) / SR / 0.5)
    return room(gain * (x + 0.6 * flick), 1.0, 0.2)


def bell():
    r = np.random.default_rng(31)
    f0 = 1046.5  # C6, a small brass hand bell
    ratios = [0.5, 1.0, 1.19, 1.56, 2.0, 2.51, 2.66, 3.01]
    amps = [0.35, 1.0, 0.45, 0.5, 0.42, 0.25, 0.2, 0.12]
    decays = [3.6, 3.2, 2.2, 1.8, 1.5, 1.0, 0.9, 0.6]
    n = int(4.5 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, a, d in zip(ratios, amps, decays):
        for det in (-0.6, 0.6):  # pairs slightly apart: the slow beating of a real bell
            out += a * np.exp(-t / d) * np.sin(2 * np.pi * (f0 * ratio + det) * t + r.uniform(0, 6.28))
    strike = hp(r.standard_normal(n), 3000) * np.exp(-t / 0.004) * 0.6
    out = (out + strike) * np.minimum(t / 0.002, 1)
    return room(out, 2.5, 0.28)


def write(x, path: Path):
    x = x / (np.abs(x).max() + 1e-9) * 0.89
    raw = (np.column_stack([x, x]) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libmp3lame", "-q:a", "2", str(path)], input=raw, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--duration", type=float, default=20.0)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    write(drone(a.duration), out / "drone.mp3")
    write(match(), out / "match.mp3")
    write(catch(), out / "catch.mp3")
    write(catch(0.9, seed=22), out / "catch-soft.mp3")
    write(bell(), out / "bell.mp3")
    print(f"sounds in {out}")


if __name__ == "__main__":
    main()
