"""Synthesizes the soundtrack and sound effects.

Requires: numpy.   Run:  python tools/gen_audio.py
Writes WAV files into assets/audio.
"""
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)

SR = 44100
rng = np.random.default_rng(1234)


def write_wav(name, data):
    data = np.asarray(data, np.float32)
    if data.ndim == 1:
        data = data[:, None]
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(pcm.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def t_arr(dur):
    return np.arange(int(dur * SR)) / SR


def one_pole_lp(x, cutoff):
    """Simple lowpass. cutoff may be scalar or per-sample array."""
    x = np.asarray(x, np.float64)
    c = np.broadcast_to(np.asarray(cutoff, np.float64), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def fft_filter(x, lo=None, hi=None, tilt=None):
    """Zero-phase spectral filter (circular) - fast for long buffers."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi is not None:
        g *= 1 / np.sqrt(1 + (f / hi) ** 4)
    if lo is not None:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** 4)
    if tilt is not None:
        g *= (np.maximum(f, 20) / 1000.0) ** tilt
    return np.fft.irfft(X * g, n=len(x))


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


# ------------------------------------------------------------------ wavetables
TABLE_N = 4096


def make_table(harmonics, rolloff, odd_only=False):
    ph = np.arange(TABLE_N) / TABLE_N
    tab = np.zeros(TABLE_N)
    for k in range(1, harmonics + 1):
        if odd_only and k % 2 == 0:
            continue
        tab += np.sin(2 * np.pi * k * ph) / k * np.exp(-k * rolloff)
    return tab / np.max(np.abs(tab))


SAW_DARK = make_table(24, 0.28)
SAW_BRIGHT = make_table(40, 0.06)
SQUARE = make_table(25, 0.08, odd_only=True)
SOFT = make_table(6, 0.6)


def osc(table, freq, n, phase0=0.0):
    freq = np.broadcast_to(np.asarray(freq, np.float64), (n,))
    ph = (phase0 + np.cumsum(freq) / SR) % 1.0
    return table[(ph * TABLE_N).astype(int) % TABLE_N]


def adsr(n, a, d, s, r, gate):
    """Envelope for n samples; gate = seconds the note is held."""
    t = np.arange(n) / SR
    env = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = t > gate
    level_at_gate = s + (1 - s) * np.exp(-(gate - a) / max(d, 1e-4)) if gate > a else gate / max(a, 1e-4)
    env[rel] = level_at_gate * np.exp(-(t[rel] - gate) / max(r, 1e-4))
    return env


# ------------------------------------------------------------------ music
BPM = 100
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = 32
TOTAL = BAR * BARS
N = int(TOTAL * SR)

CHORDS = {
    "Dm": ([62, 65, 69, 76], 38),
    "Bb": ([58, 62, 65, 72], 34),
    "F": ([60, 65, 69, 67], 41),
    "C": ([60, 64, 67, 74], 36),
    "Gm": ([62, 67, 70, 69], 43),
    "A": ([61, 64, 69, 76], 45),
}
PROG = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"] * 4

LEAD_A = [  # bars 16..23 (midi, beats)
    [(69, 1.5), (65, 0.5), (74, 2)],
    [(72, 1), (74, 0.5), (72, 0.5), (70, 2)],
    [(69, 1.5), (72, 0.5), (77, 2)],
    [(76, 1), (74, 1), (72, 1), (67, 1)],
    [(69, 1.5), (65, 0.5), (74, 1.5), (76, 0.5)],
    [(77, 2), (74, 1), (70, 1)],
    [(79, 1.5), (77, 0.5), (74, 1), (70, 1)],
    [(73, 2), (76, 1), (69, 1)],
]
LEAD_B = [  # bars 24..31
    [(74, 0.5), (77, 0.5), (81, 1), (79, 0.5), (77, 0.5), (76, 1)],
    [(77, 1.5), (74, 0.5), (70, 2)],
    [(72, 0.5), (77, 0.5), (81, 1.5), (79, 0.5), (77, 1)],
    [(76, 1.5), (79, 0.5), (76, 1), (72, 1)],
    [(74, 1), (77, 1), (81, 1), (86, 1)],
    [(84, 1.5), (82, 0.5), (77, 2)],
    [(79, 1), (82, 1), (81, 1), (79, 1)],
    [(81, 3), (None, 1)],
]


class Mix:
    def __init__(self):
        self.L = np.zeros(N + SR * 4)
        self.R = np.zeros(N + SR * 4)

    def add(self, start, sig, gain=1.0, pan=0.0):
        i = int(start * SR)
        n = len(sig)
        lg = gain * np.cos((pan + 1) * np.pi / 4)
        rg = gain * np.sin((pan + 1) * np.pi / 4)
        self.L[i:i + n] += sig * lg
        self.R[i:i + n] += sig * rg

    def wrapped(self):
        L, R = self.L[:N].copy(), self.R[:N].copy()
        L[:len(self.L) - N] += self.L[N:]
        R[:len(self.R) - N] += self.R[N:]
        return L, R


def pad_note(m, dur, bright_lfo_phase):
    n = int((dur + 1.6) * SR)
    f = mtof(m)
    sig = np.zeros(n)
    for det, pan_w in ((-0.09, 1), (0.0, 1), (0.1, 1)):
        fr = f * 2 ** (det / 12)
        dark = osc(SAW_DARK, fr, n, rng.random())
        bright = osc(SAW_BRIGHT, fr, n, rng.random())
        t = np.arange(n) / SR
        mixv = 0.2 + 0.2 * np.sin(2 * np.pi * 0.11 * t + bright_lfo_phase)
        sig += dark * (1 - mixv) + bright * mixv
    return sig / 3 * adsr(n, 0.9, 1.5, 0.8, 1.2, dur)


def pluck(m, dur, table=SQUARE, decay=0.18):
    n = int((dur + 0.6) * SR)
    s = osc(table, mtof(m), n)
    return s * adsr(n, 0.003, decay, 0.0, 0.1, dur)


def bass_note(m, dur):
    n = int((dur + 0.15) * SR)
    f = mtof(m)
    s = osc(SAW_DARK, f, n) * 0.6 + np.sin(2 * np.pi * f * np.arange(n) / SR) * 0.7
    return s * adsr(n, 0.004, 0.22, 0.45, 0.06, dur)


def lead_note(m, dur):
    n = int((dur + 0.5) * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.25) * 3, 0, 1)
    f = mtof(m) * vib
    s = osc(SOFT, f, n) * 0.7 + osc(SQUARE, f * 1.002, n) * 0.22
    return s * adsr(n, 0.02, 0.4, 0.7, 0.25, dur)


def bell(m, dur=2.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = mtof(m)
    s = np.sin(2 * np.pi * f * t + 1.5 * np.sin(2 * np.pi * f * 3.5 * t) * np.exp(-t * 3))
    return s * np.exp(-t * 2.2)


def kick():
    t = t_arr(0.45)
    f = 45 + 90 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 7) + rng.normal(0, 1, len(t)) * np.exp(-t * 200) * 0.2


def snare():
    t = t_arr(0.35)
    noise = fft_filter(rng.normal(0, 1, len(t)), lo=900, hi=7000)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25)
    return norm(noise * np.exp(-t * 13) * 0.8 + tone * 0.6, 0.9)


def hat(open_=False):
    t = t_arr(0.25 if open_ else 0.06)
    noise = fft_filter(rng.normal(0, 1, len(t)), lo=7000)
    return norm(noise * np.exp(-t * (14 if open_ else 70)), 0.8)


def compose():
    pad = Mix()
    arp = Mix()
    bass = Mix()
    lead = Mix()
    drums = Mix()
    sparkle = Mix()
    K, S, H, HO = kick(), snare(), hat(), hat(True)
    sidechain = np.ones(N + SR * 4)
    pent = [74, 76, 81, 84, 86, 88, 93]
    for bar, name in enumerate(PROG):
        t0 = bar * BAR
        notes, root = CHORDS[name]
        # ---- pad (always, quieter in last 2 bars → nice loop)
        for i, m in enumerate(notes):
            pad.add(t0, pad_note(m, BAR, i * 0.7 + bar * 0.3), 0.16, pan=(-0.5, 0.5, -0.2, 0.3)[i])
        # ---- arpeggio 16ths
        tones = sorted(notes[:3]) + [notes[0] + 12, sorted(notes[:3])[1] + 12]
        pattern = [0, 1, 2, 3, 4, 3, 2, 1, 0, 2, 1, 3, 2, 4, 3, 1]
        arp_gain = 0.07 if bar < 8 else 0.09
        for k in range(16):
            m = tones[pattern[k]] + 12
            acc = 1.0 if k % 4 == 0 else 0.7
            arp.add(t0 + k * BEAT / 4, pluck(m, BEAT / 4 * 0.8), arp_gain * acc, pan=np.sin(k * 0.8) * 0.6)
        # ---- sparkle bells in the intro / breakdown
        if bar < 8 or bar >= 30:
            for j in range(2):
                if rng.random() < 0.7:
                    m = int(rng.choice(pent))
                    sparkle.add(t0 + (j * 2 + rng.integers(0, 2)) * BEAT, bell(m), 0.07, pan=rng.uniform(-0.8, 0.8))
        # ---- bass
        if 8 <= bar < 30:
            patt = [0, 0, 12, 0, 0, 12, 0, 7]
            for k in range(8):
                bass.add(t0 + k * BEAT / 2, bass_note(root + patt[k], BEAT / 2 * 0.85), 0.32)
        # ---- drums
        if 8 <= bar < 30:
            for b in range(4):
                tb = t0 + b * BEAT
                if b in (0, 2) or (bar >= 16 and b == 3 and bar % 2 == 1):
                    drums.add(tb, K, 0.55)
                    i = int(tb * SR)
                    dip = 1 - 0.55 * np.exp(-np.arange(int(0.3 * SR)) / SR * 12)
                    sidechain[i:i + len(dip)] = np.minimum(sidechain[i:i + len(dip)], dip)
                if bar >= 16 and b in (1, 3):
                    drums.add(tb, S, 0.22, pan=0.1)
                for h in range(2):
                    th = tb + h * BEAT / 2
                    if h == 1 and b == 3 and bar % 4 == 3:
                        drums.add(th, HO, 0.09, pan=0.35)
                    else:
                        drums.add(th, H, 0.07 if h else 0.045, pan=0.35)
        # ---- lead
        if 16 <= bar < 32:
            phrase = LEAD_A[bar - 16] if bar < 24 else LEAD_B[bar - 24]
            tb = t0
            for m, beats in phrase:
                if m is not None:
                    lead.add(tb, lead_note(m, beats * BEAT * 0.95), 0.2, pan=-0.1)
                tb += beats * BEAT
    return pad, arp, bass, lead, drums, sparkle, sidechain


def delay(L, R, time_s, fb, mix):
    d = int(time_s * SR)
    outL, outR = L.copy(), R.copy()
    tapL, tapR = L.copy(), R.copy()
    g = mix
    for i in range(6):
        tapL, tapR = np.roll(tapR, d), np.roll(tapL, d)  # ping-pong, circular for loop
        outL += tapL * g
        outR += tapR * g
        g *= fb
    return outL, outR


def reverb(L, R, secs=2.8, mix=0.3):
    n = int(secs * SR)
    t = np.arange(n) / SR
    irL = rng.normal(0, 1, n) * np.exp(-t * 3.0 / secs * 2.2)
    irR = rng.normal(0, 1, n) * np.exp(-t * 3.0 / secs * 2.2)
    irL = fft_filter(np.pad(irL, (0, 0)), hi=6000)
    irR = fft_filter(irR, hi=6000)
    irL[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    irR[: int(0.017 * SR)] *= np.linspace(0, 1, int(0.017 * SR))
    size = len(L)

    def conv(x, ir):  # circular convolution → tail wraps to loop start
        X = np.fft.rfft(x, n=size)
        I = np.fft.rfft(ir, n=size)
        return np.fft.irfft(X * I, n=size)

    wl, wr = conv(L, irL), conv(R, irR)
    wl = wl / (np.max(np.abs(wl)) + 1e-9) * np.max(np.abs(L)) * 0.9
    wr = wr / (np.max(np.abs(wr)) + 1e-9) * np.max(np.abs(R)) * 0.9
    return L * (1 - mix) + wl * mix, R * (1 - mix) + wr * mix


def build_music():
    pad, arp, bass, lead, drums, sparkle, sc = compose()
    sc = sc[:N]
    padL, padR = pad.wrapped()
    arpL, arpR = arp.wrapped()
    arpL, arpR = delay(arpL, arpR, BEAT * 0.75, 0.45, 0.45)
    leadL, leadR = lead.wrapped()
    leadL, leadR = delay(leadL, leadR, BEAT * 0.5, 0.4, 0.35)
    spL, spR = sparkle.wrapped()
    spL, spR = delay(spL, spR, BEAT * 0.75, 0.5, 0.5)
    bL, bR = bass.wrapped()
    bL = fft_filter(bL, hi=900)
    bR = fft_filter(bR, hi=900)
    dL, dR = drums.wrapped()
    wetL = padL * sc + arpL * (0.6 + 0.4 * sc) + leadL + spL
    wetR = padR * sc + arpR * (0.6 + 0.4 * sc) + leadR + spR
    wetL, wetR = reverb(wetL, wetR, 3.2, 0.38)
    L = wetL + bL * sc + dL
    R = wetR + bR * sc + dR
    # soft master
    L = fft_filter(L, lo=28)
    R = fft_filter(R, lo=28)
    peak = max(np.max(np.abs(L)), np.max(np.abs(R)))
    L, R = np.tanh(L / peak * 1.3) * 0.85, np.tanh(R / peak * 1.3) * 0.85
    write_wav("music.wav", np.stack([L, R], axis=1))


# ------------------------------------------------------------------ sfx
def sfx_laser():
    t = t_arr(0.16)
    f = 380 + 1500 * np.exp(-t * 32)
    ph = np.cumsum(f) / SR
    sq = np.sign(np.sin(2 * np.pi * ph)) * 0.5 + np.sin(2 * np.pi * ph * 2) * 0.3
    s = sq * np.exp(-t * 20) + rng.normal(0, 1, len(t)) * np.exp(-t * 90) * 0.25
    return norm(fft_filter(s, hi=6500), 0.6)


def sfx_plasma():
    t = t_arr(0.55)
    f = 140 + 420 * np.exp(-t * 7) + 30 * np.sin(2 * np.pi * 22 * t)
    ph = np.cumsum(f) / SR
    s = osc(SAW_BRIGHT, f, len(t)) * 0.6 + np.sin(2 * np.pi * ph * 0.5) * 0.6
    s *= np.exp(-t * 5.5)
    s += fft_filter(rng.normal(0, 1, len(t)), lo=2000) * np.exp(-t * 30) * 0.3
    return norm(fft_filter(s, hi=5000), 0.8)


def sfx_hit():
    t = t_arr(0.09)
    s = fft_filter(rng.normal(0, 1, len(t)), lo=1200, hi=8000) * np.exp(-t * 45)
    s += np.sin(2 * np.pi * 900 * t * (1 - t * 4)) * np.exp(-t * 60) * 0.5
    return norm(s, 0.55)


def sfx_crunch():
    t = t_arr(0.28)
    s = rng.normal(0, 1, len(t))
    s = one_pole_lp(s, 400 + 2600 * np.exp(-t * 16))
    s = np.round(norm(s) * 6) / 6  # bitcrush
    s += np.sin(2 * np.pi * 70 * t) * np.exp(-t * 18) * 0.7
    return norm(s * np.exp(-t * 11), 0.75)


def sfx_explosion(dur, low, bright):
    t = t_arr(dur)
    s = rng.normal(0, 1, len(t))
    cutoff = 150 + bright * np.exp(-t * 6 / dur)
    s = one_pole_lp(one_pole_lp(s, cutoff), cutoff)
    env = np.exp(-t * 4.0 / dur) * np.clip(t * 400, 0, 1)
    thump = np.sin(2 * np.pi * np.cumsum(low + 60 * np.exp(-t * 20)) / SR) * np.exp(-t * 6 / dur)
    crackle = (rng.random(len(t)) > 0.995) * rng.normal(0, 1, len(t)) * np.exp(-t * 3 / dur)
    out = norm(s) * env + thump * 0.7 + crackle * 0.4
    return norm(out, 0.9)


def sfx_hurt():
    t = t_arr(0.35)
    f = 320 * np.exp(-t * 3)
    s = osc(SQUARE, f, len(t)) * 0.6 + rng.normal(0, 1, len(t)) * 0.25
    return norm(s * np.exp(-t * 8), 0.7)


def sfx_respawn():
    out = np.zeros(int(0.9 * SR))
    for i, m in enumerate([62, 69, 74, 81]):
        n = pluck(m + 12, 0.15, SOFT, decay=0.25)
        st = int(i * 0.09 * SR)
        e = min(len(out), st + len(n))
        out[st:e] += n[:e - st]
    return norm(out, 0.6)


def sfx_thrust():
    """Seamless loop: spectral-shaped noise synthesized with random phases (periodic)."""
    n = SR * 2
    f = np.fft.rfftfreq(n, 1 / SR)
    mag = 1 / (1 + (f / 180) ** 1.6) + 0.25 / (1 + ((f - 900) / 500) ** 2)
    mag[0] = 0
    ph = rng.uniform(0, 2 * np.pi, len(f))
    s = np.fft.irfft(mag * np.exp(1j * ph), n=n)
    t = np.arange(n) / SR
    s *= 1 + 0.15 * np.sin(2 * np.pi * 6 * t)  # 6Hz flutter, integer cycles → seamless
    return norm(s, 0.7)


def sfx_alarm():
    """Soft two-tone chime, played twice. Informative, not a siren."""
    out = np.zeros(int(1.9 * SR))
    for i, (m1, m2) in enumerate([(81, 76), (81, 76)]):
        for j, m in enumerate((m1, m2)):
            t = t_arr(0.5)
            f = mtof(m)
            tone = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 8)
            env = np.clip(t * 60, 0, 1) * np.exp(-t * 5)
            st = int((i * 0.9 + j * 0.22) * SR)
            out[st:st + len(t)] += tone * env
    return norm(out, 0.45)


def sfx_pickup():
    t = t_arr(0.12)
    f = 1400 + 900 * t / 0.12
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 30)
    return norm(s, 0.4)


def sfx_missile():
    t = t_arr(0.7)
    noise = rng.normal(0, 1, len(t))
    s = one_pole_lp(noise, 800 + 3000 * np.exp(-t * 4))
    s = norm(s) * np.clip(t * 30, 0, 1) * np.exp(-t * 3.5)
    s += np.sin(2 * np.pi * np.cumsum(200 + 300 * t) / SR) * np.exp(-t * 8) * 0.3
    return norm(s, 0.6)


def sfx_buy():
    out = np.zeros(int(0.5 * SR))
    for i, m in enumerate([72, 76, 79, 84]):
        n = pluck(m, 0.08, SOFT, decay=0.12)
        st = int(i * 0.06 * SR)
        e = min(len(out), st + len(n))
        out[st:e] += n[:e - st]
    return norm(out, 0.5)


def sfx_error():
    t = t_arr(0.22)
    s = osc(SQUARE, 110, len(t)) * 0.6 + osc(SQUARE, 116, len(t)) * 0.4
    return norm(fft_filter(s * np.exp(-t * 9), hi=2000), 0.45)


def sfx_click():
    t = t_arr(0.04)
    return norm(np.sin(2 * np.pi * 1800 * t) * np.exp(-t * 120), 0.35)


def build_sfx():
    write_wav("laser.wav", sfx_laser())
    write_wav("plasma.wav", sfx_plasma())
    write_wav("hit.wav", sfx_hit())
    write_wav("crunch.wav", sfx_crunch())
    write_wav("explode_small.wav", sfx_explosion(0.55, 70, 2500))
    write_wav("explode_big.wav", sfx_explosion(1.4, 45, 1800))
    write_wav("explode_planet.wav", sfx_explosion(3.5, 30, 1200))
    write_wav("hurt.wav", sfx_hurt())
    write_wav("respawn.wav", sfx_respawn())
    write_wav("thrust.wav", sfx_thrust())
    write_wav("alarm.wav", sfx_alarm())
    write_wav("pickup.wav", sfx_pickup())
    write_wav("missile.wav", sfx_missile())
    write_wav("buy.wav", sfx_buy())
    write_wav("error.wav", sfx_error())
    write_wav("click.wav", sfx_click())


if __name__ == "__main__":
    import sys
    build_sfx()
    if "--sfx-only" not in sys.argv:
        build_music()
    print("done")
