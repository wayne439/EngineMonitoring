#!/usr/bin/env python3
"""N63KA run-up magneto check from Perspective logs (POH 4-14 Before Takeoff: 1,700 RPM, R then L; RPM drop must not
exceed 150 RPM for either magneto and the differential must not exceed 75 RPM; an absence of RPM drop may indicate
faulty grounding or advanced timing).

Finds the run-up (on the ground, RPM held 1,600-2,150 for 20 s or more), the RPM dips inside it (25+ RPM below the
run-up RPM for 2-25 s; drop = run-up RPM minus the settled single-mag RPM, the lower half of the dip), and keeps the dips where the EGTs rise as they do on a single magneto (median rise of the six
cylinders at least 10 F); a dip where the EGTs fall together is a power change, not a mag check. The first two
mag dips are taken in POH order (R, then L). Per mag: RPM drop and each cylinder's EGT rise.

Findings:
  drop        a mag drop over 150 RPM (POH)                          -> CAUTION
  split       drops differ by more than 75 RPM (POH)                 -> CAUTION
  one-mag     only one mag drop seen in a 30 s+ run-up                -> INFO (no drop on the other mag can mean P-lead
                                                                         grounding or timing - POH - but usually the check
                                                                         was quick or below 25 RPM; shown, not alarmed)
  cold-cyl    on one mag, a cylinder's EGT falls or stays flat while the others rise (at least 25 F less than the
              others' median, and under 5 F): that cylinder is not firing on that mag - plug, lead or mag   -> WATCH
Usage: python3 n63ka_magcheck.py LOG.csv [...] [--json]
"""
import argparse, json, os, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load, num, phases  # noqa: E402

MAX_DROP, MAX_SPLIT = 150, 75
MIN_DIP, MIN_EGT_RISE = 25, 10
COLD_MARGIN, COLD_MAX = 25, 5


def runup_segments(rows, ph):
    n = len(rows); rpm = [num(r.get("E1 RPM")) for r in rows]; out = []; k = 0
    while k < n:
        if ph[k] == "ground" and rpm[k] and 1600 <= rpm[k] <= 2150:
            j = k
            while j < n and ph[j] == "ground" and rpm[j] and 1450 <= rpm[j] <= 2200: j += 1
            if j - k >= 20:
                base = statistics.median([x for x in rpm[k:j] if x]); dips = []; m = k
                while m < j:
                    if rpm[m] and base - rpm[m] >= MIN_DIP:
                        e = m
                        while e < j and rpm[e] and base - rpm[e] >= 15: e += 1
                        if 2 <= e - m <= 25: dips.append((m, e))
                        m = e
                    else:
                        m += 1
                out.append((k, j, base, dips))
            k = j + 1
        else:
            k += 1
    return out


def analyse(path):
    rows = load(path)
    out = {"file": os.path.basename(path), "runups": []}
    if len(rows) < 120: return out
    ph = phases(rows)
    rpm = [num(r.get("E1 RPM")) for r in rows]
    egt = [[num(r.get(f"E1 EGT{c}")) for r in rows] for c in range(1, 7)]
    for k, j, base, dips in runup_segments(rows, ph):
        mags = []
        for m, e in dips:
            rise = []
            for c in range(6):
                pre = [x for x in egt[c][max(k, m - 6):m] if x is not None]
                dur = [x for x in egt[c][m:min(len(rows), e + 4)] if x is not None]
                rise.append(round(max(dur) - statistics.median(pre), 1) if pre and dur else None)
            r = [x for x in rise if x is not None]
            if len(r) < 4 or statistics.median(r) < MIN_EGT_RISE: continue   # power change, not a mag check
            low = sorted(x for x in rpm[m:e] if x)
            settled = statistics.median(low[:max(1, (len(low) + 1) // 2)])   # lower half: the settled single-mag RPM
            mags.append({"time": rows[m]["Lcl Time"], "i": m, "drop": round(base - settled), "seconds": e - m, "rise": rise})
            if len(mags) == 2: break
        if not mags: continue
        f = []
        for i, mg in enumerate(mags):
            name = "R" if i == 0 else "L"
            mg["mag"] = name
            if mg["drop"] > MAX_DROP: f.append({"kind": "drop", "mag": name, "drop": mg["drop"]})
            for c in range(6):
                x = mg["rise"][c]
                others = [y for i2, y in enumerate(mg["rise"]) if i2 != c and y is not None]
                if x is not None and others:
                    mo = statistics.median(others)
                    if x < COLD_MAX and mo - x >= COLD_MARGIN:
                        f.append({"kind": "cold-cyl", "mag": name, "cylinder": c + 1, "rise": x, "others": round(mo, 1)})
        if len(mags) == 2 and abs(mags[0]["drop"] - mags[1]["drop"]) > MAX_SPLIT:
            f.append({"kind": "split", "drops": [mags[0]["drop"], mags[1]["drop"]]})
        if len(mags) == 1 and j - k >= 30:
            f.append({"kind": "one-mag", "drop": mags[0]["drop"]})
        out["runups"].append({"time": rows[k]["Lcl Time"], "i": k, "rpm": round(base), "seconds": j - k, "mags": mags, "findings": f})
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("logs", nargs="+"); ap.add_argument("--json", action="store_true"); a = ap.parse_args()
    res = [analyse(p) for p in a.logs]
    if a.json: print(json.dumps(res, indent=1))
    else:
        for r in res:
            for u in r["runups"]:
                print(r["file"], u["time"], u["rpm"], [(m["mag"], m["drop"], m["rise"]) for m in u["mags"]], u["findings"])
