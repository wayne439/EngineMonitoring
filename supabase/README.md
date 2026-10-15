# AI Engine Monitoring cloud backend (Supabase)

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

## What is stored

| Where | What |
| --- | --- |
| `aircraft` table | One row per airplane: tail, make/model, engine, monitor, plus the full Aircraft Profile as JSON |
| `flight_logs` table | One row per uploaded log: times, sample count, file path, and the flight summary the app computed |
| `inbox_uploads` table | Files received but not yet turned into flights: formats the app cannot read yet (JPI, EI), and later flyGarmin / AirSync / email / web uploads |
| `engine-logs` bucket | The raw log files, under `<user id>/<aircraft id>/<file name>` (private, 50 MB per file limit) |

Deleting an account (ACCOUNT → Delete account) removes the files, then calls `delete_my_account()`. That deletes the user, and their rows go with it.

## Testing the schema locally

`tests/` holds a small stand-in for Supabase's `auth` and `storage` schemas plus row-level-security tests. With a local Postgres 16:

```
createdb emtest
psql -d emtest -f tests/supabase_stub.sql -f schema.sql -f tests/rls_test.sql
```

The last line printed should be `ALL RLS TESTS PASSED`. The tests check that:
- one pilot can't see, change, delete or attach to another pilot's aircraft, logs or files;
- account deletion removes only that pilot's data.
