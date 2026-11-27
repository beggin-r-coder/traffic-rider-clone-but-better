#!/usr/bin/env python3
"""Build a game engine-sound bank from a real recording of a motorcycle being ridden.

  python3 tools/build_engine_bank.py recording.wav assets/audio/engine_real [--cyl 4]

1. Tracks the engine firing frequency over time (harmonic-sum pitch tracking + a smoothness
   constraint), giving RPM(t).  Inline-4: firing frequency = rpm / 30.
2. For each target RPM, finds stretches of the recording near that RPM — on-throttle (loud,
   RPM steady or rising) and off-throttle (RPM falling) — and *time-warps* them so the engine
   note sits exactly on the target RPM, then makes a seamless crossfaded loop.
3. Detects exhaust pops/backfires (sharp broadband transients during deceleration) and cuts
   them out as one-shots.
Writes on_XXXXX.wav, off_XXXXX.wav, pop_N.wav and bank.json (44.1 kHz mono 16-bit).
"""
import json, os, sys
import numpy as np
import scipy.io.wavfile as wf
import scipy.signal as sg

SR = 44100
LOOP_SEC = 0.9
FADE_SEC = 0.12
ON_RPMS = [1500, 2200, 3000, 3800, 4600, 5500, 6500, 7500, 8500, 9500]
OFF_RPMS = [2000, 3200, 4500, 6000, 7500, 9000]


def load(path):
    sr, x = wf.read(path)
    x = x.astype(np.float32)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x /= np.abs(x).max() + 1e-9
    if sr != SR:
        x = sg.resample_poly(x, SR, sr).astype(np.float32)
    return x


def track_rpm(x, cyl):
    win, hop = 8192, 1024
    f, t, Z = sg.stft(x, SR, nperseg=win, noverlap=win - hop)
    mag = np.abs(Z)
    S = np.log1p(mag * 50)
    cands = np.arange(25.0, 520.0, 1.0)
    idx = lambda fr: np.clip(np.round(fr / (SR / win)).astype(int), 0, S.shape[0] - 1)
    H = np.zeros((len(cands), S.shape[1]), dtype=np.float32)
    for h in range(1, 8):
        H += S[idx(cands * h), :] / h ** 0.3
    nC, nT = H.shape
    ci = np.arange(nC)
    score = H[:, 0].copy()
    back = np.zeros((nT, nC), dtype=np.int32)
    for k in range(1, nT):
        best = np.full(nC, -1e9, dtype=np.float32)
        arg = np.zeros(nC, dtype=np.int32)
        for d in range(-30, 31):
            src = np.clip(ci - d, 0, nC - 1)
            v = score[src] - max(0, abs(d) - 8) * 0.6 - 0.02 * abs(d)
            m = v > best
            best[m] = v[m]
            arg[m] = src[m]
        score = best + H[:, k]
        back[k] = arg
    path = np.zeros(nT, dtype=np.int32)
    path[-1] = int(np.argmax(score))
    for k in range(nT - 1, 0, -1):
        path[k - 1] = back[k, path[k]]
    fire = cands[path]
    rpm = fire * 120.0 / cyl
    clarity = H[path, np.arange(nT)]
    energy = np.sqrt((mag ** 2).mean(axis=0))
    return t, sg.medfilt(rpm, 5), clarity, energy


def warp_to_rpm(x, t, rpm, t0, target, n_out):
    """Resample x starting at t0 so that the (time-varying) engine note plays at `target` rpm."""
    out = np.zeros(n_out, dtype=np.float32)
    pos = t0 * SR
    for i in range(n_out):
        r = np.interp(pos / SR, t, rpm)
        pos += target / r            # read faster when the source is slower than target
        j = int(pos)
        if j + 1 >= len(x):
            return None
        a = pos - j
        out[i] = x[j] * (1 - a) + x[j + 1] * a
    return out


def make_loop(seg):
    n = len(seg)
    f = int(FADE_SEC * SR)
    body = seg[: n - f].copy()
    tail = seg[n - f:]
    w = np.sin(np.linspace(0, np.pi / 2, f)) ** 2
    body[:f] = body[:f] * w + tail * (1 - w)     # tail crossfades into the head
    return body


def pick_segment(t, rpm, clar, energy, target, mode, used):
    dt = t[1] - t[0]
    span = int(LOOP_SEC * 1.6 / dt)
    drpm = np.gradient(rpm, t)
    e_hi = np.percentile(energy, 60)
    best, best_s = None, -1e9
    for k in range(0, len(t) - span, 2):
        r = rpm[k:k + span]
        if r.min() < target * 0.72 or r.max() > target * 1.35:
            continue
        dr = drpm[k:k + span]
        if mode == 'on':
            if dr.mean() < -200 or energy[k:k + span].mean() < e_hi * 0.8:
                continue
        else:
            if dr.mean() > -250:
                continue
        if any(abs(t[k] - u) < 1.0 for u in used):
            continue
        s = clar[k:k + span].mean() - np.std(np.diff(r)) * 0.002 - abs(np.log(np.median(r) / target)) * 8
        if s > best_s:
            best, best_s = k, s
    return best


def find_pops(x, t, rpm, energy, n=10):
    # broadband transients: high-passed envelope peaks with a big crest factor
    b, a = sg.butter(4, 1500 / (SR / 2), 'high')
    hp = sg.filtfilt(b, a, x)
    env = np.abs(hp)
    env_s = sg.fftconvolve(env, np.ones(441) / 441, 'same')
    base = sg.fftconvolve(env, np.ones(SR // 2) / (SR // 2), 'same') + 1e-4
    crest = env_s / base
    peaks, props = sg.find_peaks(crest, height=3.2, distance=int(0.12 * SR))
    order = np.argsort(-props['peak_heights'])
    pops = []
    for oi in order:
        p = int(peaks[oi])
        ts = p / SR
        if np.interp(ts, t, np.gradient(rpm, t)) > 0:      # pops happen off-throttle
            continue
        a0, a1 = max(p - int(0.03 * SR), 0), min(p + int(0.22 * SR), len(x))
        seg = x[a0:a1].copy()
        seg *= np.minimum(1, np.linspace(0, 8, len(seg))) * np.exp(-np.linspace(0, 6, len(seg)))
        pops.append((float(ts), float(props['peak_heights'][oi]), seg))
        if len(pops) >= n:
            break
    return pops


def write(path, y, peak=0.9):
    y = y / (np.abs(y).max() + 1e-9) * peak
    wf.write(path, SR, (y * 32767).astype(np.int16))


def main():
    src, out = sys.argv[1], sys.argv[2]
    cyl = int(sys.argv[sys.argv.index('--cyl') + 1]) if '--cyl' in sys.argv else 4
    extra_pops = [a for a in sys.argv[3:] if a.endswith('.wav')]
    os.makedirs(out, exist_ok=True)
    x = load(src)
    t, rpm, clar, energy = track_rpm(x, cyl)
    bank = {'source': os.path.basename(src), 'on': [], 'off': [], 'pops': [], 'rpm_range': [float(rpm.min()), float(rpm.max())]}
    n_loop = int(LOOP_SEC * SR) + int(FADE_SEC * SR)
    for mode, targets in (('on', ON_RPMS), ('off', OFF_RPMS)):
        used = []
        for R in targets:
            # Above the recorded range use the highest material and pitch it up.
            look = min(R, np.percentile(rpm, 99.5) * 0.97)
            k = pick_segment(t, rpm, clar, energy, look, mode, used)
            if k is None:
                # Fall back to the highest-revving material available and pitch it up.
                hi = np.percentile(rpm, 99.0)
                k = pick_segment(t, rpm, clar, energy, hi * 0.92, mode, used)
            if k is None:
                print(f'{mode} {R}: no segment'); continue
            used.append(t[k])
            seg = warp_to_rpm(x, t, rpm, t[k], R, n_loop)
            if seg is None:
                continue
            loop = make_loop(seg)
            name = f'{mode}_{R:05d}.wav'
            write(os.path.join(out, name), loop, 0.8)
            bank[mode].append({'rpm': R, 'file': name, 'src_t': round(float(t[k]), 2)})
            print(f'{mode} {R}: from t={t[k]:.1f}s (src rpm {np.median(rpm[k:k+20]):.0f})')
    pops = find_pops(x, t, rpm, energy)
    for p_src in extra_pops:
        y = load(p_src)
        tt, rr, _, ee = track_rpm(y, cyl)
        pops += find_pops(y, tt, rr, ee, 6)
    for i, (ts, h, seg) in enumerate(sorted(pops, key=lambda p: -p[1])[:12]):
        name = f'pop_{i:02d}.wav'
        write(os.path.join(out, name), seg, 0.95)
        bank['pops'].append({'file': name, 'crest': round(h, 2)})
    json.dump(bank, open(os.path.join(out, 'bank.json'), 'w'), indent=1)
    print('pops', len(bank['pops']), 'rpm range', bank['rpm_range'])


if __name__ == '__main__':
    main()
