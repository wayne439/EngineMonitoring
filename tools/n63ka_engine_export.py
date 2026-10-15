#!/usr/bin/env python3
"""Exports run-up mag check, GAMI tests and the flight card in the app's EngineCheckResult JSON (FlightSummary v9),
plus the per-flight issues, for the bundled flight_history.json. Usage: n63ka_engine_export.py LOG.csv [...] (JSON lines)."""
import json, os, sys, statistics
from datetime import timezone
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from n63ka_flight import load
import n63ka_magcheck as MC, n63ka_gami as GA, n63ka_reportcard as RC

def iso(t): return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def runup_text(u):
    s = f"Run-up at {u['rpm']} RPM ({u['seconds']} s): " + ", ".join(f"{m['mag']} drop {m['drop']}" for m in u["mags"])
    if len(u["mags"]) == 2: s += f", difference {abs(u['mags'][0]['drop'] - u['mags'][1]['drop'])}"
    return s + " RPM."

def card(rc):
    if rc.get("skip") or "error" in rc: return None
    c = {"airborneHours": rc["airborneHours"], "climbSeconds": 0, "cruiseSeconds": 0, "lowPowerSeconds": 0, "deckMAP": rc.get("deckMAP", {})}
    if "takeoff" in rc: c.update(takeoffRPM=rc["takeoff"]["rpm"], takeoffMAP=rc["takeoff"]["map"], takeoffFF=rc["takeoff"]["ff"])
    if "climb" in rc:
        k = rc["climb"]; c.update(climbSeconds=k["seconds"], climbMaxCHT=k["maxCHT"], climbRate=k["rate"], climbMaxTIT=k["maxTIT"], climbFF=k["ff"])
    if "cruise" in rc:
        k = rc["cruise"]; p = k.get("power")
        c.update(cruiseSeconds=k["seconds"], cruisePower=(p * 100 if p is not None and p <= 1.5 else p), cruiseMAP=k["map"], cruiseRPM=k["rpm"],
                 cruiseFF=k["ff"], cruiseTAS=k["tas"], cruiseNMPG=k["nmpg"], cruiseAltitude=k["altitude"], cruiseCHTAvg=k["chtAvg"],
                 cruiseCHTMax=k["chtMax"], cruiseCHTSpread=k["chtSpread"], cruiseEGTSpread=k["egtSpread"], cruiseTIT=k["tit"],
                 cruiseTITGap=k["titGap"], cruiseOilT=k["oilT"], cruiseOilP=k["oilP"])
        if all(k["egtDev"].get(str(i)) is not None for i in range(1, 7)): c["cruiseEGTDev"] = [k["egtDev"][str(i)] for i in range(1, 7)]
    if "lowPower" in rc:
        c["lowPowerSeconds"] = rc["lowPower"]["seconds"]
        c["lowPowerEGTDev"] = [rc["lowPower"]["egtDev"][str(i)] for i in range(1, 7)]
    for k in ("oilTMax", "voltMin"):
        if k in rc: c[k] = rc[k]
    return {k: v for k, v in c.items() if v is not None}

KIND = {"drop": "drop", "split": "split", "one-mag": "oneMag", "cold-cyl": "coldCylinder"}

def export(path):
    rows = load(path); name = os.path.basename(path)
    mc, ga, rc = MC.analyse(path), GA.analyse(path), RC.flight_metrics(path)
    runups, issues = [], []
    for u in mc["runups"]:
        mags = [{"mag": m["mag"], "time": iso(rows[m["i"]]["_t"]), "drop": m["drop"], "seconds": m["seconds"], "rise": m["rise"]} for m in u["mags"]]
        fs = []
        for f in u["findings"]:
            k = KIND[f["kind"]]
            if k == "drop": x = {"kind": k, "mag": f["mag"], "value": f["drop"]}
            elif k == "split": x = {"kind": k, "value": f["drops"][0], "other": f["drops"][1]}
            elif k == "oneMag": x = {"kind": k, "mag": u["mags"][0]["mag"], "value": f["drop"]}
            else: x = {"kind": k, "mag": f["mag"], "cylinder": f["cylinder"], "value": f["rise"], "other": f["others"]}
            fs.append(x)
            at = next((mm["time"] for mm in mags if mm["mag"] == x.get("mag")), iso(rows[u["i"]]["_t"]))
            txt = runup_text(u)
            if k == "drop":
                issues.append(dict(kind="mag.drop", severity="CAUTION", time=at, title=f"Run-up: {x['mag']} mag drop {int(x['value'])} RPM (POH limit 150)", detail=txt))
            elif k == "split":
                issues.append(dict(kind="mag.split", severity="CAUTION", time=iso(rows[u["i"]]["_t"]), title=f"Run-up: mag drops differ by {int(abs(x['value'] - x['other']))} RPM (POH limit 75)", detail=txt))
            elif k == "coldCylinder":
                issues.append(dict(kind=f"mag.cyl{x['cylinder']}", severity="WATCH", time=at, title=f"Run-up: cylinder {x['cylinder']} EGT did not rise on the {x['mag']} mag",
                                   detail=f"Cylinder {x['cylinder']} EGT {x['value']:+.0f} °F on the {x['mag']} mag while the others rose {x['other']:.0f} °F. " + txt))
            else:
                issues.append(dict(kind="mag.one", severity="INFO", time=iso(rows[u["i"]]["_t"]), title="Run-up: only one mag drop recorded",
                                   detail=f"One drop of {int(x['value'])} RPM in a {u['seconds']} s run-up. No drop on the other mag can mean a P-lead grounding fault or advanced timing (POH 4-14); usually the check was quick or under 25 RPM. " + txt))
        runups.append({"time": iso(rows[u["i"]]["_t"]), "rpm": u["rpm"], "seconds": u["seconds"], "mags": mags, "findings": fs})
    gami = []
    for t in ga["tests"]:
        pf = [t["peaks"][c]["ff"] if c in t["peaks"] else None for c in range(1, 7)]
        gami.append({"time": iso(rows[t["i"]]["_t"]), "seconds": t["seconds"], "ffStart": t["ffStart"], "ffEnd": t["ffEnd"], "peakFlow": pf,
                     "spread": t["spread"], "richest": t["richest"], "leanest": t["leanest"]})
    for i in issues:
        i.update(system="Engine / Start", origin="Engine data card", source=name)
    out = {"runups": runups, "gami": gami}
    c = card(rc)
    if c: out["card"] = c
    return {"file": name, "engineChecks": out, "issues": issues}

if __name__ == "__main__":
    for p in sys.argv[1:]:
        try: print(json.dumps(export(p)), flush=True)
        except Exception as e: print(json.dumps({"file": os.path.basename(p), "error": repr(e)}), flush=True)
