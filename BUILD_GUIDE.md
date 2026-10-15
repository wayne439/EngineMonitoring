# Engine Monitoring build guide

## Repository
- GitHub: wayne439/EngineMonitoring (private), branch `main`.
- Xcode project: `EngineMonitoring.xcodeproj`, scheme `EngineMonitoring`, targets `EngineMonitoring` (app) and `EngineMonitoringTests`.
- `project.yml` mirrors the project for XcodeGen; the checked-in `.xcodeproj` is the source of truth.

## App identity
- Bundle ID `com.fueledconsulting.EngineMonitoring`, team D64ZNA8J2P, automatic signing.
- Capabilities: Sign in with Apple (entitlements file `EngineMonitoring/EngineMonitoring.entitlements`).

## Release flow
1. Work happens on a `feat/...` branch; a pull request is opened against `main`.
2. Xcode Cloud builds the pull request (compile check).
3. Merge to `main`; Xcode Cloud archives and uploads to TestFlight (internal group).
4. Install from TestFlight.

Xcode Cloud sets its own build number, so TestFlight shows its run counter; go by the marketing version (0.x.y).

## Cloud backend
See `supabase/README.md`: create the Supabase project, run the SQL in `supabase/schema.sql`, enable Apple sign-in, then put the project URL and anon key in `EngineMonitoring/Info.plist` (`EMSupabaseURL`, `EMSupabaseAnonKey`). With those keys blank the app runs in local-only mode.
