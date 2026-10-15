# Engine Monitoring

iPad app for piston aircraft owners: import engine monitor logs, learn each aircraft's normals, and get post-flight engine reports, early warnings and maintenance tracking.

Advisory only. Not FAA-approved; the POH/AFM, the engine monitor and your A&P remain the authority.

## Origin
Started on 2026-10-15 as a copy of N63KA Copilot `main` at 003a563 (v0.9.7: valve watch, probe check, early warning, trend charts, report card, run-up mag check, GAMI, turbo/induction checks, A&P pre-shop report). N63KA Copilot remains a separate private app.

## App identity
- Name: Engine Monitoring (working name)
- Bundle ID: com.fueledconsulting.EngineMonitoring (tests: com.fueledconsulting.EngineMonitoringTests)
- Team: D64ZNA8J2P, automatic signing (Xcode Cloud manages distribution signing)
- Version 0.2.0 (2)

## Roadmap (see Multi-Aircraft-App-Plan.pdf)
1. v0.1.0 - copy of N63KA Copilot, renamed. DONE
2. v0.2.0 - remove bundled N63KA data (flight history, normals, POH text, approach cards); AircraftProfile model and screen. DONE
3. v0.3.0 - Sign in with Apple, onboarding questionnaire, account deletion.
4. v0.4.0 - multi-aircraft import (Garmin Perspective / G1000 CSV), per-aircraft baselines.
5. External TestFlight beta, then App Store.

## Build and release
Pull request -> Xcode Cloud build check -> merge to `main` -> Xcode Cloud archive -> TestFlight. See BUILD_GUIDE.md (carried over from N63KA Copilot; paths renamed).
