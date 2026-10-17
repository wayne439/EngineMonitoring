# Engine Pulse website

A static site with no build step. Drag this `web` folder onto Netlify (Site → Deploys) or deploy it from this repo with the root directory set to `web`.

| Path | Page |
|---|---|
| `/` | Home: features, how it works, avionics, pricing, demo, FAQ, join the beta |
| `/demo/` | Interactive demo on N63KA's real flights |
| `/upload/` | Upload portal (sign in with the app account; files go to Supabase) |
| `/support/` | Support (the App Store Connect Support URL) |
| `/privacy/` | Privacy Policy (the App Store Connect Privacy Policy URL) |
| `/terms/` | Terms of Use |

Shared styles and scripts are in `assets/`. The upload portal (`upload/index.html`, `app.js`, `config.js`) keeps its own styles and uses `../logo.png`.

## Sign-in links
Older app builds send confirmation and password-reset links to the site root. A script at the top of `index.html` forwards any link carrying `access_token`, `type=recovery`, `error`, or a `code` / `token_hash` query to `/upload/` with the hash and query intact.

## After deploying
1. **Supabase:** Authentication → URL Configuration → add `https://<site>/upload/` to Redirect URLs (keep the root address too).
2. **App:** set `EMWebPortalURL` in `EngineMonitoring/Info.plist` to `https://<site>/upload/` (done by the app-development chat).

## How an upload flows
1. **Pilot drops a file on a checklist item.** It's uploaded to the private `engine-logs` bucket at `<user id>/inbox/<time>-<name>`, and a row is added to `inbox_uploads` with source `web`, the category and status `received`.
2. **The app opens or comes to the front.** `CloudStore.pullInbox` downloads waiting files:
   - Engine-log CSVs are imported as flights and marked `imported`.
   - Documents are marked `stored` and listed under AIRCRAFT > Documents and uploads.
3. **Row-level security** keeps every row and file private to its owner.

`upload/config.js` holds the Supabase Project URL and anon key (the same values as the app's Info.plist). The anon key is public by design.
