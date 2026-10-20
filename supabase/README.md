# Engine Pulse cloud backend (Supabase)

Each subscriber signs in with Apple. Their aircraft profile, engine logs and flight summaries are stored in a Postgres database and a private file bucket, and row-level security lets each subscriber see only their own data.

## One-time setup (about 15 minutes)

1. **Create the project**
   - Sign up at supabase.com and create a project named `engineai`. Pick the US West region, set a strong database password and save it in your password manager.
2. **Create the tables, bucket and security rules**
   - In the dashboard, open **SQL Editor → New query**. Paste all of `schema.sql`, click **Run**, and check that it reports "Success".
3. **Turn on Sign in with Apple**
   - Go to **Authentication → Sign In / Providers → Apple** and turn it on.
   - In **Client IDs**, enter `com.fueledconsulting.EngineMonitoring`.
   - Leave the secret key empty. The native iOS sign-in doesn't use it.
4. **Copy the keys into the app**
   - Go to **Project Settings → API**. Copy the **Project URL** and the **anon public** key.
   - Put them in `EngineMonitoring/Info.plist` under `EMSupabaseURL` and `EMSupabaseAnonKey`, or send them to Claude to commit.
   - The anon key is meant to ship inside apps: row-level security is what protects the data.
   - Never put the **service_role** key in the app.

While those two Info.plist values are blank, the app runs in local-only mode and the ACCOUNT screen says so.

## Email templates (codes instead of links)
The app confirms accounts and resets passwords with a **6-digit code** the pilot types in, so no web page is needed.
1. Go to **Authentication → Emails → Templates**.
2. **Confirm signup:** set the subject to `Your Engine Pulse code` and replace the message body with `email-templates/confirm-signup.html`.
3. **Reset Password:** set the subject to `Reset your Engine Pulse password` and replace the body with `email-templates/reset-password.html`.
4. Click **Save** on each.

Leave the **Magic Link** template as a link: the app's "Email me an upload link" uses it to sign pilots in to the upload website with one click. Under **Authentication → URL Configuration**, add the website address to **Redirect URLs**.

Supabase's built-in email sender is only for testing: it sends a few emails per hour. Before inviting beta testers, add your own sender under **Authentication → Emails → SMTP Settings**, for example Resend or Postmark with an enginepulse.net address (for example noreply@enginepulse.net).

## What is stored

| Where | What |
| --- | --- |
| `aircraft` table | One row per airplane: tail, make/model, engine, monitor, plus the full Aircraft Profile as JSON |
| `flight_logs` table | One row per uploaded log: times, sample count, file path, and the flight summary the app computed |
| `inbox_uploads` table | Files received but not yet turned into flights: formats the app cannot read yet (JPI, EI), and later flyGarmin / AirSync / email / web uploads |
| `engine-logs` bucket | The raw log files, under `<user id>/<aircraft id>/<file name>` (private, 50 MB per file limit) |

| `aircraft_transfers` table | Sales: the seller's transfer of an aircraft to a buyer's email and cell, with the hash of the texted code (never the code itself) |

## Aircraft transfers (selling the airplane)

The seller starts a transfer in ACCOUNT (or AIRCRAFT) with the buyer's email and cell number. The app uploads any flights not in the cloud yet and a copy of the maintenance, issue reviews and event markers, then texts the buyer an 8-character code and emails the steps. The buyer signs in to Engine Pulse with that email (confirmed), goes to ACCOUNT → Accept a transfer and enters the code and their cell number. `accept_aircraft_transfer()` then moves the aircraft, its flight logs and its documents to the buyer. The raw files stay in the seller's folder: the storage rules let whoever owns the rows read them, and stop the seller changing or deleting them. Codes expire after 14 days, and five wrong tries cancel the transfer. The buyer's account may hold no other aircraft with flights (one aircraft per account for now).

**To switch it on:** run the whole of `schema.sql` again in the SQL Editor (it is safe to re-run). Until then the app says transfers aren't switched on.

Deleting an account (ACCOUNT → Delete account) removes the files, then calls `delete_my_account()`. That deletes the user, and their rows go with it.

## Testing the schema locally

`tests/` holds a small stand-in for Supabase's `auth` and `storage` schemas plus row-level-security tests. With a local Postgres 16:

```
createdb emtest
psql -d emtest -f tests/supabase_stub.sql -f schema.sql -f tests/rls_test.sql
```

The last line printed should be `ALL RLS TESTS PASSED`. The transfer tests run the same way on a fresh database:

```
createdb emtransfer
psql -d emtransfer -f tests/supabase_stub.sql -f schema.sql -f tests/transfer_test.sql
```

and end with `ALL TRANSFER TESTS PASSED`. The tests check that:
- one pilot can't see, change, delete or attach to another pilot's aircraft, logs or files;
- account deletion removes only that pilot's data.
