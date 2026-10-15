#!/usr/bin/env python3
"""N63KA early warning: looks across flights for slow changes that come BEFORE a failure, and says what may be
developing, how sure it is, and roughly how many flight hours are left before a limit at the current rate.

Single-flight checks (POH limits, valve watch, probe check) catch problems once they show. This looks for the drift
that comes first: a cylinder's CHT creeping up at the same power and outside air temperature, one EGT moving away from
the others, oil temperature rising for the weather, oil pressure sagging, the two TITs separating, a valve-watch cycle
growing, bus voltage falling.

Per flight (steady cruise only: power steady for +-30 s), it records:
  chtN      CHT of each cylinder                     egtgapN   distance of each cylinder's EGT from the six-cylinder mean
  chtspread hottest minus coolest CHT                egtspread hottest minus coolest EGT
  oilt      oil temperature                          oilp      oil pressure
  titgap    gap between TIT1 and TIT2                volt1/2   bus voltages
  cycleN    valve-watch largest single-cylinder EGT cycle (from n63ka_valves, if available)
plus the conditions it is corrected for: OAT and fuel flow.

For each metric, in flight order:
  1. Correct for conditions: fit metric ~ OAT + fuel flow on the BASELINE flights (the 40 flights before the newest 5,
     so the baseline follows seasons and technique; at least 20 needed), and work
     with the residual (what is left after weather and power).
  2. Normal spread: robust sigma (1.4826 x MAD) of the baseline residuals.
  3. SHIFT: the median of the newest 5 flights is more than 2.5 sigma from normal in the direction that matters.
  4. DRIFT: over the newest 10 flights, a Mann-Kendall trend test is significant the bad way (z > 2.75, about 1 in 300
     by chance), the Theil-Sen fitted change across those flights exceeds 1.5 sigma, and the newest 3 flights are already
     1 sigma or more from normal.
  5. HOURS LEFT: from the current level and the slope, the flight hours until the metric reaches its threshold
     (POH limit, caution value or N63KA watch value); only when the trend covers 8+ flight hours.
Levels: EARLY WARNING (shift or drift found) and ACT SOON (threshold within 10 flight hours at the current rate, or a
shift above 4 sigma). Then patterns that combine metrics name what may be developing, most likely first.

Advisory (TRAINING): an early warning means "look closer and ask the A&P", never a diagnosis, and never overrides the
POH. Thresholds and rules come from published engine-monitor practice (Savvy Aviation, Mike Busch, Barker profile) and
N63KA's own history; tune them as findings are confirmed or ruled out.

Usage:
  python3 n63ka_early_warning.py LOG.csv [...] [--metrics metrics.jsonl] [--json]
  (logs are processed in date order; per-flight metrics are cached in --metrics so later runs only add new flights)
"""
import argparse, json, os, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load, num, phases  # noqa: E402

CYL = range(1, 7)
BASELINE_MIN = 20   # flights of normal needed before judging
BASELINE_MAX = 40   # rolling: the newest 40 flights before the recent ones (follows seasons and technique)
RECENT = 5          # newest flights compared with normal
DRIFT_N = 10        # flights used for the slope
SHIFT_SIGMA, ACT_SIGMA = 2.5, 4.0
DRIFT_Z = 2.75        # Mann-Kendall trend test, one-sided (about 1 in 300 by chance per metric)
DRIFT_CHANGE = 1.5    # fitted change across the drift window, in sigma
DRIFT_RECENT = 1.0    # newest 3 flights already this far from normal, in sigma
HORIZON_H, ACT_HOURS = 25.0, 10.0
MIN_PROJECT_SPAN_H = 8.0  # only project hours-to-threshold from a trend covering 8+ flight hours
MIN_STEADY_S = 300  # a flight needs 5 min of steady cruise to give metrics

# metric -> (label, unit, bad direction: +1 high is bad / -1 low is bad / 0 either, threshold or None, threshold source)
def metric_info(m):
    if m.startswith("cht") and m[3:].isdigit():
        return (f"Cylinder {m[3:]} CHT in cruise", "F", +1, 400.0, "400 F cruise CHT (engine-monitor practice; POH caution 420 F)")
    if m.startswith("egtgap"):
        return (f"Cylinder {m[6:]} EGT distance from the other cylinders", "F", +1, None, None)
    if m.startswith("cycle"):
        return (f"Cylinder {m[5:]} valve-watch EGT cycle", "F", +1, 30.0, "30 F valve-watch threshold")
    return {
        "chtspread": ("CHT spread in cruise", "F", +1, 100.0, "100 F hottest-to-coolest CHT (engine-monitor practice)"),
        "egtspread": ("EGT spread in cruise", "F", +1, None, None),
        "oilt": ("Oil temperature in cruise", "F", +1, 240.0, "240 F POH limit"),
        "oilp": ("Oil pressure in cruise", "psi", -1, 30.0, "30 psi POH caution"),
        "titgap": ("Gap between TIT 1 and TIT 2 in cruise", "F", +1, None, None),
        "volt1": ("Bus 1 voltage in cruise", "V", -1, 24.5, "24.5 V M BUS 1 caution (POH 2-9)"),
        "volt2": ("Bus 2 voltage in cruise", "V", -1, 24.5, "24.5 V M BUS 2 caution (POH 2-9)"),
    }.get(m, (m, "", 0, None, None))


# ---------------------------------------------------------------- per-flight metrics

def steady_mask(rows, ph, half=30):
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


def med(v):
    v = [x for x in v if x is not None]
    return statistics.median(v) if v else None


def flight_metrics(path, valve=None):
    rows = load(path)
    if len(rows) < 600: return None
    ph = phases(rows)
    air = sum(1 for p in ph if p in ("climb", "cruise", "descent"))
    st = [k for k, ok in enumerate(steady_mask(rows, ph)) if ok]
    out = {"file": os.path.basename(path), "date": rows[0]["_t"].isoformat(), "airborneHours": round(air / 3600, 3),
           "steadySeconds": len(st)}
    if len(st) < MIN_STEADY_S: return out
    g = lambda ch: [num(rows[k].get(ch)) for k in st]
    out["oat"] = med(g("OAT")); out["ff"] = med(g("E1 FFlow"))
    cht = {c: g(f"E1 CHT{c}") for c in CYL}; egt = {c: g(f"E1 EGT{c}") for c in CYL}
    for c in CYL:
        out[f"cht{c}"] = med(cht[c])
    spread_c, spread_e, dev = [], [], {c: [] for c in CYL}
    for i in range(len(st)):
        cs = [cht[c][i] for c in CYL if cht[c][i] is not None]
        es = [egt[c][i] for c in CYL if egt[c][i] is not None]
        if len(cs) == 6: spread_c.append(max(cs) - min(cs))
        if len(es) == 6:
            spread_e.append(max(es) - min(es)); m = sum(es) / 6
            for c in CYL: dev[c].append(egt[c][i] - m)
    out["chtspread"] = med(spread_c); out["egtspread"] = med(spread_e)
    for c in CYL: out[f"egtdev{c}"] = med(dev[c])
    out["oilt"] = med(g("E1 OilT")); out["oilp"] = med(g("E1 OilP"))
    t1, t2 = g("E1 TIT1"), g("E1 TIT2")
    out["titdiff"] = med([a - b for a, b in zip(t1, t2) if a is not None and b is not None])
    out["volt1"] = med(g("volt1")); out["volt2"] = med(g("volt2"))
    if valve and valve.get("steadyWindows"):
        for c in CYL:
            v = valve["cylinders"].get(str(c), {}).get("largestCycleF")
            if v is not None: out[f"cycle{c}"] = v
    return {k: (round(v, 2) if isinstance(v, float) else v) for k, v in out.items()}


# ---------------------------------------------------------------- trend engine

def ols(X, y):
    """Least squares with intercept, small ridge for stability. X: list of feature lists."""
    k = len(X[0]) + 1
    A = [[1.0] + list(x) for x in X]
    ata = [[sum(A[r][i] * A[r][j] for r in range(len(A))) + (1e-6 if i == j else 0) for j in range(k)] for i in range(k)]
    aty = [sum(A[r][i] * y[r] for r in range(len(A))) for i in range(k)]
    # Gaussian elimination
    M = [row[:] + [b] for row, b in zip(ata, aty)]
    for i in range(k):
        p = max(range(i, k), key=lambda r: abs(M[r][i])); M[i], M[p] = M[p], M[i]
        if abs(M[i][i]) < 1e-12: continue
        for r in range(k):
            if r != i:
                f = M[r][i] / M[i][i]
                M[r] = [a - f * b for a, b in zip(M[r], M[i])]
    return [M[i][k] / M[i][i] if abs(M[i][i]) > 1e-12 else 0.0 for i in range(k)]


def theil_sen(xs, ys):
    s = [(ys[j] - ys[i]) / (xs[j] - xs[i]) for i in range(len(xs)) for j in range(i + 1, len(xs)) if xs[j] != xs[i]]
    if not s: return 0.0, 0.0
    slope = statistics.median(s)
    agree = sum(1 for x in s if (x > 0) == (slope > 0) and x != 0) / len(s)
    return slope, agree


def mann_kendall(ys):
    """Mann-Kendall trend statistic as a z-score (positive = rising)."""
    n = len(ys)
    s = sum((ys[j] > ys[i]) - (ys[j] < ys[i]) for i in range(n) for j in range(i + 1, n))
    var = n * (n - 1) * (2 * n + 5) / 18
    if s == 0 or var == 0: return 0.0
    return (s - 1) / var ** 0.5 if s > 0 else (s + 1) / var ** 0.5


def evaluate(metric, flights):
    """flights: chronological list of dicts with the metric, oat, ff, cumHours. Returns a finding dict or None."""
    pts = [f for f in flights if f.get(metric) is not None and f.get("oat") is not None and f.get("ff") is not None]
    if len(pts) < BASELINE_MIN + RECENT: return None
    label, unit, bad, thr, src = metric_info(metric)
    base, recent = pts[:-RECENT][-BASELINE_MAX:], pts[-RECENT:]
    corr = not metric.startswith(("cycle", "volt"))  # cycles and voltages are not weather/power dependent
    if corr:
        coef = ols([[f["oat"], f["ff"]] for f in base], [f[metric] for f in base])
        fit = lambda f: coef[0] + coef[1] * f["oat"] + coef[2] * f["ff"]
    else:
        m0 = statistics.median(f[metric] for f in base); fit = lambda f: m0
    res = lambda f: f[metric] - fit(f)
    br = [res(f) for f in base]
    centre = statistics.median(br)
    sigma = max(1.4826 * statistics.median(abs(r - centre) for r in br), {"V": 0.1, "psi": 1.0}.get(unit, 2.0))
    rr = [res(f) for f in recent]
    shift = (statistics.median(rr) - centre) / sigma
    last = pts[-DRIFT_N:]
    lr = [res(f) for f in last]
    slope, agree = theil_sen([f["cumHours"] for f in last], lr)
    z = mann_kendall(lr)
    span = last[-1]["cumHours"] - last[0]["cumHours"]
    near = (statistics.median(lr[-3:]) - centre) / sigma
    sgn = 1 if bad >= 0 else -1
    if bad == 0:  # either direction matters: judge in the direction of the change
        sgn = 1 if shift >= 0 else -1
    shift_bad, slope_bad, z_bad, near_bad = sgn * shift, sgn * slope, sgn * z, sgn * near
    findings = []
    if shift_bad > SHIFT_SIGMA:
        findings.append("shift")
    if z_bad > DRIFT_Z and slope_bad * span > DRIFT_CHANGE * sigma and near_bad > DRIFT_RECENT:
        findings.append("drift")
    if not findings: return None
    # current level in real units (newest flights, at typical conditions) and hours to the threshold
    level = statistics.median(f[metric] for f in recent)
    hours_left = None
    if thr is not None and bad != 0 and slope_bad > 0 and span >= MIN_PROJECT_SPAN_H:
        gap = (thr - level) if bad > 0 else (level - thr)
        hours_left = max(gap, 0) / slope_bad
    act = shift_bad > ACT_SIGMA or (hours_left is not None and hours_left <= ACT_HOURS)
    return {"metric": metric, "label": label, "unit": unit, "level": "ACT SOON" if act else "EARLY WARNING",
            "findings": findings, "shiftSigma": round(shift, 1), "slopePerHour": round(slope, 2), "trendZ": round(z, 1),
            "sigma": round(sigma, 2), "recentValue": round(level, 1), "threshold": thr, "thresholdSource": src,
            "hoursToThreshold": round(hours_left, 1) if hours_left is not None else None,
            "since": recent[0]["date"][:10], "flights": len(pts)}


# ---------------------------------------------------------------- patterns: what may be developing

def patterns(found):
    by = {f["metric"]: f for f in found}
    out = []
    for c in CYL:
        cht, dev, cyc = by.get(f"cht{c}"), by.get(f"egtgap{c}"), by.get(f"cycle{c}")
        if cyc:
            out.append((c, "Exhaust valve starting to leak", [cyc] + [x for x in (dev, cht) if x],
                        "Valve-watch cycle growing on this cylinder. Ask the A&P to borescope the exhaust valve."))
        if dev and cht:
            out.append((c, "Cylinder moving out of balance and running hotter (injector, induction leak, timing)", [dev, cht],
                        "EGT moving away from the other cylinders with CHT rising. Clean/flow the injector, check the intake coupling for leaks, check timing; a GAMI lean test confirms."))
        elif dev:
            out.append((c, "Fuel/air balance change on this cylinder (injector or induction)", [dev],
                        "One EGT moved away from the others. Check that injector and intake; probe if the probe check also flagged it."))
        elif cht:
            out.append((c, "Cylinder running hotter for the conditions", [cht],
                        "Check baffles and seals near this cylinder, the CHT probe, and compare with the oil analysis."))
    if "chtspread" in by and not any(p[0] for p in out):
        out.append((None, "Cylinders drifting apart (cooling or fuel distribution)", [by["chtspread"]], "Baffles, injectors; GAMI lean test."))
    if "oilt" in by:
        out.append((None, "Oil running hotter for the weather (oil cooler, baffles, winterization plate)", [by["oilt"]],
                    "Check the oil cooler and its baffles/plate; compare with oil analysis."))
    if "oilp" in by:
        out.append((None, "Oil pressure sagging (oil level, relief valve, sender, internal wear)", [by["oilp"]],
                    "Check quantity and leaks, then pressure relief setting and sender; watch iron/copper in the oil analysis."))
    if "titgap" in by:
        out.append((None, "The two turbo sides separating (exhaust leak, wastegate, or TIT probe)", [by["titgap"]],
                    "Inspect the exhaust/turbo system and both TIT probes."))
    for v in ("volt1", "volt2"):
        if v in by:
            out.append((None, f"Bus {v[-1]} voltage declining (alternator, regulator, battery, connections)", [by[v]],
                        "Have the alternator output, regulator and battery checked."))
    return out


def run(metrics):
    flights = sorted([m for m in metrics if m], key=lambda m: m["date"])
    cum = 0.0
    for f in flights:
        cum += f.get("airborneHours", 0); f["cumHours"] = cum
    usable = [f for f in flights if f.get("steadySeconds", 0) >= MIN_STEADY_S]
    for f in usable:  # moving AWAY from balance is the concern; moving toward it is not
        for c in CYL:
            if f.get(f"egtdev{c}") is not None: f[f"egtgap{c}"] = abs(f[f"egtdev{c}"])
        if f.get("titdiff") is not None: f["titgap"] = abs(f["titdiff"])
    names = sorted({k for f in usable for k in f if k.startswith(("cht", "egtgap", "egtspread", "oil", "titgap", "volt", "cycle"))})
    found = [x for x in (evaluate(m, usable) for m in names) if x]
    return {"flightsUsed": len(usable), "hoursCovered": round(cum, 1), "findings": found,
            "patterns": [{"cylinder": c, "what": w, "evidence": [e["metric"] for e in ev], "level":
                          "ACT SOON" if any(e["level"] == "ACT SOON" for e in ev) else "EARLY WARNING", "next": nx}
                         for c, w, ev, nx in patterns(found)]}


def describe(r):
    lines = [f"Early warning over {r['flightsUsed']} flights with steady cruise ({r['hoursCovered']} flight hours)."]
    if not r["findings"]:
        lines.append("Nothing drifting: every tracked value is within N63KA's normal and not trending the wrong way.")
    for p in r["patterns"]:
        lines.append(f"  {p['level']}: {p['what']}" + (f" - cylinder {p['cylinder']}" if p["cylinder"] else "") + f". {p['next']}")
    for f in r["findings"]:
        h = f" ; about {f['hoursToThreshold']} flight hours to {f['threshold']} {f['unit']} at this rate" if f["hoursToThreshold"] is not None else ""
        lines.append(f"    {f['label']}: newest flights {f['recentValue']} {f['unit']}, {f['shiftSigma']:+} sigma from normal, "
                     f"{f['slopePerHour']:+} {f['unit']}/h ({', '.join(f['findings'])}){h}")
    return "\n".join(lines)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("logs", nargs="*"); ap.add_argument("--metrics"); ap.add_argument("--valves")
    ap.add_argument("--json", action="store_true"); a = ap.parse_args()
    cache = {}
    if a.metrics and os.path.exists(a.metrics):
        for l in open(a.metrics): m = json.loads(l); cache[m["file"]] = m
    valves = {}
    if a.valves and os.path.exists(a.valves):
        for l in open(a.valves): v = json.loads(l); valves[v["file"]] = v
    for p in a.logs:
        if os.path.basename(p) not in cache:
            m = flight_metrics(p, valves.get(os.path.basename(p)))
            if m: cache[m["file"]] = m
    if a.metrics:
        with open(a.metrics, "w") as f:
            for m in cache.values(): f.write(json.dumps(m) + "\n")
    r = run(list(cache.values()))
    print(json.dumps(r, indent=1) if a.json else describe(r))
