# Engine Pulse upload website

A single static page (`index.html`, `app.js`, `config.js`, `logo.png`) where pilots sign in with the same account as the app and upload their engine logs and documents. Uploads go to the same Supabase project as the app. The app brings them in whenever it opens.

## How a file flows
1. **Pilot drops a file on a checklist item.** It's uploaded to the private `engine-logs` bucket at `<user id>/inbox/<time>-<name>`, and a row is added to `inbox_uploads` with source `web`, the category and status `received`.
2. **The app opens or comes to the front.** `CloudStore.pullInbox` downloads waiting files:
   - Engine-log CSVs are imported as flights and marked `imported`.
   - Documents are marked `stored` and listed under AIRCRAFT > Documents and uploads.
3. **Row-level security** keeps every row and file private to its owner.

## Turn it on
1. **Fill in `config.js`** with the Supabase Project URL and anon key (the same values as the app's Info.plist).
2. **Host the `web` folder** on any static host. The easiest option is one that deploys from this GitHub repo on every merge:
   - **Cloudflare Pages** or **Vercel**: New project → import `wayne439/EngineMonitoring` → root directory `web` → no build command → deploy.
   - Then add your domain, for example `app.aienginemonitoring.com`.
3. **Point Supabase at the site:** go to Authentication → URL Configuration, set the **Site URL** to the website address, and add it to **Redirect URLs**. Password-reset and confirmation emails then link back to the site.
4. **Point the app at the site:** set `EMWebPortalURL` in `EngineMonitoring/Info.plist` to the same address, so the app's Documents screen links to it.

## Testing
The page was tested in a headless browser against a stand-in for Supabase. The test covered registering, logging in, the checklist, uploading a file (bucket path and `inbox_uploads` row) and the uploads list.
