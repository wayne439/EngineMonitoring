#!/usr/bin/env python3
"""Generates approach_cards.json: step-by-step Perspective/GFC 700 approach guides for N63KA.
Every step says what to press and when. Steps quoted from the POH carry authority APPROVED and the page;
everything else is a TRAINING aid to be reviewed by a CFII."""
import json, re

B, AP, HF = "both", "autopilot", "manual"

def step(action, controls=(), when=None, verify=None, mode=B, source=None, approved=False):
    """approved=True only when the step restates POH text (speeds, Before Landing, Balked Landing)."""
    return {"action": action, "controls": list(controls), "when": when, "verify": verify, "mode": mode,
            "source": source, "authority": "APPROVED" if approved else "TRAINING"}

# ---------------------------------------------------------------- shared blocks
def load_block(kind):
    s = [
        step("Get the weather and choose the approach. Check NOTAMs for the approach and navaid.", when="Before descent"),
        step("Load the approach: press PROC, choose 'Select Approach', pick the airport and approach, then the transition (or VECTORS), and press ENT. Choose LOAD now; ACTIVATE when cleared or on vectors.",
             ["PROC", "FMS knob", "ENT"], when="Before descent",
             verify="Approach name and transition in the flight plan match the chart. Database must be current (POH 2-19 item 4).",
             source="POH 2-19 (approaches must come from the current database)"),
        step("Brief the chart: final course, FAF and its altitude, minimums, missed approach point, missed approach procedure and altitude.", when="Before descent"),
        step("Set minimums: TMR/REF softkey, then Minimums: BARO, enter the %s, then CLR to close." % ("DA" if kind == "DA" else "MDA (round up to the next 10 ft if needed)"),
             ["TMR/REF softkey", "FMS knob", "CLR"], when="Before descent", verify="Minimums bug shows on the altimeter."),
    ]
    return {"title": "Brief and load", "steps": s}

def tune_block(nav, course_note):
    return {"title": "Tune and identify", "steps": [
        step("Make the %s frequency ACTIVE in NAV1. Loading the approach usually tunes it; if not, tune it with the NAV knob and press the NAV swap key." % nav,
             ["NAV knob", "NAV swap"], when="Before the IAF or vectors to final", verify="Correct frequency in NAV1 ACTIVE (left/top position)."),
        step("Identify the station: select NAV1 on the audio panel and listen to the Morse code.", ["Audio panel NAV1"],
             when="Before the IAF", verify="Morse matches the chart identifier."),
    ] + ([step(course_note, when="Before the FAF")] if course_note else [])}

def arrival_block():
    return {"title": "Getting to the final course", "steps": [
        step("Full approach (via an IAF): fly the transition with the autopilot in NAV on GPS. Use ALT to hold, VS or FLC to descend; set the ALT SEL knob to each cleared altitude first.",
             ["AP", "NAV", "ALT SEL knob", "VS", "FLC", "ALT"], when="From the IAF", mode=AP, verify="FMA: GPS (green) lateral."),
        step("Vectors: when ATC gives vectors to final, press PROC, 'Activate Vector-to-Final', ENT. Fly ATC headings in HDG mode and hold altitude in ALT.",
             ["PROC", "ENT", "HDG", "HDG knob", "ALT"], when="On vectors", mode=AP, verify="FMA: HDG and ALT (green)."),
        step("Full approach: follow the magenta CDI through the transition; descend to each charted altitude.",
             ["CDI needle"], when="From the IAF", mode=HF),
        step("Vectors: PROC, 'Activate Vector-to-Final', ENT; fly ATC headings on the heading bug. Turn on the flight director (FD) for command bars if you want them.",
             ["PROC", "ENT", "HDG knob", "FD"], when="On vectors", mode=HF),
        step("Slow down and configure: Fuel pump BOOST, mixture as required. Normal approach speeds: flaps UP 90-95 KIAS, flaps 50% 85-90 KIAS, flaps 100% 80-85 KIAS.",
             ["Fuel pump BOOST", "Flaps"], when="Before the FAF", source="POH 4-3 (Landing Approach speeds), POH 4-19 (Before Landing)", approved=True),
    ]}

def minimums_block(kind):
    if kind == "DA":
        s = [
            step("Disconnect the autopilot no lower than the minimum use height in the GFC 700 AFM supplement, then hand-fly.",
                 ["AP DISC"], when="Approaching DA", mode=AP),
            step("At DA: continue only with the required visual references (14 CFR 91.175); otherwise go around immediately.",
                 when="At DA", verify="Altimeter at the minimums bug."),
        ]
    else:
        s = [
            step("Level at the MDA (ALT captures at the ALT SEL value). Do not descend below the MDA without the required visual references (14 CFR 91.175).",
                 ["ALT"], when="At MDA", verify="FMA: ALT (green) at the MDA."),
            step("Fly level to the missed approach point. If not visual at the MAP, go around.", when="MDA to MAP"),
            step("Disconnect the autopilot before leaving the MDA to land, then hand-fly.", ["AP DISC"], when="Visual at MDA", mode=AP),
        ]
    s.append(step("Landing: flaps 100%, 80-85 KIAS.", ["Flaps"], when="Landing assured", source="POH 4-3", approved=True))
    return {"title": "Minimums", "steps": s}

def missed_block(nav):
    switch = "" if nav == "GPS" else " If the CDI is still on %s and the missed approach is flown on GPS, press the CDI softkey until GPS." % nav
    return {"title": "Missed approach", "steps": [
        step("Autopilot DISENGAGE, power lever FULL FORWARD, flaps 50%, 75-80 KIAS until clear of obstacles; then flaps UP and accelerate.",
             ["AP DISC", "Power lever", "Flaps"], when="At DA / MAP, not visual", source="POH 4-21 (Balked Landing/Go-Around)", approved=True),
        step("Press the GO AROUND button on the power lever: the flight director shows go-around pitch and the missed approach sequences in the flight plan." ,
             ["GO AROUND"], when="Same time as power", verify="FMA: GA (green). Flight plan sequences to the missed approach (no SUSP)."),
        step("If SUSP shows at the MAP instead, press the SUSP softkey (or PROC, 'Activate Missed Approach', ENT)." + switch,
             ["SUSP softkey", "PROC", "CDI softkey"], when="Climbing"),
        step("Once climbing with a rate that meets the procedure's altitudes: set ALT SEL to the missed approach altitude, press AP, then NAV (GPS) or HDG, and FLC or VS for the climb.",
             ["ALT SEL knob", "AP", "NAV", "HDG", "FLC"], when="Positive climb", mode=AP,
             verify="FMA: GPS or HDG lateral, FLC/VS with ALTS armed (white).",
             source="POH 2-20 item g (coupled missed approach allowed with GFC 700 software 0764.09 or later; N63KA has 0764.38)"),
        step("Hand-fly the missed approach on the CDI; FD bars give guidance if FD is on. Set ALT SEL to the missed approach altitude.",
             ["ALT SEL knob", "FD"], when="Positive climb", mode=HF),
        step("Tell ATC 'missed approach' and follow the published missed or ATC instructions.", when="Workload allows"),
    ]}

def card(id_, title, subtitle, minima, source, vertical, trap, phases, notes):
    return {"id": id_, "title": title, "subtitle": subtitle, "minimaType": minima, "navSource": source,
            "verticalGuidance": vertical, "keyTrap": trap, "phases": phases, "notes": notes,
            "authority": "TRAINING", "revision": "v5 (2026-10-06)"}

cards = []

# ---------------------------------------------------------------- ILS
cards.append(card("ils", "ILS", "Localizer + glideslope | DA", "DA", "LOC1", "Glideslope (approved)",
    "The ILS must be flown on LOC1, never on GPS (POH 2-19 item 4b). Capture the glideslope from below.",
    [load_block("DA"),
     tune_block("ILS", "Course: the system sets the final course when the CDI switches to LOC1; check it matches the chart."),
     arrival_block(),
     {"title": "Intercept and arm", "steps": [
        step("Check the CDI: with the ILS loaded and active, it switches from GPS to LOC1 automatically as you turn inbound on the final course. If it has not, press the CDI softkey until LOC1.",
             ["CDI softkey"], when="Inbound, before the FAF", verify="HSI shows LOC1 in green; course pointer on the final course.",
             source="POH 2-19 item 4c (VOR/ILS data must be displayed)"),
        step("Cleared for the approach and on an intercept heading (30 degrees or less): press APR.", ["APR"],
             when="On the intercept heading", mode=AP, verify="FMA: LOC armed (white) and GS armed (white); HDG and ALT active (green)."),
        step("LOC captures: lateral becomes LOC (green). Keep ALT until the glideslope.", when="On the localizer", mode=AP, verify="FMA: LOC (green), GS (white)."),
        step("Turn on the FD and press APR for command bars, or fly raw data: center the green CDI and wait for the glideslope diamond.",
             ["FD", "APR"], when="On the intercept heading", mode=HF),
     ]},
     {"title": "Final approach", "steps": [
        step("Glideslope captures from below at the glideslope intercept altitude: the autopilot starts down. Reduce power to hold your approach speed.",
             ["Power lever"], when="Glideslope intercept", mode=AP, verify="FMA: LOC and GS (green)."),
        step("After GS capture: set the ALT SEL knob to the missed approach altitude (the autopilot will not level at it while on the glideslope).",
             ["ALT SEL knob"], when="After GS capture", mode=AP),
        step("At the glideslope: reduce power to start down; keep the CDI and glideslope centered.", ["Power lever"], when="Glideslope intercept", mode=HF),
        step("Set the ALT SEL knob to the missed approach altitude.", ["ALT SEL knob"], when="After glideslope intercept", mode=HF),
        step("Cross-check altitude at the FAF / outer marker with the chart.", when="At the FAF", verify="Altimeter matches the chart crossing altitude."),
     ]},
     minimums_block("DA"), missed_block("LOC1")],
    ["Minima are DA. The glideslope is approved vertical guidance."]))

# ---------------------------------------------------------------- LOC
cards.append(card("loc", "LOC", "Localizer only | MDA", "MDA", "LOC1", "None",
    "No glideslope: protect the MDA with ALT SEL. The ILS must be flown on LOC1, never on GPS (POH 2-19 item 4b).",
    [load_block("MDA"),
     tune_block("LOC", "Course: the system sets the final course when the CDI switches to LOC1; check it matches the chart."),
     arrival_block(),
     {"title": "Intercept and arm", "steps": [
        step("Check the CDI: it switches from GPS to LOC1 automatically as you turn inbound. If not, press the CDI softkey until LOC1.",
             ["CDI softkey"], when="Inbound, before the FAF", verify="HSI shows LOC1 in green.", source="POH 2-19 item 4c"),
        step("Cleared and on an intercept heading: press APR.", ["APR"], when="On the intercept heading", mode=AP,
             verify="FMA: LOC armed (white), then LOC (green). No GS."),
        step("Center the green CDI; FD with APR gives lateral command bars.", ["FD", "APR"], when="On the intercept heading", mode=HF),
     ]},
     {"title": "Final approach (step-downs to MDA)", "steps": [
        step("Before the FAF: set the ALT SEL knob to the next step-down altitude, then the MDA (round up).", ["ALT SEL knob"], when="Before the FAF"),
        step("At the FAF: press VS and set about 600-800 ft/min down with the NOSE UP/DN wheel.",
             ["VS", "NOSE UP/DN wheel"], when="At the FAF", mode=AP, verify="FMA: VS (green), ALTS armed (white)."),
        step("At the FAF: reduce power and descend about 600-800 ft/min to each step-down, then the MDA.", ["Power lever"], when="At the FAF", mode=HF),
        step("Start the timer at the FAF if the MAP is defined by time: TMR/REF softkey, START.", ["TMR/REF softkey"], when="At the FAF"),
     ]},
     minimums_block("MDA"), missed_block("LOC1")],
    ["Minima are MDA. Any vertical guidance shown is advisory only (POH 2-19 item 4d)."]))

# ---------------------------------------------------------------- VOR family
def vor_card(dme):
    id_ = "vor-dme" if dme else "vor"
    title = "VOR/DME" if dme else "VOR"
    sub = "VOR course, DME fixes | MDA" if dme else "VOR course | MDA"
    dme_steps = []
    if dme:
        dme_steps = [step("DME fixes: N63KA's WAAS GPS may be used in place of DME for fixes that are in the loaded approach (AIM 1-1-17). Confirm each DME fix is a named waypoint in the flight plan; the GPS distance to it replaces the DME reading.",
                          when="Brief", verify="Every DME fix on the chart appears in the loaded approach.")]
    phases = [
        load_block("MDA"),
        tune_block("VOR", None),
        arrival_block(),
        {"title": "Switch to VOR and arm", "steps": dme_steps + [
            step("Press the CDI softkey until VOR1. The system does NOT switch to VOR automatically for a VOR approach, and the final course must be flown on VOR1, not GPS.",
                 ["CDI softkey"], when="Before turning inbound, well before the FAF", verify="HSI shows VOR1 in green with the TO/FROM flag.",
                 source="POH 2-19 items 4b-4c (approaches not approved for GPS need VOR data on the display)"),
            step("Set the CRS knob to the final approach course (the system does not set it for VOR).", ["CRS knob"], when="After switching to VOR1",
                 verify="Course pointer on the final course."),
            step("Cleared and established inbound or on an intercept heading: press APR.", ["APR"], when="Inbound", mode=AP,
                 verify="FMA: VAPP armed (white), then VAPP (green)."),
            step("Center the green CDI; FD with APR gives lateral command bars.", ["FD", "APR"], when="Inbound", mode=HF),
        ]},
        {"title": "Final approach (step-downs to MDA)", "steps": [
            step("Set the ALT SEL knob to the next step-down altitude, then the MDA (round up).", ["ALT SEL knob"], when="Before each step-down"),
            step(("At the FAF or the DME fix shown on the chart" if dme else "At the FAF") + ": press VS and set about 600-800 ft/min down with the NOSE UP/DN wheel.",
                 ["VS", "NOSE UP/DN wheel"], when="At the FAF", mode=AP, verify="FMA: VAPP and VS (green), ALTS armed (white)."),
            step("At the FAF: reduce power and descend about 600-800 ft/min.", ["Power lever"], when="At the FAF", mode=HF),
            step("Start the timer at the FAF if the MAP is defined by time: TMR/REF softkey, START.", ["TMR/REF softkey"], when="At the FAF"),
            step("Station passage (if the VOR is on the field): the TO/FROM flag flips; keep tracking the outbound course.", when="Over the VOR"),
        ]},
        minimums_block("MDA"),
        missed_block("VOR1"),
    ]
    notes = ["Minima are MDA. Any vertical guidance shown is advisory only (POH 2-19 item 4d).",
             "If the chart title includes 'or GPS' you may fly it as a GPS approach instead; otherwise the final must be on VOR1."]
    if dme:
        notes.append("If a required DME fix is not in the database, GPS cannot substitute for it; without a DME receiver the approach is not available.")
    return card(id_, title, sub, "MDA", "VOR1", "None",
                "The system will not switch the CDI to VOR for you: press CDI until VOR1 and set the course yourself.", phases, notes)

cards.append(vor_card(False))
cards.append(vor_card(True))

# ---------------------------------------------------------------- RNAV family
def rnav_card(id_, title, sub, minima, vertical, trap, ap_vertical_steps, hf_vertical_steps, notes, annunciation):
    phases = [
        load_block(minima),
        arrival_block(),
        {"title": "Before the FAF", "steps": [
            step("Check the approach annunciation on the HSI changes from TERM to %s within 2 NM of the FAF. If it shows a lower level (for example LNAV), fly to those minimums." % annunciation,
                 when="2 NM before the FAF", verify="HSI: %s." % annunciation),
            step("Cleared for the approach and on the final course or an intercept: press APR.", ["APR"], when="Cleared for the approach", mode=AP,
                 verify="FMA: GPS (green) lateral" + ("; GP armed (white)." if minima == "DA" else ".")),
            step("Fly the magenta CDI; FD with APR gives command bars.", ["FD", "APR"], when="Cleared for the approach", mode=HF),
        ]},
        {"title": "Final approach", "steps": ap_vertical_steps + hf_vertical_steps},
        minimums_block(minima),
        missed_block("GPS"),
    ]
    return card(id_, title, sub, minima, "GPS", vertical, trap, phases, notes)

gp_ap = [
    step("Hold altitude in ALT until the glidepath: GP captures automatically and the autopilot starts down. Reduce power for approach speed.",
         ["ALT", "Power lever"], when="Glidepath intercept (near the FAF)", mode=AP, verify="FMA: GPS and GP (green)."),
    step("After GP capture: set the ALT SEL knob to the missed approach altitude. The autopilot will not level at the selected altitude while on GP.",
         ["ALT SEL knob"], when="After GP capture", mode=AP, source="POH TPOH 15-21 (GP mode does not capture a preselected altitude)"),
]
gp_hf = [
    step("At the glidepath diamond: reduce power and follow the magenta glidepath (VDI) and CDI.", ["Power lever"], when="Glidepath intercept", mode=HF),
    step("Set the ALT SEL knob to the missed approach altitude.", ["ALT SEL knob"], when="After glidepath intercept", mode=HF),
]
cards.append(rnav_card("lpv", "RNAV (GPS) - LPV", "WAAS lateral + vertical | DA", "DA", "Glidepath (approved)",
    "LPV must show on the HSI before the FAF; otherwise use the lower minima the system shows.", gp_ap, gp_hf,
    ["Minima are DA when LPV is annunciated."], "LPV"))
cards.append(rnav_card("lnav-vnav", "RNAV (GPS) - LNAV/VNAV", "Lateral + vertical | DA", "DA", "Glidepath (approved)",
    "L/VNAV needs WAAS (or Baro-VNAV within its temperature limits). If it downgrades to LNAV, use LNAV MDA.", gp_ap, gp_hf,
    ["Minima are DA when L/VNAV is annunciated.", "Baro-VNAV: see TPOH 15-21 for temperature limits and downgrades."], "L/VNAV"))

mda_steps_ap = [
    step("Set the ALT SEL knob to the next step-down altitude, then the MDA (round up).", ["ALT SEL knob"], when="Before each step-down", mode=AP),
    step("At the FAF: press VS and set about 600-800 ft/min down with the NOSE UP/DN wheel. ALT captures at the MDA.",
         ["VS", "NOSE UP/DN wheel"], when="At the FAF", mode=AP, verify="FMA: GPS and VS (green), ALTS armed (white)."),
]
mda_steps_hf = [
    step("Set the ALT SEL knob to each step-down, then the MDA.", ["ALT SEL knob"], when="Before each step-down", mode=HF),
    step("At the FAF: reduce power and descend about 600-800 ft/min; level at each step-down and at the MDA.", ["Power lever"], when="At the FAF", mode=HF),
]
cards.append(rnav_card("lnav", "RNAV (GPS) - LNAV", "Lateral only | MDA", "MDA", "None",
    "No approved vertical guidance: protect every step-down and the MDA with ALT SEL.", mda_steps_ap, mda_steps_hf,
    ["Minima are MDA. Any vertical guidance is advisory only (POH 2-19 item 4d)."], "LNAV"))

plusv_ap = [
    step("Option A (VS, protects the MDA): set the ALT SEL knob to the MDA; at the FAF press VS and set about 600-800 ft/min down. ALT captures at the MDA.",
         ["ALT SEL knob", "VS", "NOSE UP/DN wheel"], when="At the FAF", mode=AP, verify="FMA: GPS and VS (green), ALTS armed (white)."),
    step("Option B (coupled +V): APR can couple to the advisory glidepath (GP). GP will NOT level off at the MDA: be ready to press ALT or disconnect at the MDA.",
         ["APR", "ALT"], when="At the FAF", mode=AP, verify="FMA: GPS and GP (green); watch the altimeter against the MDA.",
         source="POH 2-19 item 4d (vertical guidance advisory only)"),
]
plusv_hf = [
    step("Use the +V glidepath as advisory only; set ALT SEL to the MDA and level at the MDA.", ["ALT SEL knob", "Power lever"], when="At the FAF", mode=HF),
]
cards.append(rnav_card("lnav-plus-v", "RNAV (GPS) - LNAV+V", "LNAV minima + advisory +V | MDA", "MDA", "Advisory +V",
    "+V does not change the approach: it is still an MDA approach (POH 2-19 item 4d).", plusv_ap, plusv_hf,
    ["Minima are LNAV MDA. +V is advisory only."], "LNAV+V"))
cards.append(rnav_card("lp", "RNAV (GPS) - LP / LP+V", "LP minima; +V advisory when displayed | MDA", "MDA", "Advisory +V",
    "LP is lateral only with an MDA; +V, when shown, is advisory.", plusv_ap, plusv_hf,
    ["Minima are LP MDA. LP is not LPV."], "LP (or LP+V)"))

# step ids
for c in cards:
    for pi, ph in enumerate(c["phases"]):
        for si, st in enumerate(ph["steps"]):
            st["id"] = f"{c['id']}-{pi}-{si}"
            # Avoid "At the FAF: At the FAF: ..." when the action repeats its own timing.
            w = st["when"]
            if w and st["action"].lower().startswith(w.lower() + ":"):
                a = st["action"][len(w) + 1:].strip()
                st["action"] = a[0].upper() + a[1:]
            if st["action"].startswith("At the FAF or the DME fix shown on the chart: "):
                st["action"] = st["action"].replace("At the FAF or the DME fix shown on the chart: ", "At the FAF (or the DME fix on the chart): ")
doc = {"title": "N63KA Perspective Approach Guides", "revision": "v5 (2026-10-06)",
       "basis": "Cirrus SR22 POH 13772-002 Reissue A (Sections 2 and 4); Perspective system software 0764.38; GFC 700 with GMC 705 mode controller. GFC 700 AFM Supplement 13772-135 and the Cockpit Reference Guide 190-00821 are not on file: verify button names and annunciations against them.",
       "cards": cards}
open("approach_cards.json", "w").write(json.dumps(doc, indent=1, ensure_ascii=False))
print(len(cards), sum(len(p["steps"]) for c in cards for p in c["phases"]), "steps")
for c in cards: print(c["id"], [ (p["title"], len(p["steps"])) for p in c["phases"]])

# ---------------------------------------------------------------- QUICK CARDS (in IMC: fly first)
# "brief" = done BEFORE the approach (enroute / on vectors). "fly" = only what you do while flying it,
# one moment per line, at most 3 short actions, with the one thing to see. Speeds from POH 4-3 / 4-21.
def q(when, do, check=None):
    return {"when": when, "do": do, "check": check}

MISSED_NOW = q("MISSED", ["Power full", "GO AROUND", "Flaps 50%"], "80 KT, climbing")
MISSED_AP = q("THEN", ["AP", "NAV", "FLC"], "ALT SEL at MAA")
MISSED_HF = q("THEN", ["Fly bars", "ALT SEL MAA"], "Missed course")

# Perspective set-up sequences (button by button). Menu wording per the Perspective Cockpit Reference
# Guide 190-00821; verify against the guide for software 0764.38.
def item(task, keys, note=None):
    return {"task": task, "keys": keys, "note": note}

LOAD = item("Load the approach", ["PROC", "FMS → SELECT APPROACH", "ENT", "FMS → approach", "ENT", "FMS → transition / VECTORS", "ENT", "ENT = LOAD"],
            "Large FMS knob moves the cursor, small knob changes the choice. Pick ACTIVATE instead of LOAD if already cleared.")
MINS = item("Set minimums", ["TMR/REF softkey", "FMS → MINIMUMS", "small FMS → BARO", "FMS → set DA/MDA", "ENT", "TMR/REF (close)"],
            "Minimums bug appears on the altimeter.")
def tune(nav):
    return item(f"Tune NAV1 to the {nav}", ["NAV knob → frequency", "NAV ⇄ swap", "Audio panel NAV1 → Morse ID"],
                "Push the small NAV knob to move the cyan tuning box between NAV1 and NAV2. Loading the approach often pre-tunes it.")
VOR_SETUP = item("Set up VOR guidance", ["CDI softkey → VOR1", "CRS knob → final course"],
                 "CDI cycles GPS → VOR1/LOC1 → VOR2/LOC2 → GPS. Push CRS to center the needle.")
ALTSEL = item("Altitude preselect", ["ALT SEL knob → altitude"], "Push ALT SEL to sync to current altitude.")
ACTIVATE = item("When cleared (if only loaded)", ["PROC", "FMS → ACTIVATE APPROACH", "ENT"])
VTF = item("If vectored to final", ["PROC", "FMS → ACTIVATE VECTOR-TO-FINAL", "ENT"], "Fly ATC headings: HDG knob, then HDG on the autopilot.")
CONFIG = item("Configure", ["Fuel pump BOOST", "Flaps 50%"], "85–90 KIAS (POH 4-3).")

def brief(nav=None, extra=()):
    b = [LOAD, MINS]
    if nav: b.append(tune(nav))
    b += list(extra) + [ACTIVATE, VTF, ALTSEL, CONFIG]
    return b

def ils_like(gs):
    ap = [q("INTERCEPT", ["APR"], "LOC" + (" GS" if gs else "") + " white"),
          q("ON FINAL", ["LOC1 on HSI?"], "CDI if not")]
    hf = [q("INTERCEPT", ["FD", "APR"], "Center LOC"),
          q("ON FINAL", ["LOC1 on HSI?"], "CDI if not")]
    if gs:
        ap += [q("GS CAPTURE", ["ALT SEL MAA", "Power back"], "LOC GS green")]
        hf += [q("GLIDESLOPE", ["Power back", "ALT SEL MAA"], "Needles centered")]
        end = [q("DA", ["AP DISC"], "Visual? Land. No? Missed."), q("DA", [], "Visual? Land. No? Missed.")]
    else:
        ap += [q("FAF", ["ALT SEL MDA", "VS −700", "Timer"], "ALTS white")]
        hf += [q("FAF", ["ALT SEL MDA", "Down 700 fpm", "Timer"])]
        end = [q("MDA", ["ALT holds"], "To MAP. Visual? AP off, land."), q("MDA", ["Level off"], "To MAP. Visual? Land.")]
    return {"autopilot": {"brief": brief("ILS" if gs else "LOC"), "fly": ap + [end[0], MISSED_NOW, MISSED_AP]},
            "manual": {"brief": brief("ILS" if gs else "LOC"), "fly": hf + [end[1], MISSED_NOW, MISSED_HF]}}

def vor_like(dme):
    extra = [VOR_SETUP] + ([item("DME fixes", ["FPL → check each DME fix is in the approach"], "GPS distance replaces DME only for fixes in the loaded approach.")] if dme else [])
    sw = q("BEFORE FAF", ["CDI → VOR1", "CRS → final", "APR"], "VOR1 green · VAPP")
    swh = q("BEFORE FAF", ["CDI → VOR1", "CRS → final"], "VOR1 green")
    faf = q("FAF" if not dme else "FAF / DME FIX", ["ALT SEL MDA", "VS −700", "Timer"], "ALTS white")
    fafh = q("FAF" if not dme else "FAF / DME FIX", ["ALT SEL MDA", "Down 700 fpm", "Timer"])
    then_ap = q("THEN", ["CDI → GPS", "AP", "NAV · FLC"], "If missed is GPS")
    then_hf = q("THEN", ["CDI → GPS", "Fly bars"], "If missed is GPS")
    return {"autopilot": {"brief": brief("VOR", extra), "fly": [sw, faf, q("MDA", ["ALT holds"], "To MAP. Visual? AP off, land."), MISSED_NOW, then_ap]},
            "manual": {"brief": brief("VOR", extra), "fly": [swh, fafh, q("MDA", ["Level off"], "To MAP. Visual? Land."), MISSED_NOW, then_hf]}}

def gps_like(ann, gp, plusv=False):
    arm = q("2 NM TO FAF", [f"{ann} on HSI?", "APR"], "GP white" if gp else "GPS green")
    armh = q("2 NM TO FAF", [f"{ann} on HSI?"], "If lower, use its mins")
    if gp:
        ap = [arm, q("GP CAPTURE", ["ALT SEL MAA", "Power back"], "GP green"), q("DA", ["AP DISC"], "Visual? Land. No? Missed.")]
        hf = [armh, q("GLIDEPATH", ["Power back", "ALT SEL MAA"], "Follow diamond"), q("DA", [], "Visual? Land. No? Missed.")]
    else:
        note = "+V advisory only" if plusv else "ALTS white"
        ap = [arm, q("FAF", ["ALT SEL MDA", "VS −700"], note), q("MDA", ["ALT holds"], "To MAP. Visual? AP off, land.")]
        hf = [armh, q("FAF", ["ALT SEL MDA", "Down 700 fpm"], "+V advisory only" if plusv else None), q("MDA", ["Level off"], "To MAP. Visual? Land.")]
    return {"autopilot": {"brief": brief(), "fly": ap + [MISSED_NOW, MISSED_AP]},
            "manual": {"brief": brief(), "fly": hf + [MISSED_NOW, MISSED_HF]}}

quick = {"ils": ils_like(True), "loc": ils_like(False), "vor": vor_like(False), "vor-dme": vor_like(True),
         "lpv": gps_like("LPV", True), "lnav-vnav": gps_like("L/VNAV", True), "lnav": gps_like("LNAV", False),
         "lnav-plus-v": gps_like("LNAV+V", False, True), "lp": gps_like("LP", False, True)}

doc = json.load(open("approach_cards.json"))
for c in doc["cards"]:
    c["quick"] = quick[c["id"]]
open("approach_cards.json", "w").write(json.dumps(doc, indent=1, ensure_ascii=False))
print("quick:", {k: (len(v["autopilot"]["fly"]), len(v["manual"]["fly"])) for k, v in quick.items()})

# ---------------------------------------------------------------- KEY REFERENCE (what each control does)
doc = json.load(open("approach_cards.json"))
doc["keyReference"] = [
 {"group": "Flight plan and procedures (PFD bezel or FMS keyboard)", "items": [
   {"key": "PROC", "does": "Procedures menu: Select Approach, Activate Approach, Activate Vector-to-Final, Activate Missed Approach"},
   {"key": "FMS knob", "does": "Large = move cursor between fields, small = change the value; push = show/hide cursor"},
   {"key": "ENT", "does": "Accept the highlighted choice"},
   {"key": "CLR", "does": "Cancel / back out; hold on the MFD for the default map"},
   {"key": "FPL", "does": "Flight plan page: check the loaded approach legs and fixes"},
   {"key": "D→ (Direct-To)", "does": "Direct to a fix (e.g. the IAF or FAF when ATC clears you)"},
 ]},
 {"group": "PFD softkeys", "items": [
   {"key": "CDI", "does": "Navigation source: GPS → VOR1/LOC1 → VOR2/LOC2 → GPS"},
   {"key": "TMR/REF", "does": "Timer (start at FAF for timed approaches) and Minimums (BARO DA/MDA)"},
   {"key": "SUSP", "does": "Appears at the MAP: press to resume sequencing into the missed approach"},
 ]},
 {"group": "Radios (PFD bezel)", "items": [
   {"key": "NAV knob", "does": "Tune the cyan standby frequency; push small knob to switch NAV1/NAV2"},
   {"key": "NAV ⇄", "does": "Swap standby to active"},
   {"key": "NAV VOL / ID", "does": "NAV audio volume; ID toggles Morse identifier audio"},
 ]},
 {"group": "Bugs (FMS keyboard)", "items": [
   {"key": "HDG knob", "does": "Heading bug; push = sync to current heading"},
   {"key": "CRS knob", "does": "Course for VOR/LOC; push = center the CDI"},
   {"key": "ALT SEL knob", "does": "Selected altitude (where the autopilot levels); push = sync to current altitude"},
 ]},
 {"group": "Autopilot (GMC 705 mode controller)", "items": [
   {"key": "AP", "does": "Engage/disengage the autopilot (turns on the flight director)"},
   {"key": "FD", "does": "Flight director command bars on/off"},
   {"key": "HDG", "does": "Follow the heading bug"},
   {"key": "NAV", "does": "Follow the CDI source (GPS, VOR, LOC) enroute"},
   {"key": "APR", "does": "Approach: arms LOC+GS, VAPP or GPS+GP depending on the approach"},
   {"key": "ALT", "does": "Hold current altitude"},
   {"key": "VS", "does": "Vertical speed; set the rate with the NOSE UP/DN wheel"},
   {"key": "FLC", "does": "Flight level change: climb/descend at a set airspeed"},
   {"key": "VNV", "does": "Vertical path to flight-plan altitudes (not for the final approach segment)"},
   {"key": "NOSE UP/DN wheel", "does": "Adjust the VS rate, FLC speed or pitch reference"},
 ]},
 {"group": "Yoke and power lever", "items": [
   {"key": "AP DISC", "does": "Autopilot disconnect (on the yoke)"},
   {"key": "GO AROUND", "does": "Power lever button: go-around pitch on the flight director, sequences the missed approach"},
 ]},
]
doc["keyReferenceNote"] = "Names per the POH panel diagram (7-75/7-76). Detailed behavior per the GFC 700 AFM Supplement 13772-135 and Cockpit Reference Guide 190-00821 (not on file): verify."
open("approach_cards.json", "w").write(json.dumps(doc, indent=1, ensure_ascii=False))
