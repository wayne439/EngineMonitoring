#!/usr/bin/env python3
"""N63KA GAMI spread from leaning recorded in Perspective logs.

A GAMI lean test leans the mixture slowly at constant RPM and manifold pressure until every cylinder passes its peak
EGT; the fuel flow at which each cylinder peaks shows how evenly the injectors feed the cylinders. GAMI spread =
richest-peaking cylinder's fuel flow minus leanest-peaking cylinder's fuel flow. GAMI's guidance: 0.5 gph or less is
well balanced (smooth lean-of-peak operation); about 1.0 gph or more means mismatched injectors.

Finds airborne stretches where RPM (within 40) and MAP (within 1.0 inHg) hold steady while fuel flow (5 s median)
falls by at least 1.5 gph at no more than 0.15 gph per second (slow enough for 1 s EGT data), then for each cylinder
the fuel flow at its peak EGT (5 s median) - only when the EGT rose at least 10 F before and fell at least 10 F after
the peak inside the sweep. Needs 4 or more cylinders peaking. Leaning quickly at level-off rarely qualifies; the
in-app guided test (lean about 1 gph per 10 s from 50 F rich of peak to 50 F lean of peak) gives a clean result.

Usage: python3 n63ka_gami.py LOG.csv [...] [--json]
"""
import argparse, json, os, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load, num, phases  # noqa: E402

MIN_DROP, MAX_RATE, MIN_PEAK_SIDE, MIN_CYL = 1.5, 0.15, 10, 4
LOCAL, MAX_LOCAL_RATE = 8, 0.1
FIT_WITHIN = 25  # F below the highest EGT used for the parabola fit   # fuel flow within +-8 s of each peak must move no faster than 0.1 gph/s


def smooth(v, h=2):
    out = []
    for k in range(len(v)):
        w = [x for x in v[max(0, k - h):k + h + 1] if x is not None]
        out.append(statistics.median(w) if w else None)
    return out


def vertex(f, e, p, within=FIT_WITHIN):
    """Fuel flow at the top of a parabola fitted to EGT vs fuel flow, using the samples within FIT_WITHIN F of the
    highest EGT. 1 Hz EGT has a flat, noisy top, so the single highest sample wanders; the fit does not."""
    pts = [(f[i], e[i]) for i in range(len(e)) if f[i] is not None and e[i] is not None and e[p] - e[i] <= within]
    if len(pts) >= 5:
        xm = sum(x for x, _ in pts) / len(pts)
        A = [[0.0] * 3 for _ in range(3)]; B = [0.0] * 3
        for x, y in pts:
            v = [1.0, x - xm, (x - xm) ** 2]
            for r in range(3):
                B[r] += v[r] * y
                for c in range(3): A[r][c] += v[r] * v[c]
        try:
            a0, a1, a2 = solve3(A, B)
            if a2 < 0:
                x = xm - a1 / (2 * a2)
                if min(x for x, _ in pts) <= x <= max(x for x, _ in pts): return x
        except ZeroDivisionError:
            pass
    return f[p]


def solve3(A, B):
    M = [A[r][:] + [B[r]] for r in range(3)]
    for c in range(3):
        piv = max(range(c, 3), key=lambda r: abs(M[r][c]))
        if abs(M[piv][c]) < 1e-12: raise ZeroDivisionError
        M[c], M[piv] = M[piv], M[c]
        for r in range(3):
            if r != c:
                k = M[r][c] / M[c][c]
                M[r] = [M[r][i] - k * M[c][i] for i in range(4)]
    return [M[r][3] / M[r][r] for r in range(3)]


def sweeps(rows, ph):
    n = len(rows)
    rpm = [num(r.get("E1 RPM")) for r in rows]; mp = [num(r.get("E1 MAP")) for r in rows]
    ff = smooth([num(r.get("E1 FFlow")) for r in rows])
    out, k = [], 0
    while k < n - 30:
        if ph[k] not in ("climb", "cruise", "descent") or ff[k] is None:
            k += 1; continue
        j = k + 1
        # extend while steady RPM/MAP and fuel flow not rising by more than 0.2 gph
        while j < n and ph[j] in ("climb", "cruise", "descent") and ff[j] is not None and ff[j] <= ff[j - 1] + 0.05:
            w_r = [x for x in rpm[k:j + 1] if x]; w_m = [x for x in mp[k:j + 1] if x]
            if not w_r or not w_m or max(w_r) - min(w_r) > 40 or max(w_m) - min(w_m) > 1.0: break
            j += 1
        drop = ff[k] - ff[j - 1] if ff[j - 1] is not None else 0
        if drop >= MIN_DROP and j - k >= 15 and drop / (j - k) <= MAX_RATE:
            out.append((k, j)); k = j
        else:
            k += 1
    return out


def analyse(path):
    rows = load(path)
    res = {"file": os.path.basename(path), "tests": []}
    if len(rows) < 300: return res
    ph = phases(rows)
    ff = smooth([num(r.get("E1 FFlow")) for r in rows])
    raw = [[num(r.get(f"E1 EGT{c}")) for r in rows] for c in range(1, 7)]
    egt = [smooth(v) for v in raw]
    for k, j in sweeps(rows, ph):
        peaks = {}
        for c in range(6):
            seg = egt[c][k:j]
            if any(x is None for x in seg): continue
            p = max(range(len(seg)), key=lambda i: seg[i]); a = k + p
            # the peak must be caused by leaning: fuel flow moving slowly through it, and the EGT 10 F below the
            # peak on each side at a fuel flow at least 0.2 gph richer (before) and leaner (after)
            if a - LOCAL < 0 or a + LOCAL >= len(ff) or ff[a - LOCAL] is None or ff[a + LOCAL] is None: continue
            if (ff[a - LOCAL] - ff[a + LOCAL]) / (2 * LOCAL) > MAX_LOCAL_RATE: continue
            before = [i for i in range(p) if seg[p] - seg[i] >= MIN_PEAK_SIDE]
            after = [i for i in range(p + 1, len(seg)) if seg[p] - seg[i] >= MIN_PEAK_SIDE]
            if not before or not after: continue
            if ff[k + before[-1]] - ff[a] < 0.2 or ff[a] - ff[k + after[0]] < 0.2: continue
            peaks[c + 1] = {"ff": round(vertex(ff[k:j], egt[c][k:j], p), 2), "egt": round(seg[p]), "t": a}
        if len(set(v["t"] for v in peaks.values())) == 1 and len(peaks) > 1: continue
        if len(peaks) >= MIN_CYL:
            fl = {c: v["ff"] for c, v in peaks.items()}
            rich = max(fl, key=fl.get); lean = min(fl, key=fl.get)
            res["tests"].append({"time": rows[k]["Lcl Time"], "i": k, "seconds": j - k, "ffStart": round(ff[k], 1), "ffEnd": round(ff[j - 1], 1),
                                 "peaks": {c: {"ff": v["ff"], "egt": v["egt"]} for c, v in peaks.items()}, "spread": round(fl[rich] - fl[lean], 2), "richest": rich, "leanest": lean,
                                 "cylindersPeaked": len(peaks)})
    return res


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("logs", nargs="+"); ap.add_argument("--json", action="store_true"); a = ap.parse_args()
    out = [analyse(p) for p in a.logs]
    if a.json: print(json.dumps(out, indent=1))
    else:
        for r in out:
            for t in r["tests"]:
                print(r["file"], t["time"], f'{t["ffStart"]}->{t["ffEnd"]} gph in {t["seconds"]} s', "spread", t["spread"], "gph, richest cyl", t["richest"], "leanest", t["leanest"], {c: v["ff"] for c, v in t["peaks"].items()})
