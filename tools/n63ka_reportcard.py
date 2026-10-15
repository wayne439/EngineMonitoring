#!/usr/bin/env python3
"""N63KA flight report card and turbonormalizer / induction checks from Perspective logs.

Report card: about a dozen numbers per flight (takeoff, climb, cruise, oil, electrical), each with a percentile
against N63KA's own earlier flights, so "is this normal for this airplane?" has an answer at a glance.

Turbo and induction checks (advisory, against N63KA's own history):
  takeoff power   - full-throttle RPM (POH 4-16: about 2,700), MAP and fuel flow during the takeoff roll and first climb.
                    Low fuel flow means less cooling fuel (fuel servo/injectors/flow divider); low MAP points at the
                    turbonormalizer (wastegate, controller) or an induction/exhaust leak; low RPM at the governor.
  deck pressure   - full-throttle MAP in climb by 2,000 ft altitude band vs this airplane's normal for that band. A
                    turbonormalized engine holds sea-level MAP to its critical altitude; MAP sagging earlier than normal
                    is the classic turbo/wastegate/exhaust-leak sign. Also reports the highest altitude where MAP held.
  TIT balance     - TIT1 vs TIT2 in steady cruise (the two turbine inlets should read alike).
  induction leak  - a leak downstream of the throttle leans one cylinder most at low manifold pressure. Per cylinder:
                    its EGT relative to the others at low power (MAP under 20 in, airborne) minus the same in cruise.
Usage: python3 n63ka_reportcard.py LOG.csv [...] --json   (per-flight metrics; percentiles with --history file)
"""
import argparse, json, os, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load, num, phases, pct  # noqa: E402

CYL = range(1, 7)
BANDS = list(range(0, 18000, 2000))


def med(v):
    v = [x for x in v if x is not None]
    return statistics.median(v) if v else None


def col(rows, c):
    return [num(r.get(c)) for r in rows]


def flight_metrics(path):
    rows = load(path)
    out = {"file": os.path.basename(path)}
    if len(rows) < 300:
        return dict(out, skip=True)
    ph = phases(rows)
    air = [i for i, p in enumerate(ph) if p in ("climb", "cruise", "descent")]
    out["date"] = rows[0]["_t"].isoformat()
    out["airborneHours"] = round(len(air) / 3600, 2)
    if len(air) < 600:
        return dict(out, skip=True)
    rpm, mp, ff = col(rows, "E1 RPM"), col(rows, "E1 MAP"), col(rows, "E1 FFlow")
    alt, vs, tas = col(rows, "AltB"), col(rows, "VSpd"), col(rows, "TAS")
    cht = {c: col(rows, f"E1 CHT{c}") for c in CYL}
    egt = {c: col(rows, f"E1 EGT{c}") for c in CYL}
    t1, t2 = col(rows, "E1 TIT1"), col(rows, "E1 TIT2")
    oilt, oilp, pw = col(rows, "E1 OilT"), col(rows, "E1 OilP"), col(rows, "E1 %Pwr")
    v1 = col(rows, "volt1")

    # takeoff: first airborne sample, full power from 20 s before to 60 s after
    first = air[0]
    to = [i for i in range(max(0, first - 20), min(len(rows), first + 60)) if (rpm[i] or 0) > 2550 and (mp[i] or 0) > 26]
    if len(to) >= 15:
        out["takeoff"] = {"rpm": round(med(rpm[i] for i in to)), "map": round(med(mp[i] for i in to), 2),
                          "ff": round(med(ff[i] for i in to), 1), "seconds": len(to)}
    # climb at full throttle: MAP within 1.5 in of the takeoff MAP or rpm > 2450 and climbing
    climb = [i for i in air if ph[i] == "climb" and (rpm[i] or 0) > 2400 and alt[i] is not None and mp[i] is not None]
    if climb:
        out["climb"] = {"maxCHT": round(max(max(cht[c][i] or 0 for c in CYL) for i in climb)),
                        "rate": round(med(vs[i] for i in climb)), "maxTIT": round(max(max(t1[i] or 0, t2[i] or 0) for i in climb)),
                        "ff": round(med(ff[i] for i in climb), 1), "seconds": len(climb)}
        # deck pressure by altitude band (highest MAP the engine makes there = full throttle)
        bands = {}
        for b in BANDS:
            v = [mp[i] for i in climb if b <= alt[i] < b + 2000]
            if len(v) >= 20:
                bands[str(b)] = round(pct(v, 0.9), 2)
        out["deckMAP"] = bands
    # steady cruise: cruise phase, RPM/MAP/FF steady over +-30 s
    cr = [i for i in air if ph[i] == "cruise" and 30 <= i < len(rows) - 30 and steady(rpm, mp, ff, i)]
    if len(cr) >= 300:
        def m(v): return med(v[i] for i in cr)
        chts = [statistics.mean(cht[c][i] for c in CYL) for i in cr if all(cht[c][i] is not None for c in CYL)]
        spreads = [max(cht[c][i] for c in CYL) - min(cht[c][i] for c in CYL) for i in cr if all(cht[c][i] is not None for c in CYL)]
        espread = [max(egt[c][i] for c in CYL) - min(egt[c][i] for c in CYL) for i in cr if all(egt[c][i] is not None for c in CYL)]
        tasv, ffv = m(tas), m(ff)
        out["cruise"] = {"seconds": len(cr), "power": round(100 * m(pw)) if m(pw) else None, "map": round(m(mp), 1), "rpm": round(m(rpm)),
                         "ff": round(ffv, 1), "tas": round(tasv) if tasv else None,
                         "nmpg": round(tasv / ffv, 1) if tasv and ffv else None, "altitude": round(m(alt), -2),
                         "chtAvg": round(med(chts)), "chtMax": round(max(max(cht[c][i] or 0 for c in CYL) for i in cr)),
                         "chtSpread": round(med(spreads)), "egtSpread": round(med(espread)),
                         "tit": round(med(max(t1[i] or 0, t2[i] or 0) for i in cr)),
                         "titGap": round(med((t1[i] - t2[i]) for i in cr if t1[i] is not None and t2[i] is not None), 1),
                         "oilT": round(m(oilt)), "oilP": round(m(oilp), 1)}
        out["cruise"]["egtDev"] = {str(c): round(med(egt[c][i] - med([egt[o][i] for o in CYL if o != c]) for i in cr
                                                    if all(egt[o][i] is not None for o in CYL))) for c in CYL}
    # low power airborne (descent / approach, MAP under 20, RPM over 1800): induction-leak check
    low = [i for i in air if mp[i] is not None and mp[i] < 20 and (rpm[i] or 0) > 1800 and all(egt[c][i] is not None for c in CYL)]
    if len(low) >= 60:
        out["lowPower"] = {"seconds": len(low), "egtDev": {str(c): round(med(egt[c][i] - med([egt[o][i] for o in CYL if o != c]) for i in low)) for c in CYL}}
    out["oilTMax"] = round(max(x for x in oilt if x is not None))
    av = [v1[i] for i in air if v1[i] is not None]
    if av:
        out["voltMin"] = round(pct(av, 0.02), 1)
    return out


def steady(rpm, mp, ff, i):
    w = range(i - 30, i + 31)
    r = [rpm[k] for k in w if rpm[k] is not None]; m = [mp[k] for k in w if mp[k] is not None]; f = [ff[k] for k in w if ff[k] is not None]
    return len(r) > 50 and len(m) > 50 and len(f) > 50 and max(r) - min(r) <= 60 and max(m) - min(m) <= 1.5 and max(f) - min(f) <= 1.5


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("logs", nargs="+"); a = ap.parse_args()
    for p in a.logs:
        try:
            print(json.dumps(flight_metrics(p)), flush=True)
        except Exception as e:
            print(json.dumps({"file": os.path.basename(p), "error": str(e)}), flush=True)
