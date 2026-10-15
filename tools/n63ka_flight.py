#!/usr/bin/env python3
"""N63KA post-flight analysis for Garmin Perspective CSV logs.
Usage: python3 n63ka_flight.py LOG.csv [--baseline baseline.json] [--save-summary summaries_dir]
Prints a JSON report: phases, per-phase stats, POH-limit exceedances, baseline deviations."""
import csv, json, sys, os, statistics, argparse
from datetime import datetime, timedelta, timezone

METRICS = {
    "rpm": ["E1 RPM"], "map": ["E1 MAP"], "ff": ["E1 FFlow"], "oilp": ["E1 OilP"], "oilt": ["E1 OilT"],
    "tit": ["E1 TIT1", "E1 TIT2"], "tit1": ["E1 TIT1"], "tit2": ["E1 TIT2"], "oat": ["OAT"], "volt1": ["volt1"], "volt2": ["volt2"], "amps": ["amp1"],
    **{f"cht{i}": [f"E1 CHT{i}"] for i in range(1, 7)},
}
# (id, metric, high, low, minRPM, phases, minDuration, authority, source, label)
LIMITS = [
    ("rpm-max", "rpm", 2710, None, None, None, 11, "APPROVED", "POH 2-8", "RPM above 2,710 for more than 10 s"),
    ("rpm-overspeed", "rpm", 2730, None, None, None, 6, "APPROVED", "POH 2-8", "RPM above 2,730 for more than 5 s"),
    ("oilt-max", "oilt", 240, None, None, None, 1, "APPROVED", "POH 2-6/2-8", "Oil temperature above 240 F"),
    ("oilp-max", "oilp", 100, None, None, None, 1, "APPROVED", "POH 2-8", "Oil pressure above 100 psi"),
    ("oilp-min", "oilp", None, 10, 1000, None, 1, "APPROVED", "POH 2-8", "Oil pressure below 10 psi"),
    ("oilp-caution", "oilp", None, 30, 1000, None, 1, "APPROVED", "POH 2-8", "Oil pressure 10-29 psi above 1,000 RPM"),
    ("cht-warning", "chtmax", 460, None, None, None, 1, "APPROVED", "POH 2-8", "CHT above 460 F"),
    ("cht-caution", "chtmax", 420, None, None, None, 1, "APPROVED", "POH 2-8", "CHT above 420 F"),
    ("barker-cht", "chtmax", 370, None, 2000, {"climb"}, 1, "EXPERIENCE", "Barker profile", "CHT above 370 F in climb (technique)"),
    ("barker-tit", "tit", 1325, None, 2000, {"climb"}, 1, "EXPERIENCE", "Barker profile", "Hotter TIT above 1,325 F in climb (technique)"),
]

def num(x):
    try: return float(x)
    except (TypeError, ValueError): return None

def load(path):
    rows, header = [], None
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        for raw in csv.reader(f):
            fields = [c.strip() for c in raw]
            if not fields or fields[0].startswith("#") or fields == [""]: continue
            if header is None: header = fields; continue
            r = dict(zip(header, fields))
            try:
                off = r.get("UTCOfst") or "+00:00"; sign = -1 if off.startswith("-") else 1
                hh, mm = off.strip("+-").split(":")
                tz = timezone(sign * timedelta(hours=int(hh), minutes=int(mm)))
                r["_t"] = datetime.strptime(r["Lcl Date"] + " " + r["Lcl Time"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=tz)
            except Exception:
                continue
            rows.append(r)
    return rows

def value(r, m):
    if m == "chtmax":
        v = [num(r.get(f"E1 CHT{i}")) for i in range(1, 7)]; v = [x for x in v if x is not None]
        return max(v) if v else None
    if m == "egtspread":
        v = [num(r.get(f"E1 EGT{i}")) for i in range(1, 7)]; v = [x for x in v if x is not None]
        return max(v) - min(v) if len(v) >= 2 else None
    if m == "tit":  # twin turbochargers: the hotter TIT
        v = [num(r.get(c)) for c in METRICS["tit"]]; v = [x for x in v if x is not None]
        return max(v) if v else None
    return num(r.get(METRICS[m][0]))

def phases(rows):
    vs = [num(r.get("VSpd")) for r in rows]; out = []
    for i, r in enumerate(rows):
        rpm = num(r.get("E1 RPM")) or 0
        if rpm < 500: out.append("off"); continue
        if (num(r.get("IAS")) or 0) < 50: out.append("ground"); continue
        w = [x for x in vs[max(0, i - 7):i + 8] if x is not None]; v = sum(w) / len(w) if w else 0
        out.append("climb" if v > 300 else "descent" if v < -300 else "cruise")
    return out

def pct(s, q):
    s = sorted(s); p = q * (len(s) - 1); lo = int(p); hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (p - lo)

def summarize(rows, ph, name):
    allm = list(METRICS) + ["chtmax", "egtspread"]; stats = {}
    for phase in ("climb", "cruise"):
        idx = [i for i, p in enumerate(ph) if p == phase]
        for m in allm:
            v = [x for x in (value(rows[i], m) for i in idx) if x is not None]
            if len(v) >= 60:
                stats.setdefault(phase, {})[m] = {"p05": pct(v, .05), "p50": pct(v, .5), "p95": pct(v, .95), "max": max(v), "n": len(v)}
    secs = {p: ph.count(p) for p in set(ph)}
    return {"file": name, "start": rows[0]["_t"].isoformat(), "end": rows[-1]["_t"].isoformat(), "phaseSeconds": secs, "stats": stats}

def exceedances(rows, ph):
    out = []
    for lid, m, hi, lo, minrpm, phs, mind, auth, src, label in LIMITS:
        run, total, first, ext = [], 0, None, None
        def close():
            nonlocal run, total, first, ext
            if len(run) >= mind:
                total += len(run); first = first or run[0][0]
                for _, v in run: ext = v if ext is None else (max(ext, v) if hi is not None else min(ext, v))
            run = []
        for r, p in zip(rows, ph):
            v = value(r, m)
            ok_phase = p != "off" and (phs is None or p in phs) and (minrpm is None or (num(r.get("E1 RPM")) or 0) > minrpm)
            outside = ok_phase and v is not None and ((hi is not None and v > hi) or (lo is not None and v < lo))
            if outside: run.append((r["_t"], v))
            else: close()
        close()
        if total: out.append({"id": lid, "label": label, "authority": auth, "source": src, "seconds": total, "first": first.isoformat(), "extreme": ext})
    return out

def baseline(summaries):
    flights = [s for s in summaries if sum(s["phaseSeconds"].get(p, 0) for p in ("climb", "cruise", "descent")) >= 300]
    b = {}
    for phase in ("climb", "cruise"):
        ms = {m for s in flights for m in s["stats"].get(phase, {})}
        for m in ms:
            med = sorted(s["stats"][phase][m]["p50"] for s in flights if m in s["stats"].get(phase, {}))
            if len(med) >= 5: b.setdefault(phase, {})[m] = {"low": pct(med, .1), "high": pct(med, .9), "typical": pct(med, .5), "flights": len(med)}
    return {"flights": len(flights), "ranges": b}

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("log"); ap.add_argument("--summaries", help="dir of earlier *.summary.json")
    ap.add_argument("--save-summary", action="store_true"); a = ap.parse_args()
    rows = load(a.log); ph = phases(rows); name = os.path.basename(a.log)
    summ = summarize(rows, ph, name)
    hist = []
    if a.summaries and os.path.isdir(a.summaries):
        for fn in os.listdir(a.summaries):
            if fn.endswith(".summary.json") and not fn.startswith(name):
                hist.append(json.load(open(os.path.join(a.summaries, fn))))
    base = baseline(hist); dev = []
    for phase, ms in summ["stats"].items():
        for m, s in ms.items():
            r = base["ranges"].get(phase, {}).get(m)
            if r and not (r["low"] <= s["p50"] <= r["high"]):
                dev.append({"phase": phase, "metric": m, "median": s["p50"], "usual": [r["low"], r["high"]], "flights": r["flights"]})
    if a.save_summary and a.summaries:
        os.makedirs(a.summaries, exist_ok=True); json.dump(summ, open(os.path.join(a.summaries, name + ".summary.json"), "w"))
    print(json.dumps({"summary": summ, "exceedances": exceedances(rows, ph), "baselineFlights": base["flights"], "deviations": dev,
                      "note": "TIT/MAP turbonormalizer limits not checked (Tornado Alley AFM supplement not loaded)."}, indent=1, default=str))
