"""Synthesizes Paste's original UI sounds into Resources/ (16-bit stereo WAV, 44.1 kHz)."""
import math, struct, sys, wave

SR = 44100

def write(path, samples, level=0.7):
    peak = max(1e-9, max(abs(s) for s in samples))
    samples = [s / peak * level for s in samples]
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<hh", int(s * 32767), int(s * 32767)) for s in samples))

def pluck(freq, dur, decay, start=0.0, total=0.22, harmonics=((1, 1.0), (2, 0.28), (3, 0.08))):
    out = [0.0] * int(total * SR)
    s0 = int(start * SR)
    for i in range(int(dur * SR)):
        t = i / SR
        attack = min(1.0, t / 0.003)
        env = attack * math.exp(-t / decay)
        v = sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics)
        if s0 + i < len(out):
            out[s0 + i] += env * v
    return out

def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]

# Copy: a short paper swish — band-passed noise, quick attack, crinkly texture, ~0.18 s.
import random

def biquad_bandpass(x, f0, q):
    w0 = 2 * math.pi * f0 / SR
    alpha = math.sin(w0) / (2 * q)
    b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * math.cos(w0), 1 - alpha
    y = [0.0] * len(x); x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        out = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, v, y1, out
        y[i] = out
    return y

def paper_swish(total=0.11, seed=3):
    """A hushed brush of paper: warm, low-passed noise with a slow swell and gentle tail."""
    random.seed(seed)
    n = int(total * SR)
    noise = [random.uniform(-1, 1) for _ in range(n)]
    # Wide, low bands = soft and warm; no bright hiss, no crackle.
    air = biquad_bandpass(noise, 2600, 0.6)
    body = biquad_bandpass(noise, 900, 0.7)
    out = []
    for i in range(n):
        t = i / SR
        swell = math.sin(min(1.0, t / 0.015) * math.pi / 2) ** 2     # ~15 ms ease-in
        tail = math.exp(-max(0.0, t - 0.02) / 0.025)
        out.append(swell * tail * (0.55 * air[i] + 0.6 * body[i]))
    # gentle one-pole low-pass to round off any edge
    y, prev = [], 0.0
    for v in out:
        prev += 0.35 * (v - prev)
        y.append(prev)
    return y

copy = paper_swish()

# Paste: a short, low wooden tap with a tiny noise transient, ~0.08 s.
random.seed(7)
tap = pluck(420.0, 0.08, 0.016, 0.0, 0.08, harmonics=((1, 1.0), (2.7, 0.35), (5.1, 0.12)))
click = [(random.uniform(-1, 1) * math.exp(-i / (SR * 0.0015))) * 0.5 for i in range(int(0.01 * SR))]
paste = mix(tap, click)

out = sys.argv[1]
write(f"{out}/Copy.wav", copy, level=0.22)
write(f"{out}/Paste.wav", paste)
print("wrote", out)
