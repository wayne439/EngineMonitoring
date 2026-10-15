#!/usr/bin/env python3
"""N63KA probe and wiring check: finds sensor faults in Perspective engine logs so they are not mistaken for engine
problems (and so a failing probe or connector is caught early).

Looks at every EGT, CHT, TIT, oil temperature and oil pressure channel while the engine runs. Readings are judged
against the other cylinders where possible (EGT vs the other EGTs, CHT vs the other CHTs, TIT1 vs TIT2), because a
real engine change moves the group together while a probe fault moves one channel alone.

Faults:
  dropout  - blank readings in the middle of the log while the engine runs (the last 3 s of a log are ignored:
             the Perspective often writes a partial last row when the card or power is removed).
  spike    - airborne, a single reading sticking out on the same side of its neighbours before and after (relative to the group): EGT/TIT 100 F, CHT 40 F, oil temp 20 F,
             oil pressure 25 psi (oil pressure and oil temperature have no group, so their own neighbours are used).
  step     - in steady cruise (power steady +-30 s), the channel alone jumps relative to its group and stays there
             (loose connector, failing junction): 10-s medians before/after differ by EGT/TIT 150 F, CHT 50 F, and no
             other channel stepped within 30 s.
  flatline - the exact same value for 60 s or more with the engine running while the other channels of its group
             move (these channels normally vary in the decimals every second): a frozen or disconnected input.
             (Oil temperature and pressure have no group and are not checked for flatlines.)
  off-scale- airborne reading outside what a working probe shows (EGT/TIT below 300 F or above 1,900 F; CHT below
             80 F or above 600 F; oil temp below 50 F or above 300 F; oil pressure below 0 or above 120 psi).
  apart    - in steady cruise for 60 s or more far from its group (EGT 400 F, CHT 120 F from the other cylinders' median;
             TIT1 vs TIT2 300 F): a dead or badly reading probe.

A channel is listed for a flight when it has a dropout, flatline, off-scale, apart or step, or 3 or more spikes.
Recorded values only: "check the probe, its clamp, connector and wiring", never an engine diagnosis.

Usage: python3 n63ka_probes.py LOG.csv [LOG2.csv ...] [--json]
"""
import argparse, json, os, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load, num, phases  # noqa: E402

EGT = [f"E1 EGT{i}" for i in range(1, 7)]
CHT = [f"E1 CHT{i}" for i in range(1, 7)]
TIT = ["E1 TIT1", "E1 TIT2"]
OTHER = ["E1 OilT", "E1 OilP"]
SPIKE = {"EGT": 100, "CHT": 40, "TIT": 100, "E1 OilT": 20, "E1 OilP": 25}
STEP = {"EGT": 150, "CHT": 50, "TIT": 150}
APART = {"EGT": 400, "CHT": 120, "TIT": 300}
SCALE = {"EGT": (300, 1900), "CHT": (80, 600), "TIT": (300, 1900), "E1 OilT": (50, 300), "E1 OilP": (0, 120)}
TAIL = 3
FLAT_S = 60
FLAT_MOVE = 5  # F the other channels of the group must move during a flatline
APART_S = 60
MIN_SPIKES = 3
AIR = ("climb", "cruise", "descent")


def group_of(ch):
    if ch in EGT: return "EGT", EGT
    if ch in CHT: return "CHT", CHT
    if ch in TIT: return "TIT", TIT
    return ch, None


def steady_mask(rows, ph, half=30):
    """True where the engine is in cruise with steady power for +-30 s (RPM 60, fuel flow 1.5 gph, MAP 1.5 inHg)."""
    n = len(rows)
    rpm = [num(r.get("E1 RPM")) for r in rows]; ff = [num(r.get("E1 FFlow")) for r in rows]; mp = [num(r.get("E1 MAP")) for r in rows]
    out = [False] * n
    for k in range(half, n - half):
        if ph[k] != "cruise": continue
        ok = True
        for v, lim in ((rpm, 60), (ff, 1.5), (mp, 1.5)):
            w = [x for x in v[k - half:k + half + 1] if x is not None]
            if len(w) < 2 * half or max(w) - min(w) > lim: ok = False; break
        out[k] = ok
    return out


def _range(v):
    v = [x for x in v if x is not None]
    return max(v) - min(v) if v else 0


def med(v):
    v = [x for x in v if x is not None]
    return statistics.median(v) if v else None


def analyse(path):
    rows = load(path)
    name = os.path.basename(path)
    out = {"file": name, "date": rows[0]["_t"].isoformat() if rows else None, "channels": {}, "checkedChannels": 0}
    if len(rows) < 120:
        return out
    ph = phases(rows)
    n = len(rows) - TAIL
    running = [(num(r.get("E1 RPM")) or 0) >= 500 for r in rows]
    t = [r["_t"].strftime("%H:%M:%S") for r in rows]
    data = {ch: [num(r.get(ch)) for r in rows] for ch in EGT + CHT + TIT + OTHER}
    steady = steady_mask(rows, ph)
    step_at = {}  # channel -> sample indexes of candidate steps (to drop steps shared by several channels)
    for ch, v in data.items():
        if not any(x is not None for x in v[:n]):
            continue  # channel not recorded in this log
        out["checkedChannels"] += 1
        kind, group = group_of(ch)
        others = [o for o in (group or []) if o != ch and any(x is not None for x in data[o][:n])]
        # residual against the group (the group median of the OTHER channels), or the raw value
        if others:
            ref = [med([data[o][k] for o in others]) for k in range(len(rows))]
            res = [v[k] - ref[k] if v[k] is not None and ref[k] is not None else None for k in range(len(rows))]
        else:
            res = list(v)
        f = {}
        # dropouts
        k = 0; drops = []
        while k < n:
            if running[k] and v[k] is None and k > 0 and any(x is not None for x in v[:k]):
                j = k
                while j < n and v[j] is None: j += 1
                if j < n: drops.append((t[k], j - k))
                k = j
            else:
                k += 1
        if drops: f["dropout"] = {"count": len(drops), "seconds": sum(d for _, d in drops), "first": drops[0][0]}
        # spikes (on the residual)
        thr = SPIKE.get(kind, SPIKE.get(ch))
        sp = []
        for k in range(3, n - 3):
            if ph[k] not in AIR or res[k] is None: continue
            left = [res[m] for m in range(k - 3, k) if res[m] is not None]
            right = [res[m] for m in range(k + 1, k + 4) if res[m] is not None]
            # far from BOTH sides: a lone reading, not the edge of a real change
            if len(left) >= 2 and len(right) >= 2:
                dl, dr = res[k] - statistics.median(left), res[k] - statistics.median(right)
            else:
                continue
            # sticks out on the SAME side of both neighbours (a ramp or real change does not)
            if dl * dr > 0 and abs(dl) > thr and abs(dr) > thr:
                sp.append((t[k], round(v[k], 1)))
        if len(sp) >= MIN_SPIKES: f["spike"] = {"count": len(sp), "first": sp[0][0], "examples": sp[:3]}
        # steps (group channels only, airborne)
        if others:
            st = []
            k = 10
            while k < n - 10:
                if steady[k]:
                    a = med(res[k - 10:k]); b = med(res[k:k + 10])
                    if a is not None and b is not None and abs(b - a) > STEP[kind]:
                        st.append((k, t[k], round(b - a))); k += 60; continue
                k += 1
            if st: step_at[ch] = st
        # flatline: identical readings while the other channels of the group are moving
        if others:
            best = cur = 1; at = None; start = 0
            for k in range(1, n):
                if running[k] and v[k] is not None and v[k] == v[k - 1]:
                    cur += 1
                    if cur == 2: start = k - 1
                    if cur > best:
                        moving = any(_range([data[o][m] for m in range(start, k + 1)]) >= FLAT_MOVE for o in others)
                        if moving: best = cur; at = t[start]
                else:
                    cur = 1
            if best >= FLAT_S: f["flatline"] = {"seconds": best, "from": at}
        # off-scale, airborne
        lo, hi = SCALE.get(kind, SCALE.get(ch))
        bad = [k for k in range(n) if ph[k] in AIR and v[k] is not None and not lo <= v[k] <= hi]
        if bad: f["off-scale"] = {"seconds": len(bad), "first": t[bad[0]], "value": round(v[bad[0]], 1)}
        # apart from the group, airborne, sustained
        if others:
            run = best_run = 0; first = None
            for k in range(n):
                if steady[k] and res[k] is not None and abs(res[k]) > APART[kind]:
                    run += 1
                    if run > best_run: best_run = run; first = t[k - run + 1]
                else:
                    run = 0
            if best_run >= APART_S: f["apart"] = {"seconds": best_run, "from": first}
        if f:
            out["channels"][ch] = f
    # a step is a probe fault only if no other channel of any group stepped within 30 s (else the engine changed)
    for ch, st in step_at.items():
        own = [x for x in st if not any(abs(x[0] - y[0]) <= 30 for o, sy in step_at.items() if o != ch for y in sy)]
        if own:
            out["channels"].setdefault(ch, {})["step"] = {"count": len(own), "first": own[0][1], "size": own[0][2]}
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("logs", nargs="+"); ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    res = [analyse(p) for p in a.logs]
    if a.json:
        print(json.dumps(res, indent=1))
    else:
        for r in res:
            if r["channels"]:
                print(r["file"])
                for ch, f in r["channels"].items():
                    print("  ", ch, json.dumps(f))
