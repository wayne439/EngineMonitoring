import Foundation

/// How to handle and resolve each kind of issue the app records.
/// "In flight" restates the POH procedure (APPROVED) and names the page; open the procedure in
/// PROCEDURES for the exact wording. "To resolve" lists ground checks for the pilot and the A&P
/// (TRAINING / shop guidance, not a diagnosis). Update with the shop's findings as items are closed.
enum IssuePlaybook {
    static func guide(for kind: String) -> IssueGuide {
        if let g = guides[kind] { return g }
        if let r = recordIssues.first(where: { $0.issue.kind == kind }) { return r.guide }
        if kind.hasPrefix("trend.") { return trendGuide(kind) }
        if kind.hasPrefix("technique.") { return techniqueGuide(kind) }
        if kind.hasPrefix("valve.cyl") { return valveGuide(kind) }
        if kind.hasPrefix("probe.") { return probeGuide(kind) }
        if kind.hasPrefix("early.") { return earlyGuide(kind) }
        if kind.hasPrefix("mag.") { return magGuide(kind) }
        if kind.hasPrefix("gami.") { return gamiGuide(kind) }
        if kind.hasPrefix("turbo.") { return turboGuide(kind) }
        return IssueGuide(title: "Recorded issue", meaning: "A recorded value the app flagged.", pohProcedureID: nil, pohReference: nil,
                          inFlight: ["Follow the POH procedure for any annunciation."], toResolve: ["Review the flight with your A&P."],
                          copaTopic: "Recorded issue")
    }

    private static let guides: [String: IssueGuide] = [
        // MARK: Engine start
        "start.stopped": IssueGuide(
            title: "Engine catches, then stops",
            meaning: "RPM rose above 500 and fell back below 100 within 30 seconds, followed by another start.",
            pohProcedureID: nil, pohReference: "POH 4-10 Starting Engine",
            inFlight: [
                "Warm engine: no priming. First start of the day / cold: prime (POH 4-10).",
                "Flooded (weak firing, black smoke): fuel pump OFF, mixture full LEAN, power lever full OPEN, crank; when it starts, retard power and slowly go FULL RICH (POH 4-10).",
                "Under-primed (will not fire): prime more. As soon as it fires, open the power lever slightly to keep it running (POH 4-10).",
                "Alternators OFF during the start (POH 4-10 caution).",
            ],
            toResolve: [
                "Note engine temperature, OAT and how long since shutdown for each event - a hot-start pattern points to technique, a cold one to priming.",
                "Compare your hot-start technique with a CFII (TAT turbonormalized engines are known for hard hot starts).",
                "If it happens with correct technique: ask the A&P to check the fuel injector nozzles (shown 35 hr past due on the Nov 2025 status sheet), fuel servo/mixture rigging and the boost pump.",
                "Check cranking voltage in Engine / Start history; low values point at the battery, starter or connections.",
            ],
            copaTopic: "Engine catches and then dies during start"),
        "start.extra-cranking": IssueGuide(
            title: "Extra cranking before the engine starts",
            meaning: "The starter turned the engine (RPM 100-500) one or more times without a start before the start that worked.",
            pohProcedureID: nil, pohReference: "POH 4-10 Starting Engine",
            inFlight: [
                "Follow POH 4-10: prime only when cold; use the flooded-start method if it fires weakly with black smoke.",
                "Do not crank continuously for long periods; let the starter cool between attempts (see starter limits in the POH and your A&P).",
            ],
            toResolve: [
                "Look for a pattern: hot vs cold engine, first flight of the day, after fueling.",
                "If cranking voltage is low or falling over time, have the battery capacity tested and starter/cables checked.",
                "With correct technique and good voltage, ask the A&P to check the injector nozzles and the fuel system.",
            ],
            copaTopic: "Several cranking attempts needed before the engine starts"),
        "start.oil-pressure": IssueGuide(
            title: "Slow oil pressure after start",
            meaning: "Oil pressure stayed below 10 psi for the first 30 seconds after the engine started.",
            pohProcedureID: nil, pohReference: "POH 4-10 Starting Engine",
            inFlight: [
                "POH 4-10: if oil pressure does not show within 30 s (warm weather) or about 60 s (very cold), SHUT DOWN and investigate.",
            ],
            toResolve: [
                "Check oil quantity and recent oil change records.",
                "Ask the A&P to check the oil pressure sender and wiring if the engine sounded normal.",
                "Do not fly until the cause is found.",
            ],
            copaTopic: "Oil pressure slow to rise after engine start"),

        // MARK: POH limits - engine
        "limit.rpm-max": rpmGuide, "limit.rpm-overspeed": rpmGuide,
        "limit.oilt-max": IssueGuide(
            title: "Oil temperature above 240 °F",
            meaning: "Oil temperature was above the POH red line.",
            pohProcedureID: "3-oil-temperature-high", pohReference: "POH 3-19 Oil Temperature High",
            inFlight: ["Power - REDUCE", "Airspeed - INCREASE", "Oil temperature - MONITOR", "If it remains high: land as soon as possible."],
            toResolve: [
                "Note the outside air temperature and airport: desert summer days raise oil temperature, but 240 °F is the POH limit regardless of OAT.",
                "Ask the A&P to check the oil cooler, cooler baffles/winterization plate, and oil quantity.",
                "Check the oil pressure on the same flight - both together matter more.",
                "Compare with Engine / In Flight history: one hot day or a rising trend?",
            ],
            copaTopic: "Oil temperature above 240 F"),
        "limit.oilp-max": oilPressureGuide, "limit.oilp-min": oilPressureGuide, "limit.oilp-caution": oilPressureGuide,
        "limit.oilp-idle": IssueGuide(
            title: "Low oil pressure at idle on the ground",
            meaning: "OIL PRESS caution range (10-29 psi above 1,000 RPM) while taxiing or at idle, usually with hot oil after landing.",
            pohProcedureID: "3a-low-idle-oil-pressure", pohReference: "POH 3A-6 Low Idle Oil Pressure",
            inFlight: [
                "POH 3A-6: OIL PRESS caution in flight - LAND as soon as practical.",
                "On the ground: a little more RPM clears it if pressure rises normally; it should never go below 10 psi.",
            ],
            toResolve: [
                "Look at the occurrences: after landing with hot oil at about 1,000 RPM is the common pattern.",
                "If it is happening more often or at lower pressure, ask the A&P to check idle RPM, the oil pressure relief valve setting and the oil grade (XC 20W-50).",
                "Compare with the oil temperature and oil analysis trends.",
            ],
            copaTopic: "OIL PRESS caution at idle after landing, IO-550-N"),
        "limit.cht-warning": chtGuide, "limit.cht-caution": chtGuide,

        // MARK: POH limits - electrical
        "limit.volt1-low": IssueGuide(
            title: "Bus 1 voltage low (M BUS 1 caution range)",
            meaning: "Main bus 1 was below 24.5 V for 10 s or more with the engine above 1,500 RPM.",
            pohProcedureID: "3a-low-voltage-on-main-bus-1", pohReference: "POH 3A-10 / 3A-11",
            inFlight: [
                "M BUS 1 caution: perform the ALT 1 Caution (Failure) checklist (POH 3A-10).",
                "ALT 1 circuit breaker - CHECK & SET; ALT 1 master - CYCLE (POH 3A-11).",
                "If it does not reset: ALT 1 OFF, reduce non-essential loads, continue avoiding IMC or night as able.",
            ],
            toResolve: [
                "Check whether ALT 1 was ON (low voltage right after start often means the alternator was not yet switched on).",
                "Ask the A&P to check the ALT 1 belt, output, voltage regulator and connections, and battery 1 condition.",
            ],
            copaTopic: "Main bus 1 voltage below 24.5 V with alternator 1 on"),
        "limit.volt2-low": IssueGuide(
            title: "Bus 2 voltage low (M BUS 2 caution range)",
            meaning: "Main bus 2 was below 24.5 V for 10 s or more with the engine above 1,500 RPM.",
            pohProcedureID: "3a-low-voltage-on-main-bus-2", pohReference: "POH 3A-10",
            inFlight: [
                "M BUS 2 caution: perform the ALT 1 Caution (Failure) and ALT 2 Caution (Failure) checklists (POH 3A-10).",
                "If unable to restore an alternator, reduce loads and land as soon as practical.",
            ],
            toResolve: [
                "Check whether ALT 2 was ON at the time.",
                "Ask the A&P to check ALT 2 (gear-driven standby) output, regulator and wiring.",
            ],
            copaTopic: "Main bus 2 voltage below 24.5 V"),
        "limit.volt1-high": IssueGuide(
            title: "Bus 1 voltage above 32 V",
            meaning: "Main bus 1 was above the POH red line.",
            pohProcedureID: "3-high-voltage-on-main-bus-1", pohReference: "POH 3-23",
            inFlight: ["ALT 1 master - CYCLE; M1 voltage - CHECK.", "If still above 32 V: ALT 1 OFF; perform the ALT 1 Caution (Failure) checklist; do not reset the alternator."],
            toResolve: ["Ask the A&P to check the ALT 1 voltage regulator before the next flight."],
            copaTopic: "Main bus 1 overvoltage"),
        "limit.volt2-high": IssueGuide(
            title: "Bus 2 voltage above 32 V",
            meaning: "Main bus 2 was above the POH red line.",
            pohProcedureID: "3-high-voltage-on-main-bus-2", pohReference: "POH 3-24",
            inFlight: ["Check M1 first (POH 3-24). If M2 above 32 V: ALT 2 master - CYCLE.", "If still above 32 V: ALT 2 OFF; perform the ALT 2 Caution (Failure) checklist; do not reset the alternator."],
            toResolve: ["Ask the A&P to check the ALT 2 voltage regulator before the next flight."],
            copaTopic: "Main bus 2 overvoltage"),

        // MARK: Other recorded events
        "electrical.voltage-drop": IssueGuide(
            title: "Sudden bus 1 voltage drop",
            meaning: "Bus 1 voltage fell 2 V or more within one second with the engine running.",
            pohProcedureID: "3a-low-alternator-1-output", pohReference: "POH 3A-11 if ALT 1 caution",
            inFlight: ["If ALT 1 or M BUS 1 caution: ALT 1 breaker CHECK & SET, ALT 1 master CYCLE (POH 3A-11)."],
            toResolve: [
                "Open the flight: a drop when a large load switched on (landing light, A/C, pitot heat) is expected; a drop with no switching is not.",
                "Repeated drops: ask the A&P to check alternator 1 connections, the belt and the regulator.",
            ],
            copaTopic: "Momentary bus 1 voltage drops in flight"),
        "avionics.gps-loss": IssueGuide(
            title: "GPS fix lost in flight",
            meaning: "The Perspective GPS solution changed to no solution while airborne.",
            pohProcedureID: nil, pohReference: "Perspective / GFC 700 supplement (not on file)",
            inFlight: [
                "Fly the airplane; use LOC/VOR or ATC vectors if on a GPS approach - go missed if guidance is lost.",
                "Expect the autopilot to revert from GPS-based modes; reselect HDG.",
            ],
            toResolve: [
                "Check FAA GPS interference NOTAMs for the date and area (military testing is common).",
                "If it repeats on different routes: ask the avionics shop to check GPS antennas, coax and the GIA units.",
            ],
            copaTopic: "Perspective GPS fix lost in flight"),
    ]

    private static let rpmGuide = IssueGuide(
        title: "Engine speed high",
        meaning: "RPM above 2,710 for more than 10 s or above 2,730 for more than 5 s (POH 2-8 annunciation timing).",
        pohProcedureID: "3-engine-speed-high", pohReference: "POH 3-21",
        inFlight: [
            "Tachometer - CHECK. If speed normal in flight: continue, monitor.",
            "If speed high: Propeller Governor Failure checklist - power lever ADJUST to keep RPM in limits, airspeed REDUCE to 90 KIAS, land as soon as practical.",
            "Oil pressure - CHECK.",
        ],
        toResolve: [
            "On the ground the POH says correct before flight.",
            "Ask the A&P to check the propeller governor setting and the governor oil leak noted at the Nov 2025 prebuy.",
        ],
        copaTopic: "RPM above 2,710 on takeoff or climb")

    private static let oilPressureGuide = IssueGuide(
        title: "Oil pressure out of range",
        meaning: "Oil pressure outside the POH range (below 30 psi caution / 10 psi warning above 1,000 RPM, or above 100 psi).",
        pohProcedureID: "3-oil-pressure-out-of-range", pohReference: "POH 3-19",
        inFlight: [
            "Oil pressure gage - CHECK.",
            "Low or high: power REDUCE to minimum for sustained flight; land as soon as possible; prepare for engine failure.",
        ],
        toResolve: [
            "Check oil quantity before the next flight and look for leaks (turbo wastegate and prop governor leaks were noted at the Nov 2025 prebuy).",
            "Ask the A&P to check the sender and pressure relief valve; compare with the oil analysis.",
            "If it only happens in the flare or landing roll with the power at idle and hot oil, it is the same pattern as Low Idle Oil Pressure (POH 3A-6) - show the occurrences to the A&P.",
        ],
        copaTopic: "Oil pressure out of range")

    private static let chtGuide = IssueGuide(
        title: "Cylinder head temperature high",
        meaning: "Hottest CHT above 420 °F (caution) or 460 °F (warning).",
        pohProcedureID: "3-high-cylinder-head-temperature", pohReference: "POH 3-20",
        inFlight: [
            "Power lever - REDUCE; airspeed - INCREASE; monitor.",
            "Still on: power minimum required. Caution only: land as soon as practical. Warning: land as soon as possible.",
            "On the ground: if still on after reducing power, flight is PROHIBITED.",
        ],
        toResolve: [
            "Find which cylinder: see Engine / In Flight history.",
            "Ask the A&P to check that cylinder's baffles, injector nozzle (past due Nov 2025) and probe.",
            "Climb technique: shallower climb / more airspeed, mixture per the TAT supplement.",
        ],
        copaTopic: "CHT above 420 F")

    /// Valve watch (ValveWatch): one cylinder's EGT cycling about once a minute in steady cruise.
    private static func valveGuide(_ kind: String) -> IssueGuide {
        let cyl = kind.replacingOccurrences(of: "valve.cyl", with: "")
        return IssueGuide(
            title: "Cylinder \(cyl) EGT cycling in cruise (valve watch)",
            meaning: "In steady cruise, cylinder \(cyl)'s EGT swung up and down on its own, about once a minute, while the other cylinders stayed steady. "
                + "Savvy Aviation's FEVA associates this pattern with an exhaust valve that is starting to leak (not seating fully), often well before it burns. "
                + "A loose EGT probe or connector, or a partly blocked injector on that cylinder, can look similar. Not a diagnosis.",
            pohProcedureID: nil, pohReference: nil,
            inFlight: [
                "Nothing to do unless the engine runs rough or a CHT/EGT annunciation appears; then use the POH procedure.",
                "If convenient, note whether the swing continues after a small power or mixture change - useful for the A&P.",
            ],
            toResolve: [
                "Likely causes, most to least likely: exhaust valve starting to leak (seat deposits, valve or guide wear, sticking rotator); EGT probe, clamp or connector on cylinder \(cyl); partly blocked injector.",
                "One flight can be a fluke. Two or more flights listed here: ask the A&P to borescope cylinder \(cyl), looking at the exhaust valve face and seat for an uneven or hot area.",
                "If the valve looks good, have the cylinder \(cyl) EGT probe, clamp and wiring checked.",
                "Compare with the oil analysis: nickel was 11 ppm in Apr 2026 (guide 5) and 6 ppm in Aug 2026; nickel is often linked to valve-train wear.",
                "Caught early, a leaking exhaust valve can sometimes be lapped in place instead of removing the cylinder; ask the A&P about options.",
                "Fuel injector nozzles were shown past due on the Nov 2025 status sheet; worth doing at the same visit.",
            ],
            copaTopic: "EGT on one cylinder cycling about once a minute in cruise (possible exhaust valve)")
    }

    /// Probe and wiring check (ProbeCheck): a sensor reading that a real engine cannot produce.
    private static func probeGuide(_ kind: String) -> IssueGuide {
        let name = ProbeCheck.channels.first { ProbeCheck.issueKind($0) == kind }.map(ProbeCheck.label) ?? "Engine sensor"
        let isOil = name.hasPrefix("Oil")
        let part = isOil ? "sender" : "probe"
        return IssueGuide(
            title: "\(name) \(part) or wiring",
            meaning: "The \(name) reading did something a running engine does not do on its own: blank readings, one-second spikes, "
                + "a jump that stayed while the other cylinders did not move, a stuck value, an off-scale value, or a reading far from "
                + "the other cylinders. That usually points to the \(part), its clamp, connector or wiring, not the engine. "
                + "Until it is fixed, don't rely on this reading alone (it also weakens checks that use it, such as the valve watch).",
            pohProcedureID: nil, pohReference: nil,
            inFlight: [
                "Cross-check with the other cylinders, fuel flow, oil pressure and how the engine runs. One odd reading with everything else normal points to the \(part).",
                "If the engine runs rough, power drops or other readings agree, treat it as real and use the POH procedure.",
            ],
            toResolve: [
                isOil
                    ? "Likely causes, most to least likely: loose or corroded connector at the sender; chafed or broken wire; failing sender; engine data unit (EAU) input."
                    : "Likely causes, most to least likely: loose or corroded connector at the probe; probe clamp loose or probe not seated; chafed or broken lead; failing thermocouple; engine data unit (EAU) input if several channels fail together.",
                "Ask the A&P to inspect the \(name) \(part), \(isOil ? "fitting" : "clamp"), connector and wiring.",
                isOil
                    ? "If the wiring is good, the A&P can compare with a mechanical gauge before replacing the sender."
                    : "Swapping this probe's lead with a neighbouring cylinder's shows whether the fault follows the probe or the wiring.",
                "If it comes back after the fix, have the engine data unit connections checked.",
            ],
            copaTopic: "\(name) reading glitching on the Perspective engine page (probe or wiring)")
    }

    /// Run-up mag check (MagCheck).
    private static func magGuide(_ kind: String) -> IssueGuide {
        let poh = "POH 4-14 Before Takeoff (Magnetos)"
        let inFlight = [
            "At the run-up: RPM drop must not exceed 150 RPM for either magneto; differential must not exceed 75 RPM (POH 4-14).",
            "If there is a doubt concerning operation of the ignition system, RPM checks at higher engine speeds will usually confirm whether a deficiency exists (POH 4-14).",
            "Don't take off with a mag check outside the POH limits.",
        ]
        switch kind {
        case "mag.drop", "mag.split":
            return IssueGuide(
                title: kind == "mag.drop" ? "Mag drop over 150 RPM" : "Mag drops differ by more than 75 RPM",
                meaning: "At the run-up the RPM on one magneto fell further than the POH allows, or the two magnetos differed by more than it allows. A one-off can be a fouled plug (cold, rich taxi) that clears with a lean run-up; repeated, it points at plugs, leads or magneto timing.",
                pohProcedureID: nil, pohReference: poh, inFlight: inFlight,
                toResolve: [
                    "Lean for taxi and repeat the check after a short burn-off at higher RPM (plug fouling).",
                    "If it repeats: have the A&P check the plugs (gap, fouling, cracked insulators), the ignition leads and the magneto timing.",
                    "Open DIAGNOSTICS > Run-Up Mag Check to see whether it is one mag and whether a cylinder's EGT stayed flat.",
                ],
                copaTopic: "SR22T/TN mag drop over limit at run-up")
        case "mag.one":
            return IssueGuide(
                title: "Only one mag drop recorded",
                meaning: "The run-up showed one RPM dip with the EGT rise of a single-magneto check, not two. Usually the check was quick or the drop was small; the POH notes that an absence of RPM drop may indicate faulty grounding of one side of the ignition system or timing set in advance.",
                pohProcedureID: nil, pohReference: poh, inFlight: inFlight,
                toResolve: [
                    "Next run-up: hold each mag 3-5 seconds, R then L, and watch for a drop on both.",
                    "If one mag shows no drop at all, ask the A&P to check the P-lead grounding and the magneto timing before flying.",
                ],
                copaTopic: "No RPM drop on one magneto at run-up")
        default:
            let c = String(kind.dropFirst("mag.cyl".count))
            return IssueGuide(
                title: "Cylinder \(c) not firing on one mag at run-up",
                meaning: "On one magneto, cylinder \(c)'s EGT stayed flat or fell while the other cylinders' EGTs rose. A cylinder running on a single plug gets hotter at the EGT probe; one that does not is most likely not firing on that mag: a fouled or failed plug or a bad ignition lead for that cylinder on that magneto.",
                pohProcedureID: nil, pohReference: poh, inFlight: inFlight,
                toResolve: [
                    "Open DIAGNOSTICS > Run-Up Mag Check: the table shows each cylinder's EGT rise on each mag across all run-ups.",
                    "Ask the A&P to inspect and test cylinder \(c)'s spark plug and ignition lead on that magneto (swap the plug to another position to see if the fault follows it).",
                    "If the RPM drop is normal and only the EGT stays flat, also check cylinder \(c)'s EGT probe.",
                ],
                copaTopic: "One cylinder EGT not rising on one magneto during run-up")
        }
    }

    /// GAMI lean test (GAMICheck).
    private static func gamiGuide(_ kind: String) -> IssueGuide {
        IssueGuide(
            title: "GAMI spread (fuel distribution)",
            meaning: "In a slow lean sweep, the cylinders reached peak EGT at fuel flows spread by 0.5 gph or more. GAMI's guidance: 0.5 gph or less runs smoothly lean of peak; about 1.0 gph or more means mismatched injectors, so the leanest cylinder goes lean of peak long before the richest one does.",
            pohProcedureID: nil, pohReference: nil,
            inFlight: [
                "If the engine runs rough lean of peak, enrichen to smooth operation; run rich of peak per the POH until the spread is fixed.",
                "Stay within the POH and Tornado Alley supplement limits for CHT and TIT at all times.",
            ],
            toResolve: [
                "Repeat the guided lean test once to confirm (DIAGNOSTICS > GAMI Lean Test).",
                "Ask the A&P to clean and flow-check the injectors; check the intake couplers and gaskets on the leanest cylinder.",
                "If the spread stays near 1 gph, consider a matched (GAMIjector) set from GAMI.",
            ],
            copaTopic: "SR22 TN GAMI spread over 0.5 gph")
    }

    /// Turbonormalizer and induction checks (TurboCheck).
    private static func turboGuide(_ kind: String) -> IssueGuide {
        let what: String
        let resolve: [String]
        if kind.hasPrefix("turbo.induction") {
            let c = String(kind.dropFirst("turbo.induction.cyl".count))
            what = "On consecutive flights cylinder \(c) ran much hotter than the others at low manifold pressure (descent, approach) compared with cruise, more than this aircraft's normal. A leak between the throttle and that cylinder (intake tube coupler, gasket, hose) lets in unmetered air that leans it most when manifold pressure is low."
            resolve = ["Ask the A&P to inspect cylinder \(c)'s intake tube couplers, clamps and gaskets (a soapy-water or smoke test of the induction finds leaks).",
                       "Check the cylinder \(c) injector for a partial blockage too.",
                       "DIAGNOSTICS > Turbo & Induction shows the numbers per cylinder."]
        } else if kind == "turbo.deck" {
            what = "In climb at full throttle, manifold pressure at some altitude was lower than this aircraft normally makes there. A turbonormalized engine holds about sea-level manifold pressure to its critical altitude; less points at the wastegate or its controller, or an exhaust or induction leak."
            resolve = ["Ask the A&P to inspect the wastegate and controller, the exhaust (slip joints, V-band clamps, cracks) and the induction for leaks.",
                       "Compare with the TIT1/TIT2 trend in DIAGNOSTICS > Early Warning & Trends."]
        } else {
            what = "The full-power takeoff (20 s before to 60 s after lift-off) showed lower RPM, manifold pressure or fuel flow than this aircraft normally makes. Low fuel flow means less cooling fuel at full power; low MAP points at the turbonormalizer or a leak; low RPM at the propeller governor."
            resolve = ["Make sure the mixture was full rich / set per the POH for the takeoff.",
                       "Fuel flow low: have the fuel servo, flow divider, injectors and mixture rigging checked.",
                       "MAP low: wastegate, controller, exhaust and induction leaks. RPM low: governor high-RPM stop."]
        }
        return IssueGuide(
            title: "Turbonormalizer or induction: " + (kind.hasPrefix("turbo.induction") ? "lean cylinder at low power" : kind == "turbo.deck" ? "manifold pressure low in climb" : "takeoff power low"),
            meaning: what,
            pohProcedureID: nil, pohReference: "POH 4-16 Takeoff Power Check",
            inFlight: [
                "Check full-throttle engine operation early in the takeoff run; discontinue the takeoff at any sign of rough operation or sluggish acceleration (POH 4-16).",
                "Turbonormalizer limits: follow the Tornado Alley AFM supplement.",
            ],
            toResolve: resolve,
            copaTopic: "SR22 Tornado Alley turbonormalized: " + (kind.hasPrefix("turbo.induction") ? "induction leak suspected" : "low manifold pressure / takeoff power"))
    }

    /// Early warning (EarlyWarning): a value drifting across flights before it reaches a limit.
    private static func earlyGuide(_ kind: String) -> IssueGuide {
        let id = String(kind.dropFirst("early.".count))
        let metric = TrendMetric.named(id)
        let name = metric?.label ?? "Engine value"
        let advice: String
        switch metric?.group {
        case .cylinders?: advice = "Check baffles and seals near this cylinder and its CHT probe; compare with the oil analysis. If its EGT is also moving away from the others, suspect the injector, an intake leak or timing."
        case .balance?: advice = "Check that cylinder's injector (clean/flow) and intake coupling; a GAMI lean test shows fuel distribution. If Probes & Wiring flagged the probe, fix that first."
        case .valves?: advice = "Ask the A&P to borescope the exhaust valve of this cylinder."
        case .oil?: advice = id == "oilp" ? "Check oil quantity and leaks, then the pressure relief setting and sender; watch iron and copper in the oil analysis." : "Check the oil cooler and its baffles/winterization plate; compare with the oil analysis."
        case .turbo?: advice = "Inspect the exhaust and turbo system (leaks, wastegate) and both TIT probes."
        case .electrical?: advice = "Have the alternator output, voltage regulator, battery and connections checked."
        case nil: advice = "Review the trend with your A&P."
        }
        return IssueGuide(
            title: "Early warning: \(name)",
            meaning: "Across this aircraft's recent flights this value has moved outside its normal or is trending the wrong way, after correcting for outside air temperature and fuel flow. "
                + "Nothing has reached a limit; the warning is meant to give time to look before it does. Open DIAGNOSTICS > Early Warning & Trends for the chart and the hours left at the current rate.",
            pohProcedureID: nil, pohReference: nil,
            inFlight: [
                "Nothing to do unless a CAS annunciation appears; then use the POH procedure.",
                "Fly normal power settings so the next flights are comparable; note anything unusual with an event marker.",
            ],
            toResolve: [
                advice,
                "Once a fix is done, record it in the issue review; the warning clears when the newest flights are back within normal.",
            ],
            copaTopic: "\(name) slowly trending the wrong way over several flights")
    }

    private static func techniqueGuide(_ kind: String) -> IssueGuide {
        let id = String(kind.dropFirst("technique.".count))
        let label = AircraftKnowledge.limits.first { $0.id == id }?.label ?? "Technique reference exceeded"
        return IssueGuide(
            title: "Technique: " + (label.components(separatedBy: " (").first ?? label),
            meaning: "\(label). This is an operating-technique reference (Jim Barker flight profile), not a POH limit.",
            pohProcedureID: nil, pohReference: nil,
            inFlight: ["Climb: add airspeed, use boost pump per the TAT supplement, or enrich - as your CFII taught."],
            toResolve: ["Review your climb profile with a CFII familiar with TAT turbonormalized SR22s.",
                        "Approved TIT limits need the Tornado Alley AFM supplement (not on file)."],
            copaTopic: "Turbonormalized SR22 climb CHT and TIT technique")
    }

    private static func trendGuide(_ kind: String) -> IssueGuide {
        let parts = kind.split(separator: ".").map(String.init)
        let phase = parts.count > 1 ? parts[1] : ""
        let high = parts.last == "high"
        let metric = parts.count > 2 ? (parts[2] == "cht" ? FlightMetric.chtMax : FlightMetric(rawValue: parts[2])) : nil
        let name = parts.count > 2 && parts[2] == "cht" ? "CHT" : (metric?.sentenceLabel ?? "value")
        var poh: (String?, String?) = (nil, nil)
        var checks = ["Compare with the oil analysis and the shop's last inspection.", "If the trend continues over several flights, show the history to your A&P."]
        switch metric {
        case .oilTemp?: poh = ("3-oil-temperature-high", "POH 3-19 if OIL TEMP warning")
            checks.insert("Already compared with this aircraft's flights at a similar outside air temperature, so a hot day alone does not trigger this. If it repeats, ask the A&P to check the oil cooler, cooler baffles and winterization plate.", at: 0)
        case .oilPressure?: poh = ("3-oil-pressure-out-of-range", "POH 3-19 if OIL PRESS warning")
            checks.insert("Check oil quantity and for leaks.", at: 0)
        case .chtMax?, .cht1?, .cht2?, .cht3?, .cht4?, .cht5?, .cht6?: poh = ("3-high-cylinder-head-temperature", "POH 3-20 if CHT annunciation")
            checks.insert("Compared with this aircraft's flights at a similar outside air temperature. Check that cylinder's baffles, injector nozzle and probe.", at: 0)
        case .egtSpread?: checks.insert("A widening EGT spread can come from an injector, intake leak or probe: ask the A&P about a GAMI spread check and nozzle cleaning (past due Nov 2025).", at: 0)
        case .volt1?, .volt2?: poh = ("3a-low-voltage-on-main-bus-1", "POH 3A-10 if M BUS caution")
            checks.insert("Have the battery and alternator output checked.", at: 0)
        default: break
        }
        return IssueGuide(
            title: "Trend: \(phase.lowercased()) \(name) \(high ? "higher" : "lower") than usual",
            meaning: "The median for this phase was well outside the range of this aircraft's other flights (10th-90th percentile). Not a limit; a change worth watching.",
            pohProcedureID: poh.0, pohReference: poh.1,
            inFlight: ["Nothing to do unless an annunciation appears; then use the POH procedure."],
            toResolve: checks,
            copaTopic: "\(phase) \(name) \(high ? "higher" : "lower") than usual")
    }

    // MARK: - Items from the maintenance records (SharePoint Cirrus/Records)

    /// Issues raised by the aircraft's own records (open squawks, oil analysis). Nothing is bundled;
    /// these will come from the owner's records in a later version.
    static let recordIssues: [(issue: FlightIssue, guide: IssueGuide)] = []
}
