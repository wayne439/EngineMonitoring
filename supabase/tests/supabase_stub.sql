-- Minimal stand-in for the parts of Supabase that schema.sql relies on, so the schema and its
-- row-level security can be tested on plain Postgres. Not for production.
create extension if not exists pgcrypto;

do $$ begin
    if not exists (select from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text, email_confirmed_at timestamptz default now(),
    created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}'::jsonb);
-- Supabase reads the signed-in user from the JWT; the tests set it with set_config.
create or replace function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
create or replace function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
alter table storage.objects enable row level security;

grant usage on schema public, auth, storage to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant select, insert, update, delete on storage.objects to authenticated;
