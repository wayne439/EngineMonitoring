#!/usr/bin/env python3
"""N63KA issue check for Perspective engine-data logs, with a register of every issue already seen.

Mirrors the app's IssueDetector (N63KACopilot/Services/IssueDetector.swift): POH limits (with the POH
annunciation durations and the 30 s start grace for oil pressure), technique references, engine starts
(caught then stopped, extra cranking, slow oil pressure), sudden bus 1 voltage drops and GPS fix loss.
Trend checks against N63KA's normal are done by n63ka_flight.py and the app.

Usage:
  python3 n63ka_issues.py LOG.csv [LOG2.csv ...] --register issue-register.json [--update] [--reviews review_log.md]

Prints NEW issue kinds (never seen before), NEW occurrences of known kinds, and known kinds that were marked
Completed in the app's exported review log but happened again (RECURRED). --update writes the register.
Recorded values only; no cause is assigned.
"""
import argparse, json, os, re, sys
from datetime import datetime, timedelta, timezone
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load, num, phases, value  # noqa: E402

# (id, metric, high, low, minRPM, phases, minDuration, startGrace, kind, authority, source, label)
LIMITS = [
    ("rpm-max", "rpm", 2710, None, None, None, 11, 0, "WARNING", "APPROVED", "POH 2-8", "Engine speed above 2,710 RPM for more than 10 s"),
    ("rpm-overspeed", "rpm", 2730, None, None, None, 6, 0, "WARNING", "APPROVED", "POH 2-8", "Engine speed above 2,730 RPM for more than 5 s"),
    ("oilt-max", "oilt", 240, None, None, None, 1, 0, "WARNING", "APPROVED", "POH 2-6 / 2-8", "Oil temperature above 240 F"),
    ("oilp-max", "oilp", 100, None, None, None, 1, 0, "WARNING", "APPROVED", "POH 2-8", "Oil pressure above 100 psi"),
    ("oilp-min", "oilp", None, 10, 1000, None, 2, 30, "WARNING", "APPROVED", "POH 2-8", "Oil pressure below 10 psi"),
    ("oilp-caution", "oilp", None, 30, 1000, {"climb", "cruise", "descent"}, 2, 30, "CAUTION", "APPROVED", "POH 2-8 / 3A-6", "Oil pressure 10-29 psi above 1,000 RPM in flight"),
    ("oilp-idle", "oilp", None, 30, 1000, {"ground"}, 5, 30, "CAUTION", "APPROVED", "POH 2-8 / 3A-6", "Oil pressure 10-29 psi above 1,000 RPM on the ground (OIL PRESS caution)"),
    ("cht-warning", "chtmax", 460, None, None, None, 1, 0, "WARNING", "APPROVED", "POH 2-8", "CHT above 460 F"),
    ("cht-caution", "chtmax", 420, None, None, None, 1, 0, "CAUTION", "APPROVED", "POH 2-8", "CHT above 420 F"),
    ("volt1-low", "volt1", None, 24.5, 1500, {"climb", "cruise", "descent"}, 10, 0, "CAUTION", "APPROVED", "POH 2-9", "Bus 1 voltage below 24.5 V in flight (M BUS 1 caution range)"),
    ("volt2-low", "volt2", None, 24.5, 1500, {"climb", "cruise", "descent"}, 10, 0, "CAUTION", "APPROVED", "POH 2-9", "Bus 2 voltage below 24.5 V in flight (M BUS 2 caution range)"),
    ("volt1-high", "volt1", 32, None, None, None, 3, 0, "WARNING", "APPROVED", "POH 2-9", "Bus 1 voltage above 32 V (M BUS 1 warning range)"),
    ("volt2-high", "volt2", 32, None, None, None, 3, 0, "WARNING", "APPROVED", "POH 2-9", "Bus 2 voltage above 32 V (M BUS 2 warning range)"),
    ("barker-cht", "chtmax", 370, None, 2000, {"climb"}, 1, 0, "REFERENCE", "EXPERIENCE", "Barker flight profile 2023", "CHT above 370 F in climb (technique)"),
    ("barker-tit", "tit", 1325, None, 2000, {"climb"}, 1, 0, "REFERENCE", "EXPERIENCE", "Barker flight profile 2023", "Hotter TIT above 1,325 F in climb (technique)"),
]
SYSTEM = {"volt1": "Electrical / Bus", "volt2": "Electrical / Bus"}
PH = {"off": "off", "ground": "ground", "climb": "climb", "cruise": "cruise", "descent": "descent"}

def epoch(t): return int(t.timestamp())

def exceedances(rows, ph):
    found = []
    for lid, m, hi, lo, minrpm, phs, mind, grace, kind, auth, src, label in LIMITS:
        run, secs, first, ext = [], 0, None, None
        grace_until = None
        def close():
            nonlocal run, secs, first, ext
            if len(run) >= mind:
                secs += len(run); first = first or run[0][0]
                for _, v in run:
                    ext = v if ext is None else (max(ext, v) if hi is not None else min(ext, v))
            run = []
        for r, p in zip(rows, ph):
            rpm = num(r.get("E1 RPM")) or 0
            if grace and rpm < 500: grace_until = r["_t"] + timedelta(seconds=grace)
            outside = False
            if p != "off" and (grace_until is None or r["_t"] > grace_until) and (phs is None or p in phs) \
                    and (minrpm is None or rpm > minrpm):
                v = value(r, m)
                if v is not None:
                    outside = (hi is not None and v > hi) or (lo is not None and v < lo)
                    if outside: run.append((r["_t"], v))
            if not outside: close()
        close()
        if secs: found.append(dict(id=lid, metric=m, high=hi, kind=kind, authority=auth, source=src, label=label, seconds=secs, first=first, extreme=ext))
    # a warning makes the matching caution redundant (same metric and direction)
    return [e for e in found if not (e["kind"] == "CAUTION" and any(
        w["kind"] == "WARNING" and w["metric"] == e["metric"] and (w["high"] is not None) == (e["high"] is not None) for w in found))]

def in_window(rows, lo, hi):
    return [r for r in rows if lo <= r["_t"] <= hi]

def starts(rows):
    recs, stopped, episodes, in_ep, seen = [], True, 0, False, False
    for i, r in enumerate(rows):
        rpm = num(r.get("E1 RPM"))
        if rpm is None: continue
        if not seen:
            seen = True
            if rpm >= 500: stopped = False; continue
        if rpm < 100:
            if in_ep: episodes += 1
            in_ep, stopped = False, True; continue
        if stopped and rpm >= 500:
            t = r["_t"]
            crank = in_window(rows[max(0, i - 60):i + 1], t - timedelta(seconds=30), t)
            after = in_window(rows[i:i + 60], t, t + timedelta(seconds=30))
            v = [num(x.get("volt1")) for x in crank]; v = [x for x in v if x is not None]
            rp = [num(x.get("E1 RPM")) for x in after]; rp = [x for x in rp if x is not None]
            recs.append(dict(time=t, episodes=episodes, minv=min(v) if v else None, rpm30=rp[-1] if rp else None, idx=i))
            stopped, in_ep, episodes = False, False, 0; continue
        if stopped and rpm >= 100: in_ep = True
    return recs

def detect(path):
    rows = load(path); name = os.path.basename(path)
    name = re.sub(r"[^A-Za-z0-9\-_.]", "_", name)
    if not rows: return name, rows, []
    ph = phases(rows); out = []
    hm = lambda t: t.strftime("%H:%M:%S")
    for e in exceedances(rows, ph):
        approved = e["authority"] == "APPROVED"
        sev = "INFO" if not approved else ("WATCH" if e["id"] == "oilp-idle" else ("WARNING" if e["kind"] == "WARNING" else "CAUTION"))
        unit = {"rpm": "", "oilp": " psi", "volt1": " V", "volt2": " V"}.get(e["metric"], " F")
        out.append(dict(kind=("limit." if approved else "technique.") + e["id"], severity=sev, system=SYSTEM.get(e["metric"], "Engine / In Flight"),
                        time=e["first"], title=e["label"],
                        detail=f'{e["seconds"]} s from {hm(e["first"])}, extreme {e["extreme"]:.0f}{unit} ({e["source"]})'))
    for s in starts(rows):
        caught = (s["rpm30"] or 0) >= 500
        volts = f', lowest {s["minv"]:.1f} V cranking' if s["minv"] is not None else ""
        if not caught:
            out.append(dict(kind="start.stopped", severity="WATCH", system="Engine / Start", time=s["time"], title="Engine caught, then stopped within 30 s",
                            detail=f'Start at {hm(s["time"])}; RPM 30 s later {int(s["rpm30"] or 0)}{volts}'))
        elif s["episodes"] > 0:
            out.append(dict(kind="start.extra-cranking", severity="WATCH", system="Engine / Start", time=s["time"], title="Extra cranking before the engine started",
                            detail=f'{s["episodes"]} cranking attempt(s) without a start before {hm(s["time"])}{volts}'))
        if caught:
            after = in_window(rows[s["idx"]:s["idx"] + 60], s["time"], s["time"] + timedelta(seconds=30))
            oil = [num(x.get("E1 OilP")) for x in after]; oil = [x for x in oil if x is not None]
            if len(oil) >= 20 and max(oil) < 10:
                out.append(dict(kind="start.oil-pressure", severity="CAUTION", system="Engine / Start", time=s["time"], title="Oil pressure below 10 psi 30 s after start",
                                detail=f"Highest {max(oil):.0f} psi in the first 30 s after the start at {hm(s['time'])} (POH 4-10)"))
    # sudden bus 1 drop and GPS loss
    drop, last, gps, last_ok = None, None, 0, None
    for i, (r, p) in enumerate(zip(rows, ph)):
        if (num(r.get("E1 RPM")) or 0) > 1000:
            v = num(r.get("volt1"))
            if v is not None:
                if last and last[0] == i - 1 and last[1] - v > (drop or 0): drop = last[1] - v
                last = (i, v)
        fix = r.get("GPSfix")
        if p in ("climb", "cruise", "descent") and fix:
            ok = "nosoln" not in fix.lower()
            if last_ok is True and not ok: gps += 1
            last_ok = ok
    if drop is not None and drop >= 2.0:
        out.append(dict(kind="electrical.voltage-drop", severity="WATCH", system="Electrical / Bus", time=rows[0]["_t"], title="Sudden bus 1 voltage drop",
                        detail=f"Largest one-second drop {drop:.1f} V with the engine running"))
    if gps:
        out.append(dict(kind="avionics.gps-loss", severity="WATCH", system="Avionics / Navigation", time=rows[0]["_t"], title="GPS fix lost in flight",
                        detail=f"GPS solution lost {gps} time(s) while airborne"))
    for o in out:
        o["log"] = name; o["id"] = f'{o["kind"]}|{name}|{epoch(o["time"])}'; o["time"] = o["time"].isoformat()
    return name, rows, out

def completed_kinds(review_md):
    """Kinds marked Completed in the app's exported review log, with the date reviewed through."""
    done = {}
    for line in open(review_md, encoding="utf-8"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 8 and "." in cells[0] and cells[3].startswith("Completed"):
            done[cells[0]] = cells[7]
    return done

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("logs", nargs="+"); ap.add_argument("--register", required=True)
    ap.add_argument("--update", action="store_true"); ap.add_argument("--reviews", help="review log .md exported from the app")
    a = ap.parse_args()
    reg = json.load(open(a.register)) if os.path.exists(a.register) else {"updated": None, "logs": [], "kinds": {}}
    done = completed_kinds(a.reviews) if a.reviews else {}
    new_kinds, new_occ, recurred, skipped = [], [], [], []
    for path in a.logs:
        name, rows, issues = detect(path)
        if name in reg["logs"]: skipped.append(name)
        for o in issues:
            k = reg["kinds"].setdefault(o["kind"], {"title": o["title"], "severity": o["severity"], "system": o["system"], "occurrences": {}})
            if o["id"] in k["occurrences"]: continue
            if not k["occurrences"]: new_kinds.append(o)
            else: new_occ.append(o)
            if o["kind"] in done and o["time"][:10] > done[o["kind"]]: recurred.append(o)
            k["occurrences"][o["id"]] = {"log": o["log"], "time": o["time"], "detail": o["detail"]}
        if name not in reg["logs"]: reg["logs"].append(name)
    tracked = lambda o: o["severity"] != "INFO"
    print(json.dumps({
        "logsChecked": [os.path.basename(p) for p in a.logs], "alreadyInRegister": skipped,
        "newKinds": [o for o in new_kinds], "newOccurrences": [o for o in new_occ if tracked(o)],
        "newTechniqueNotes": len([o for o in new_occ if not tracked(o)]), "recurredAfterCompleted": recurred,
        "registerKinds": len(reg["kinds"]), "registerLogs": len(reg["logs"]),
        "note": "Recorded values only; no cause is assigned. NEW = not in the register before this check."}, indent=1, default=str))
    if a.update:
        reg["updated"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        reg["logs"].sort()
        json.dump(reg, open(a.register, "w"), indent=1, sort_keys=True)
