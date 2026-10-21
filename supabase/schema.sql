-- Engine Pulse: cloud database schema (Supabase / Postgres).
-- Run once in the Supabase dashboard: SQL Editor > New query > paste this file > Run.
-- Safe to re-run: every statement checks whether its object already exists.
--
-- What it stores, per subscriber (auth.users row = one subscriber):
--   aircraft     one row per airplane the subscriber sets up (the app's Aircraft Profile)
--   flight_logs  one row per uploaded engine log, with the flight summary the app computed
--   storage      the raw engine log files, in the private "engine-logs" bucket,
--                under <user id>/<aircraft id>/<file name>
-- Row-level security makes every row and file visible only to the subscriber who owns it.

-- ---------------------------------------------------------------- aircraft
create table if not exists public.aircraft (
    id                uuid primary key default gen_random_uuid(),
    owner_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
    tail_number       text not null default '',
    make              text not null default '',
    model             text not null default '',
    year              integer,
    engine_model      text not null default '',
    cylinders         integer not null default 6 check (cylinders between 1 and 12),
    is_turbocharged   boolean not null default false,
    monitor           text not null default '',
    limits_confirmed  boolean not null default false,
    -- The complete Aircraft Profile exactly as the app saves it (limits, references, settings).
    profile           jsonb not null default '{}'::jsonb,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now()
);

create index if not exists aircraft_owner_idx on public.aircraft (owner_id);

-- ---------------------------------------------------------------- flight_logs
create table if not exists public.flight_logs (
    id                 uuid primary key default gen_random_uuid(),
    owner_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
    aircraft_id        uuid not null references public.aircraft (id) on delete cascade,
    filename           text not null,
    original_filename  text not null,
    started_at         timestamptz not null,
    ended_at           timestamptz not null,
    sample_count       integer not null default 0,
    airframe_name      text,
    system_id          text,
    -- Path of the raw file in the engine-logs bucket.
    storage_path       text not null,
    size_bytes         bigint,
    -- The per-flight summary the app computed (phases, stats, issues, engine checks).
    summary            jsonb,
    uploaded_at        timestamptz not null default now(),
    unique (aircraft_id, filename)
);

create index if not exists flight_logs_owner_idx on public.flight_logs (owner_id);
create index if not exists flight_logs_aircraft_started_idx on public.flight_logs (aircraft_id, started_at desc);

-- ---------------------------------------------------------------- inbox_uploads
-- Every file that arrives for a subscriber before it becomes a flight: files shared to the app in a
-- format it cannot read yet (JPI, EI), and later uploads from flyGarmin / PlaneSync, AirSync, email-in
-- and the web. A processing job turns them into flight_logs rows.
create table if not exists public.inbox_uploads (
    id                 uuid primary key default gen_random_uuid(),
    owner_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
    aircraft_id        uuid references public.aircraft (id) on delete set null,
    source             text not null default 'app'
                       check (source in ('app', 'share', 'sd-card', 'email', 'web', 'flygarmin', 'airsync', 'cirrus-iq')),
    original_filename  text not null,
    storage_path       text not null,
    size_bytes         bigint,
    format             text not null default 'unknown',   -- garmin-csv, jpi, ei, pdf, image, unknown
    -- Which checklist item the file answers (see the app's data checklist and the web upload page).
    category           text not null default 'logs',
    -- received: waiting for the app; imported: became a flight; stored: kept as a document;
    -- unsupported: format not readable yet; failed: could not be read.
    status             text not null default 'received',
    detail             text,
    received_at        timestamptz not null default now(),
    processed_at       timestamptz
);

-- Columns and rules added after the first release (safe to re-run on an existing database).
alter table public.inbox_uploads add column if not exists category text not null default 'logs';
alter table public.inbox_uploads drop constraint if exists inbox_uploads_status_check;
alter table public.inbox_uploads add constraint inbox_uploads_status_check
    check (status in ('received', 'processing', 'imported', 'stored', 'unsupported', 'failed'));
alter table public.inbox_uploads drop constraint if exists inbox_uploads_category_check;
alter table public.inbox_uploads add constraint inbox_uploads_category_check
    check (category in ('logs', 'poh-limits', 'logbook', 'engine-time', 'oil-analysis', 'squawks', 'turbo', 'other'));

create index if not exists inbox_uploads_owner_idx on public.inbox_uploads (owner_id, received_at desc);
create index if not exists inbox_uploads_status_idx on public.inbox_uploads (status) where status in ('received', 'processing');

-- ---------------------------------------------------------------- updated_at
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists aircraft_updated_at on public.aircraft;
create trigger aircraft_updated_at before update on public.aircraft
    for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------- row-level security
alter table public.aircraft enable row level security;
alter table public.flight_logs enable row level security;

drop policy if exists "aircraft: owner only" on public.aircraft;
create policy "aircraft: owner only" on public.aircraft
    for all to authenticated
    using (owner_id = auth.uid())
    with check (owner_id = auth.uid());

alter table public.inbox_uploads enable row level security;

drop policy if exists "inbox_uploads: owner only" on public.inbox_uploads;
create policy "inbox_uploads: owner only" on public.inbox_uploads
    for all to authenticated
    using (owner_id = auth.uid())
    with check (
        owner_id = auth.uid()
        and (aircraft_id is null or exists (select 1 from public.aircraft a where a.id = aircraft_id and a.owner_id = auth.uid()))
    );

drop policy if exists "flight_logs: owner only" on public.flight_logs;
create policy "flight_logs: owner only" on public.flight_logs
    for all to authenticated
    using (owner_id = auth.uid())
    with check (
        owner_id = auth.uid()
        and exists (select 1 from public.aircraft a where a.id = aircraft_id and a.owner_id = auth.uid())
    );

-- ---------------------------------------------------------------- file storage
insert into storage.buckets (id, name, public, file_size_limit)
values ('engine-logs', 'engine-logs', false, 52428800)   -- private; 50 MB per file
on conflict (id) do nothing;

-- Files live under <user id>/..., so the first folder of the path must be the caller's id.
drop policy if exists "engine-logs: owner read" on storage.objects;
create policy "engine-logs: owner read" on storage.objects
    for select to authenticated
    using (bucket_id = 'engine-logs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "engine-logs: owner insert" on storage.objects;
create policy "engine-logs: owner insert" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'engine-logs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "engine-logs: owner update" on storage.objects;
create policy "engine-logs: owner update" on storage.objects
    for update to authenticated
    using (bucket_id = 'engine-logs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "engine-logs: owner delete" on storage.objects;
create policy "engine-logs: owner delete" on storage.objects
    for delete to authenticated
    using (bucket_id = 'engine-logs' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------- account deletion
-- Apple requires in-app account deletion. The app first deletes the user's files through the
-- Storage API (Supabase does not allow deleting storage objects from SQL), then calls this
-- function, which deletes the auth user; aircraft and flight_logs rows go with it (on delete cascade).
create or replace function public.delete_my_account() returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'not signed in';
    end if;
    delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------- aircraft transfer (sale)
-- When an airplane is sold, the current owner starts a transfer in the app with the buyer's email and
-- cell phone number. The app texts the buyer a transfer code. The buyer signs in to Engine Pulse with
-- that email, enters the code and their cell number, and accept_aircraft_transfer() moves the aircraft,
-- its flight logs and its documents to the buyer's account. The raw files stay where they are; the
-- storage rules below let whoever owns the rows read them, and stop the seller deleting them.
create table if not exists public.aircraft_transfers (
    id               uuid primary key default gen_random_uuid(),
    aircraft_id      uuid not null references public.aircraft (id) on delete cascade,
    from_owner       uuid default auth.uid() references auth.users (id) on delete set null,
    tail_number      text not null default '',
    to_email         text not null check (to_email = lower(btrim(to_email)) and position('@' in to_email) > 1),
    to_phone         text not null check (to_phone ~ '^[0-9]{7,15}$'),
    -- sha256 (hex) of the transfer code, upper-cased with spaces and dashes removed. The code itself is never stored.
    code_hash        text not null check (code_hash ~ '^[0-9a-f]{64}$'),
    -- Snapshot of the seller's maintenance, issue reviews and event markers for this aircraft.
    state_path       text,
    status           text not null default 'pending' check (status in ('pending', 'accepted', 'cancelled', 'expired')),
    failed_attempts  integer not null default 0,
    created_at       timestamptz not null default now(),
    expires_at       timestamptz not null default now() + interval '14 days',
    accepted_at      timestamptz,
    accepted_by      uuid references auth.users (id) on delete set null
);

create unique index if not exists aircraft_transfers_one_pending on public.aircraft_transfers (aircraft_id) where status = 'pending';
create index if not exists aircraft_transfers_email_idx on public.aircraft_transfers (to_email) where status = 'pending';
create index if not exists flight_logs_storage_path_idx on public.flight_logs (storage_path);
create index if not exists inbox_uploads_storage_path_idx on public.inbox_uploads (storage_path);

alter table public.aircraft_transfers enable row level security;

-- The seller sees their transfers; the buyer sees the ones they accepted.
drop policy if exists "aircraft_transfers: seller or buyer read" on public.aircraft_transfers;
create policy "aircraft_transfers: seller or buyer read" on public.aircraft_transfers
    for select to authenticated
    using (from_owner = auth.uid() or accepted_by = auth.uid());

-- Only the aircraft's current owner can start a transfer, and only as a fresh pending one.
drop policy if exists "aircraft_transfers: owner starts" on public.aircraft_transfers;
create policy "aircraft_transfers: owner starts" on public.aircraft_transfers
    for insert to authenticated
    with check (
        from_owner = auth.uid()
        and status = 'pending' and failed_attempts = 0 and accepted_at is null and accepted_by is null
        and expires_at <= now() + interval '15 days'
        and exists (select 1 from public.aircraft a where a.id = aircraft_id and a.owner_id = auth.uid())
        and (state_path is null or state_path like auth.uid()::text || '/%')
    );

-- While pending, the seller can refresh the snapshot or cancel. Nothing else can be changed directly.
drop policy if exists "aircraft_transfers: seller updates pending" on public.aircraft_transfers;
create policy "aircraft_transfers: seller updates pending" on public.aircraft_transfers
    for update to authenticated
    using (from_owner = auth.uid() and status = 'pending')
    with check (from_owner = auth.uid() and status in ('pending', 'cancelled')
                and (state_path is null or state_path like auth.uid()::text || '/%'));

revoke update, delete, truncate on public.aircraft_transfers from authenticated, anon;
revoke all on public.aircraft_transfers from anon;
grant select, insert on public.aircraft_transfers to authenticated;
grant update (status, state_path) on public.aircraft_transfers to authenticated;

-- A row's file path is set by the app, so it must point into the caller's own folder when written,
-- and it can't be repointed later (rows moved to a buyer keep pointing at the seller's folder).
create or replace function public.check_storage_path() returns trigger
language plpgsql as $$
begin
    if auth.uid() is null then
        return new;   -- service jobs
    end if;
    if tg_op = 'UPDATE' and new.storage_path = old.storage_path then
        return new;
    end if;
    if new.storage_path not like auth.uid()::text || '/%' then
        raise exception 'storage_path must be in your own folder' using errcode = '42501';
    end if;
    return new;
end;
$$;

drop trigger if exists flight_logs_storage_path on public.flight_logs;
create trigger flight_logs_storage_path before insert or update on public.flight_logs
    for each row execute function public.check_storage_path();
drop trigger if exists inbox_uploads_storage_path on public.inbox_uploads;
create trigger inbox_uploads_storage_path before insert or update on public.inbox_uploads
    for each row execute function public.check_storage_path();

-- Whether a file belongs to the caller's rows, or to someone else's (security definer: it has to see
-- other users' rows to answer, but only returns true or false).
create or replace function public.engine_file_is_mine(path text) returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (select 1 from public.flight_logs where storage_path = path and owner_id = auth.uid())
        or exists (select 1 from public.inbox_uploads where storage_path = path and owner_id = auth.uid())
        or exists (select 1 from public.aircraft_transfers where state_path = path and accepted_by = auth.uid() and status = 'accepted')
$$;

create or replace function public.engine_file_is_others(path text) returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (select 1 from public.flight_logs where storage_path = path and owner_id <> auth.uid())
        or exists (select 1 from public.inbox_uploads where storage_path = path and owner_id <> auth.uid())
        or exists (select 1 from public.aircraft_transfers where state_path = path and accepted_by <> auth.uid() and status = 'accepted')
$$;

revoke all on function public.engine_file_is_mine(text), public.engine_file_is_others(text) from public, anon;
grant execute on function public.engine_file_is_mine(text), public.engine_file_is_others(text) to authenticated;

-- Storage rules, replacing the folder-only ones above: you can read, change and delete your own folder
-- and any file your rows point at (an aircraft you bought), except files that now belong to someone
-- else's rows (an aircraft you sold).
drop policy if exists "engine-logs: owner read" on storage.objects;
create policy "engine-logs: owner read" on storage.objects
    for select to authenticated
    using (bucket_id = 'engine-logs'
           and (((storage.foldername(name))[1] = auth.uid()::text and not public.engine_file_is_others(name))
                or public.engine_file_is_mine(name)));

drop policy if exists "engine-logs: owner update" on storage.objects;
create policy "engine-logs: owner update" on storage.objects
    for update to authenticated
    using (bucket_id = 'engine-logs'
           and ((storage.foldername(name))[1] = auth.uid()::text or public.engine_file_is_mine(name))
           and not public.engine_file_is_others(name));

drop policy if exists "engine-logs: owner delete" on storage.objects;
create policy "engine-logs: owner delete" on storage.objects
    for delete to authenticated
    using (bucket_id = 'engine-logs'
           and ((storage.foldername(name))[1] = auth.uid()::text or public.engine_file_is_mine(name))
           and not public.engine_file_is_others(name));

-- The buyer accepts. Checks the signed-in (confirmed) email, the code and the cell number, then moves
-- the aircraft and everything recorded for it. Five wrong tries cancel the transfer.
-- Returns {"ok": true, "aircraft_id", "tail_number", "state_path"} or {"ok": false, "reason"}, where reason is
-- unconfirmed, none, mismatch, locked, self or has_aircraft.
create or replace function public.accept_aircraft_transfer(transfer_code text, phone text) returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    me uuid := auth.uid();
    my_email text;
    t public.aircraft_transfers;
    digits text := right(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), 10);
    hash text := encode(sha256(convert_to(upper(regexp_replace(coalesce(transfer_code, ''), '[^A-Za-z0-9]', '', 'g')), 'UTF8')), 'hex');
    locked boolean := false;
begin
    if me is null then
        raise exception 'not signed in';
    end if;
    select lower(email) into my_email from auth.users where id = me and email_confirmed_at is not null;
    if my_email is null then
        return jsonb_build_object('ok', false, 'reason', 'unconfirmed');
    end if;

    update public.aircraft_transfers set status = 'expired' where status = 'pending' and expires_at < now();

    select * into t from public.aircraft_transfers
     where status = 'pending' and to_email = my_email and code_hash = hash
     order by created_at desc limit 1
     for update;

    if not found or right(t.to_phone, 10) <> digits then
        with bumped as (
            update public.aircraft_transfers
               set failed_attempts = failed_attempts + 1,
                   status = case when failed_attempts + 1 >= 5 then 'cancelled' else status end
             where status = 'pending' and to_email = my_email
            returning status)
        select bool_or(status = 'cancelled') into locked from bumped;
        if not exists (select 1 from public.aircraft_transfers where to_email = my_email and status in ('pending', 'cancelled')
                       and created_at > now() - interval '15 days') then
            return jsonb_build_object('ok', false, 'reason', 'none');
        end if;
        return jsonb_build_object('ok', false, 'reason', case when coalesce(locked, false) then 'locked' else 'mismatch' end);
    end if;

    if t.from_owner = me then
        return jsonb_build_object('ok', false, 'reason', 'self');
    end if;
    if not exists (select 1 from public.aircraft where id = t.aircraft_id and owner_id = t.from_owner) then
        update public.aircraft_transfers set status = 'cancelled' where id = t.id;
        return jsonb_build_object('ok', false, 'reason', 'none');
    end if;

    -- One aircraft per account for now: an aircraft the buyer already has flights or documents for
    -- blocks the transfer; an empty one (made while registering) is replaced.
    if exists (select 1 from public.aircraft a where a.owner_id = me
               and (exists (select 1 from public.flight_logs f where f.aircraft_id = a.id)
                    or exists (select 1 from public.inbox_uploads i where i.aircraft_id = a.id))) then
        return jsonb_build_object('ok', false, 'reason', 'has_aircraft',
            'tail_number', (select tail_number from public.aircraft where owner_id = me order by created_at limit 1));
    end if;
    delete from public.aircraft where owner_id = me;

    update public.aircraft set owner_id = me where id = t.aircraft_id;
    update public.flight_logs set owner_id = me where aircraft_id = t.aircraft_id;
    update public.inbox_uploads set owner_id = me where aircraft_id = t.aircraft_id;
    update public.aircraft_transfers set status = 'accepted', accepted_at = now(), accepted_by = me where id = t.id;

    return jsonb_build_object('ok', true, 'aircraft_id', t.aircraft_id, 'tail_number', t.tail_number, 'state_path', t.state_path);
end;
$$;

revoke all on function public.accept_aircraft_transfer(text, text) from public, anon;
grant execute on function public.accept_aircraft_transfer(text, text) to authenticated;

-- ---------------------------------------------------------------- beta tester status (admins only)
-- Row-level security keeps every pilot's data private, including from the app's owner. These two
-- functions let the people listed in app_admins see, in the app (ACCOUNT > Beta testers), whether each
-- tester has signed in, set up an aircraft and uploaded flights and documents. Counts only, no file contents.
create table if not exists public.app_admins (email text primary key check (email = lower(email)));
alter table public.app_admins enable row level security;     -- no policies: not readable through the API
revoke all on public.app_admins from anon, authenticated;
insert into public.app_admins (email) values ('wayne@fueledconsulting.com') on conflict do nothing;

create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = public, auth
as $$
    select exists (select 1 from public.app_admins a join auth.users u on lower(u.email) = a.email where u.id = auth.uid())
$$;

create or replace function public.admin_tester_status()
returns table (email text, full_name text, signed_up timestamptz, confirmed boolean, last_sign_in timestamptz,
               tail_number text, aircraft text, monitor text, flights bigint, last_flight timestamptz,
               uploads bigint, uploads_waiting bigint, uploads_failed bigint, documents text)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
    if not public.is_app_admin() then
        raise exception 'not allowed' using errcode = '42501';
    end if;
    return query
    select u.email::text,
           (u.raw_user_meta_data ->> 'full_name')::text,
           u.created_at,
           u.email_confirmed_at is not null,
           u.last_sign_in_at,
           a.tail_number,
           nullif(btrim(coalesce(a.make, '') || ' ' || coalesce(a.model, '')), ''),
           a.monitor,
           (select count(*) from public.flight_logs f where f.owner_id = u.id),
           (select max(f.started_at) from public.flight_logs f where f.owner_id = u.id),
           (select count(*) from public.inbox_uploads i where i.owner_id = u.id),
           (select count(*) from public.inbox_uploads i where i.owner_id = u.id and i.status in ('received', 'unsupported')),
           (select count(*) from public.inbox_uploads i where i.owner_id = u.id and i.status = 'failed'),
           (select string_agg(x.c, ', ' order by x.c) from (
                select i.category || ' x' || count(*) as c from public.inbox_uploads i where i.owner_id = u.id group by i.category) x)
    from auth.users u
    left join lateral (select * from public.aircraft ac where ac.owner_id = u.id order by ac.created_at limit 1) a on true
    order by u.created_at desc;
end;
$$;

revoke all on function public.is_app_admin(), public.admin_tester_status() from public, anon;
grant execute on function public.is_app_admin(), public.admin_tester_status() to authenticated;
