# Engine Pulse

iPad app for aircraft owners whose avionics record engine data (Garmin and other modern engine monitors; piston first, turbine later): import engine monitor logs, learn each aircraft's normals, and get post-flight engine reports, early warnings and maintenance tracking.

Advisory only. Not FAA-approved; the POH/AFM, the engine monitor and your A&P remain the authority.

## What it does
Engine analysis: valve watch, probe check, early warning, trend charts, report card, run-up mag check, GAMI, turbo/induction checks and the A&P pre-shop report. No data about any specific aircraft ships with the app.

## App identity
- Name: Engine Pulse (App Store and home screen); repo, bundle ID and module keep the EngineMonitoring name
- Bundle ID: com.fueledconsulting.EngineMonitoring (tests: com.fueledconsulting.EngineMonitoringTests)
- Team: D64ZNA8J2P, automatic signing (Xcode Cloud manages distribution signing)
- Version 0.6.4 (11)

## Roadmap (see Multi-Aircraft-App-Plan.pdf)
1. v0.1.0 - starting code base, renamed. DONE
2. v0.2.0 - no bundled aircraft data; Aircraft Profile model and screen. DONE
3. v0.3.0 - cloud database (Supabase), Sign in with Apple, upload of profile and logs, account deletion. DONE
4. v0.4.0 - onboarding questionnaire that fills the Aircraft Profile; download logs on a new iPad.
5. v0.5.0 - several aircraft per account; G3X / EI / JPI importers.
6. External TestFlight beta, then App Store.
7. Turbine engine checks (ITT, Ng/Np, torque, start temperatures).

## Build and release
Pull request -> Xcode Cloud build check -> merge to `main` -> Xcode Cloud archive -> TestFlight. See BUILD_GUIDE.md.

## Cloud
Subscriber data is stored in Supabase (Postgres + private file storage) with row-level security. See supabase/README.md.

## Upload website
See web/README.md. Static page on the same Supabase backend; deploys from this repo.
