#!/usr/bin/env python3
"""N63KA valve watch: looks for the early exhaust-valve signature in Perspective engine logs.

Signature (published by Savvy Aviation for FEVA, AOPA Aug 2014): a slow, rhythmic EGT oscillation on ONE
cylinder, roughly one cycle per minute, 30-100 F peak to peak, while the engine is in steady cruise. A valve
that is not seating fully leaks a little hot exhaust, the valve rotator turns it, the leak comes and goes, and
the EGT of that cylinder swings slowly. Our version is built from that description, not Savvy's model.

Method (pure standard library, so it runs on any Python 3):
  1. Find steady cruise windows of 8 minutes (RPM within 60, fuel flow within 1.5 gph, MAP within 1.5 inHg,
     every cylinder's EGT present, no 1-second EGT jump over 100 F, which is a probe glitch, not a valve).
  2. For each cylinder, subtract the median of the other five cylinders. Power, mixture and altitude changes
     move every cylinder together, so they cancel; a single cylinder's own swing stays.
  3. Remove the straight-line drift and measure the strongest repeating cycle with a period of 40-100 s
     (Fourier transform of that band only). Report its peak-to-peak size and how much of the cylinder's
     wobble it explains (periodicity).
  4. A window counts as a hit for a cylinder when the cycle is at least 30 F peak to peak, explains at least
     35% of the wobble, and is at least twice the size of the same measure on the other cylinders.
  5. A flight is flagged for a cylinder when hits make up at least 25% of its steady windows (min 2 windows).
     Across flights, a cylinder flagged on 2 or more of its last 5 flights with steady cruise is REPEATING.

Usage:
  python3 n63ka_valves.py LOG.csv [LOG2.csv ...] [--history valve-history.json] [--update] [--json]
Advisory only: a flag means "ask the A&P to borescope this cylinder", never a diagnosis.
"""
import argparse, cmath, json, math, os, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load, num, phases  # noqa: E402

CYL = range(1, 7)
WINDOW_S = 480          # 8-minute analysis window (needs at least ~5 cycles at the slowest period)
STEP_S = 120            # windows overlap; step 2 minutes
PERIOD_S = (40, 100)    # about one cycle per minute
MAX_RPM_RANGE, MAX_FF_RANGE, MAX_MAP_RANGE = 60, 1.5, 1.5
MAX_JUMP_F = 100        # a lone EGT sample this far from its neighbours is a probe/wiring spike, not a valve
MAX_SPIKES = 5          # more spikes than this in a window: the probe is too noisy to judge that window
MIN_P2P_F = 30          # published lower bound of the signature
MIN_PERIODICITY = 0.35  # share of the cylinder's detrended variance explained by the band peak
MIN_DOMINANCE = 2.0     # this cylinder's cycle vs the median of the other cylinders' cycles
FLIGHT_SHARE, FLIGHT_MIN_HITS = 0.25, 2
MIN_CRUISE_SHARE = 0.8  # share of the window classified as cruise
REPEAT_OF, REPEAT_MIN = 5, 2


def series(rows, col):
    return [num(r.get(col)) for r in rows]


def steady_windows(rows, ph):
    """Yield (start, end) index pairs of steady-cruise windows."""
    rpm, ff, mp = series(rows, "E1 RPM"), series(rows, "E1 FFlow"), series(rows, "E1 MAP")
    egt = {c: series(rows, f"E1 EGT{c}") for c in CYL}
    n, i = len(rows), 0
    while i + WINDOW_S <= n:
        j = i + WINDOW_S
        if _level_enough(ph[i:j]) and _steady(rpm[i:j], MAX_RPM_RANGE) and _steady(ff[i:j], MAX_FF_RANGE) \
                and _steady(mp[i:j], MAX_MAP_RANGE) and all(_clean(egt[c][i:j]) for c in CYL):
            yield i, j
            i += STEP_S
        else:
            i += 30
    return


def _level_enough(ph):
    """Airborne the whole window and mostly level: brief climbs/descents (step climbs, turbulence) are fine
    because power must still be steady and altitude changes move every cylinder's EGT together."""
    return all(p in ("cruise", "climb", "descent") for p in ph) and ph.count("cruise") >= MIN_CRUISE_SHARE * len(ph)


def _steady(v, rng):
    v = [x for x in v if x is not None]
    return len(v) >= 0.95 * WINDOW_S and max(v) - min(v) <= rng


def _clean(v):
    """Usable EGT trace: no gaps, and probe spikes (single samples far from their neighbours) are rare."""
    if any(x is None for x in v):
        return False
    return sum(1 for k in spikes(v)) <= MAX_SPIKES


def spikes(v):
    """Indexes of probe/wiring spikes: a sample more than MAX_JUMP_F from the median of its +-3 s neighbours."""
    for k in range(len(v)):
        nb = [v[m] for m in range(max(0, k - 3), min(len(v), k + 4)) if m != k and v[m] is not None]
        if v[k] is not None and nb and abs(v[k] - statistics.median(nb)) > MAX_JUMP_F:
            yield k


def despike(v):
    v = list(v)
    for k in list(spikes(v)):
        nb = [v[m] for m in range(max(0, k - 3), min(len(v), k + 4)) if m != k]
        v[k] = statistics.median(nb)
    return v


def detrend(v):
    n = len(v); xm = (n - 1) / 2; ym = sum(v) / n
    sxx = sum((k - xm) ** 2 for k in range(n)) or 1
    b = sum((k - xm) * (y - ym) for k, y in enumerate(v)) / sxx
    return [y - (ym + b * (k - xm)) for k, y in enumerate(v)]


def band_cycle(v):
    """Strongest cycle with a period in PERIOD_S: (peak-to-peak F, period s, share of variance)."""
    n = len(v); var = sum(x * x for x in v) / n
    if var <= 0:
        return 0.0, None, 0.0
    best = (0.0, None)
    kmin, kmax = math.ceil(n / PERIOD_S[1]), math.floor(n / PERIOD_S[0])
    for q in range(4 * kmin, 4 * kmax + 1):
        k = q / 4
        z = sum(x * cmath.exp(-2j * math.pi * k * t / n) for t, x in enumerate(v))
        amp = 2 * abs(z) / n                      # sine amplitude
        if amp > best[0]:
            best = (amp, n / k)
    amp, period = best
    share = (amp * amp / 2) / var                 # variance explained by that sine
    return 2 * amp, period, min(share, 1.0)


def analyse_window(rows, i, j):
    egt = {c: despike(num(rows[t].get(f"E1 EGT{c}")) for t in range(i, j)) for c in CYL}
    raw, out = {}, {}
    for c in CYL:
        others = [statistics.median(egt[o][t] for o in CYL if o != c) for t in range(j - i)]
        own = detrend([egt[c][t] - others[t] for t in range(j - i)])
        raw[c] = band_cycle(own)
    for c in CYL:
        p2p, period, share = raw[c]
        rest = statistics.median(raw[o][0] for o in CYL if o != c) or 0.1
        hit = p2p >= MIN_P2P_F and share >= MIN_PERIODICITY and p2p / rest >= MIN_DOMINANCE
        out[c] = {"p2p": round(p2p, 1), "period": round(period, 1) if period else None, "periodicity": round(share, 2),
                  "dominance": round(p2p / rest, 1), "hit": hit}
    return out


def analyse_flight(path):
    rows = load(path)
    name = os.path.basename(path)
    if len(rows) < WINDOW_S or not any(f"E1 EGT{c}" in rows[0] for c in CYL):
        return {"file": name, "date": rows[0]["_t"].isoformat() if rows else None, "steadyWindows": 0, "cylinders": {}}
    ph = phases(rows)
    wins = list(steady_windows(rows, ph))
    per = {c: [] for c in CYL}
    for i, j in wins:
        res = analyse_window(rows, i, j)
        for c in CYL:
            per[c].append(dict(res[c], start=rows[i]["_t"].strftime("%H:%M")))
    cyl = {}
    for c in CYL:
        hits = [w for w in per[c] if w["hit"]]
        flagged = len(hits) >= FLIGHT_MIN_HITS and len(wins) and len(hits) / len(wins) >= FLIGHT_SHARE
        top = max(per[c], key=lambda w: w["p2p"], default=None)
        cyl[str(c)] = {"flagged": bool(flagged), "hitWindows": len(hits),
                       "largestCycleF": top["p2p"] if top else None, "periodS": top["period"] if top else None,
                       "periodicity": top["periodicity"] if top else None, "dominance": top["dominance"] if top else None,
                       "hitTimes": [w["start"] for w in hits][:10]}
    return {"file": name, "date": rows[0]["_t"].isoformat(), "steadyWindows": len(wins), "cylinders": cyl}


def update_history(hist, flight):
    flights = [f for f in hist.get("flights", []) if f["file"] != flight["file"]]
    flights.append({"file": flight["file"], "date": flight["date"], "steadyWindows": flight["steadyWindows"],
                    "flagged": [c for c, v in flight["cylinders"].items() if v["flagged"]],
                    "largest": {c: v["largestCycleF"] for c, v in flight["cylinders"].items()}})
    flights.sort(key=lambda f: f["date"] or "")
    return {"flights": flights}


def repeating(hist):
    usable = [f for f in hist.get("flights", []) if f["steadyWindows"] > 0][-REPEAT_OF:]
    out = {}
    for c in map(str, CYL):
        n = sum(1 for f in usable if c in f["flagged"])
        if n >= REPEAT_MIN:
            out[c] = n
    return out, len(usable)


def describe(flight, rep, considered):
    lines = [f"{flight['file']}: {flight['steadyWindows']} steady cruise windows (8 min each)"]
    if not flight["steadyWindows"]:
        lines.append("  No steady cruise long enough to check the valves.")
    for c, v in flight["cylinders"].items():
        if v["flagged"]:
            lines.append(f"  CYL {c} WATCH: EGT cycling {v['largestCycleF']:.0f} F peak to peak about every "
                         f"{v['periodS']:.0f} s, on its own ({v['dominance']}x the other cylinders), in {v['hitWindows']} "
                         f"of {flight['steadyWindows']} windows (from {', '.join(v['hitTimes'][:4])}).")
    if flight["steadyWindows"] and not any(v["flagged"] for v in flight["cylinders"].values()):
        biggest = max(flight["cylinders"].items(), key=lambda kv: kv[1]["largestCycleF"] or 0)
        lines.append(f"  No valve signature. Largest single-cylinder cycle: CYL {biggest[0]} {biggest[1]['largestCycleF']:.0f} F.")
    for c, n in rep.items():
        lines.append(f"  CYL {c} REPEATING: signature on {n} of the last {considered} flights with steady cruise. "
                     f"Ask the A&P to borescope cylinder {c} (exhaust valve face and seat).")
    return "\n".join(lines)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--history", help="valve-history.json (per-flight results, for the repeat check)")
    ap.add_argument("--update", action="store_true", help="write the flights into --history")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    hist = json.load(open(a.history)) if a.history and os.path.exists(a.history) else {"flights": []}
    results = []
    for p in a.logs:
        f = analyse_flight(p)
        hist = update_history(hist, f)
        rep, considered = repeating(hist)
        results.append({"flight": f, "repeating": rep})
        if not a.json:
            print(describe(f, rep, considered))
    if a.json:
        print(json.dumps(results, indent=1))
    if a.update and a.history:
        json.dump(hist, open(a.history, "w"), indent=1)
