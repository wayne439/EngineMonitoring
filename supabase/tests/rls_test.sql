-- Row-level security tests for schema.sql. Run after supabase_stub.sql and schema.sql.
-- Every check raises an exception on failure; the script ends with "ALL RLS TESTS PASSED".
\set ON_ERROR_STOP on
grant select, insert, update, delete on public.aircraft, public.flight_logs, public.inbox_uploads to authenticated;

insert into auth.users values ('00000000-0000-0000-0000-00000000000a', 'a@example.com'),
                              ('00000000-0000-0000-0000-00000000000b', 'b@example.com');

-- Pilot A adds an aircraft, a log row and a file.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into public.aircraft (id, tail_number, make, model, profile)
values ('11111111-1111-1111-1111-111111111111', 'N12345', 'Cirrus', 'SR22', '{"tailNumber":"N12345"}');
insert into public.flight_logs (aircraft_id, filename, original_filename, started_at, ended_at, storage_path, summary)
values ('11111111-1111-1111-1111-111111111111', 'log1.csv', 'log1.csv', now() - interval '2 hours', now(),
        '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111/log1.csv', '{"flight":1}');
insert into storage.objects (bucket_id, name) values ('engine-logs', '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111/log1.csv');
insert into public.inbox_uploads (aircraft_id, source, original_filename, storage_path, format, status)
values ('11111111-1111-1111-1111-111111111111', 'share', 'flight.jpi', '00000000-0000-0000-0000-00000000000a/inbox/flight.jpi', 'jpi', 'unsupported');
insert into public.inbox_uploads (aircraft_id, source, category, original_filename, storage_path, format, status)
values ('11111111-1111-1111-1111-111111111111', 'web', 'poh-limits', 'poh-section2.pdf', '00000000-0000-0000-0000-00000000000a/inbox/poh.pdf', 'pdf', 'received');
-- The app marks web uploads once handled.
update public.inbox_uploads set status = 'stored', processed_at = now() where category = 'poh-limits';
do $$ begin
    if (select status from public.inbox_uploads where category = 'poh-limits') <> 'stored' then raise exception 'owner could not update status'; end if;
    begin
        insert into public.inbox_uploads (original_filename, storage_path, category) values ('a.pdf', '00000000-0000-0000-0000-00000000000a/inbox/a.pdf', 'bogus');
        raise exception 'category check did not fire';
    exception when check_violation then null;
    end;
end $$;

-- owner_id was filled from the signed-in user.
do $$ begin
    if (select owner_id from public.aircraft) <> '00000000-0000-0000-0000-00000000000a' then raise exception 'owner_id default failed'; end if;
end $$;

-- A cannot write a file outside their own folder.
do $$ begin
    begin
        insert into storage.objects (bucket_id, name) values ('engine-logs', '00000000-0000-0000-0000-00000000000b/x/log.csv');
        raise exception 'A wrote into B''s folder';
    exception when insufficient_privilege then null;
    end;
end $$;

-- Pilot B sees nothing of A's.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
do $$ begin
    if (select count(*) from public.aircraft) <> 0 then raise exception 'B can see A''s aircraft'; end if;
    if (select count(*) from public.flight_logs) <> 0 then raise exception 'B can see A''s logs'; end if;
    if (select count(*) from storage.objects) <> 0 then raise exception 'B can see A''s files'; end if;
    if (select count(*) from public.inbox_uploads) <> 0 then raise exception 'B can see A''s inbox'; end if;
end $$;

-- B cannot attach a log to A's aircraft, nor pose as A.
do $$ begin
    begin
        insert into public.flight_logs (aircraft_id, filename, original_filename, started_at, ended_at, storage_path)
        values ('11111111-1111-1111-1111-111111111111', 'evil.csv', 'evil.csv', now(), now(), 'x');
        raise exception 'B attached a log to A''s aircraft';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.aircraft (owner_id, tail_number) values ('00000000-0000-0000-0000-00000000000a', 'N666');
        raise exception 'B created an aircraft owned by A';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.inbox_uploads (aircraft_id, original_filename, storage_path)
        values ('11111111-1111-1111-1111-111111111111', 'evil.jpi', 'x');
        raise exception 'B attached an inbox file to A''s aircraft';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.inbox_uploads (original_filename, storage_path, status) values ('a.csv', '00000000-0000-0000-0000-00000000000b/inbox/a.csv', 'bogus');
        raise exception 'status check did not fire';
    exception when check_violation then null;
    end;
    -- B cannot point a row at A's file to read it.
    begin
        insert into public.inbox_uploads (original_filename, storage_path, status)
        values ('steal.csv', '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111/log1.csv', 'received');
        raise exception 'B pointed a row at A''s file';
    exception when insufficient_privilege then null;
    end;
end $$;

-- B cannot change or delete A's rows (they are invisible, so 0 rows are affected).
update public.aircraft set tail_number = 'HACKED';
delete from public.flight_logs;

-- Not signed in: no access to the account-deletion function's effect.
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
    begin
        perform public.delete_my_account();
        raise exception 'delete_my_account ran without a user';
    exception when raise_exception then
        if sqlerrm <> 'not signed in' then raise; end if;
    end;
end $$;

-- A deletes their account: their rows go with it, B is untouched.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
do $$ begin
    if (select tail_number from public.aircraft) <> 'N12345' then raise exception 'B changed A''s aircraft'; end if;
    if (select count(*) from public.flight_logs) <> 1 then raise exception 'B deleted A''s logs'; end if;
end $$;
select public.delete_my_account();
reset role;
do $$ begin
    if exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000a') then raise exception 'user A not deleted'; end if;
    if (select count(*) from public.aircraft) <> 0 then raise exception 'aircraft not cascaded'; end if;
    if (select count(*) from public.flight_logs) <> 0 then raise exception 'logs not cascaded'; end if;
    if (select count(*) from public.inbox_uploads) <> 0 then raise exception 'inbox not cascaded'; end if;
    if not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000b') then raise exception 'user B was deleted'; end if;
end $$;

select 'ALL RLS TESTS PASSED' as result;
