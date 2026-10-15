-- AI Engine Monitoring: cloud database schema (Supabase / Postgres).
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
