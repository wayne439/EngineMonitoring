-- Aircraft transfer (sale) tests. Run on a fresh database after supabase_stub.sql and schema.sql.
-- Ends with "ALL TRANSFER TESTS PASSED".
\set ON_ERROR_STOP on
grant select, insert, update, delete on public.aircraft, public.flight_logs, public.inbox_uploads to authenticated;

insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-00000000000a', 'seller@example.com'),
    ('00000000-0000-0000-0000-00000000000b', 'Buyer@Example.com'),
    ('00000000-0000-0000-0000-00000000000c', 'other@example.com');
insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-0000-0000-00000000000d', 'buyer2@example.com', null);

-- Seller A: an aircraft, a flight log, a POH upload and the transfer snapshot.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into public.aircraft (id, tail_number) values ('11111111-1111-1111-1111-111111111111', 'N12345');
insert into public.flight_logs (aircraft_id, filename, original_filename, started_at, ended_at, storage_path)
values ('11111111-1111-1111-1111-111111111111', 'log1.csv', 'log1.csv', now() - interval '1 hour', now(),
        '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111/log1.csv');
insert into public.inbox_uploads (aircraft_id, source, category, original_filename, storage_path, format, status)
values ('11111111-1111-1111-1111-111111111111', 'web', 'poh-limits', 'poh.pdf', '00000000-0000-0000-0000-00000000000a/inbox/poh.pdf', 'pdf', 'stored');
insert into storage.objects (bucket_id, name) values
    ('engine-logs', '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111/log1.csv'),
    ('engine-logs', '00000000-0000-0000-0000-00000000000a/inbox/poh.pdf'),
    ('engine-logs', '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111/transfer-state.json'),
    ('engine-logs', '00000000-0000-0000-0000-00000000000a/app-state.json');

-- Other user C owns an aircraft too.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
insert into public.aircraft (id, tail_number) values ('33333333-3333-3333-3333-333333333333', 'N999C');

-- A starts the transfer to B. A can't transfer C's aircraft, start one as accepted, or edit the buyer.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into public.aircraft_transfers (aircraft_id, tail_number, to_email, to_phone, code_hash, state_path)
values ('11111111-1111-1111-1111-111111111111', 'N12345', 'buyer@example.com', '6025551234',
        encode(sha256('ABCD2345'::bytea), 'hex'),
        '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111/transfer-state.json');
do $$ begin
    begin
        insert into public.aircraft_transfers (aircraft_id, to_email, to_phone, code_hash)
        values ('33333333-3333-3333-3333-333333333333', 'buyer@example.com', '6025551234', encode(sha256('X'::bytea), 'hex'));
        raise exception 'A transferred C''s aircraft';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.aircraft_transfers (aircraft_id, to_email, to_phone, code_hash, status)
        values ('11111111-1111-1111-1111-111111111111', 'x@example.com', '6025551234', encode(sha256('X'::bytea), 'hex'), 'accepted');
        raise exception 'A started a transfer as accepted';
    exception when insufficient_privilege then null;
    end;
    begin
        update public.aircraft_transfers set to_email = 'other@example.com';
        raise exception 'A changed the buyer email';
    exception when insufficient_privilege then null;
    end;
    begin
        perform public.accept_aircraft_transfer('ABCD2345', '6025551234');
    end;
end $$;
do $$ begin
    if public.accept_aircraft_transfer('ABCD2345', '6025551234')->>'reason' is distinct from 'none' then
        raise exception 'seller (wrong email) got past the email check';
    end if;
end $$;

-- C knows the code but is signed in with another email.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
do $$ begin
    if (public.accept_aircraft_transfer('ABCD2345', '6025551234'))->>'ok' <> 'false' then raise exception 'C accepted B''s transfer'; end if;
    if exists (select 1 from public.aircraft_transfers) then raise exception 'C can see the transfer'; end if;
end $$;

-- Unconfirmed email can't accept.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
do $$ begin
    if (public.accept_aircraft_transfer('ABCD2345', '6025551234'))->>'reason' <> 'unconfirmed' then raise exception 'unconfirmed email accepted'; end if;
end $$;

-- B: wrong code, wrong phone, then right (formatted) code and phone. B's empty aircraft from registering is replaced.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
insert into public.aircraft (id, tail_number) values ('22222222-2222-2222-2222-222222222222', 'NEW');
do $$
declare r jsonb;
begin
    r := public.accept_aircraft_transfer('ABCD9999', '6025551234');
    if r->>'reason' <> 'mismatch' then raise exception 'wrong code: %', r; end if;
    r := public.accept_aircraft_transfer('ABCD2345', '4805550000');
    if r->>'reason' <> 'mismatch' then raise exception 'wrong phone: %', r; end if;
    if (select count(*) from public.aircraft) <> 1 then raise exception 'B sees the aircraft before accepting'; end if;
    r := public.accept_aircraft_transfer('abcd-2345', '+1 (602) 555-1234');
    if r->>'ok' <> 'true' then raise exception 'accept failed: %', r; end if;
    if r->>'aircraft_id' <> '11111111-1111-1111-1111-111111111111' or r->>'tail_number' <> 'N12345' then raise exception 'bad result %', r; end if;
    if (select count(*) from public.aircraft) <> 1 or (select tail_number from public.aircraft) <> 'N12345' then raise exception 'B does not own just the transferred aircraft'; end if;
    if (select count(*) from public.flight_logs) <> 1 then raise exception 'B does not own the logs'; end if;
    if (select count(*) from public.inbox_uploads) <> 1 then raise exception 'B does not own the documents'; end if;
    if (select count(*) from storage.objects) <> 3 then raise exception 'B should read the log, POH and snapshot, got %', (select count(*) from storage.objects); end if;
    if (select status from public.aircraft_transfers) <> 'accepted' then raise exception 'transfer not marked accepted'; end if;
    -- The same code can't be used twice.
    if (public.accept_aircraft_transfer('ABCD2345', '6025551234'))->>'ok' <> 'false' then raise exception 'code reused'; end if;
end $$;
-- B can still mark its documents (path unchanged) and add its own flights.
update public.inbox_uploads set status = 'stored';
insert into public.flight_logs (aircraft_id, filename, original_filename, started_at, ended_at, storage_path)
values ('11111111-1111-1111-1111-111111111111', 'log2.csv', 'log2.csv', now(), now(),
        '00000000-0000-0000-0000-00000000000b/11111111-1111-1111-1111-111111111111/log2.csv');

-- A no longer sees, changes or deletes the aircraft or its files, but keeps its own app-state file.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
update public.aircraft set tail_number = 'HACKED';
delete from storage.objects where name like '00000000-0000-0000-0000-00000000000a/%';
do $$ begin
    if (select count(*) from public.aircraft) <> 0 then raise exception 'seller still sees the aircraft'; end if;
    if (select count(*) from public.flight_logs) <> 0 then raise exception 'seller still sees the logs'; end if;
    if (select count(*) from storage.objects) <> 0 then raise exception 'seller app-state should have been deletable, others not'; end if;
    if (select status from public.aircraft_transfers) <> 'accepted' then raise exception 'seller cannot see the accepted transfer'; end if;
    begin
        insert into public.aircraft_transfers (aircraft_id, to_email, to_phone, code_hash)
        values ('11111111-1111-1111-1111-111111111111', 'other@example.com', '6025551234', encode(sha256('X'::bytea), 'hex'));
        raise exception 'seller transferred a sold aircraft';
    exception when insufficient_privilege then null;
    end;
end $$;
reset role;
do $$ begin
    if (select tail_number from public.aircraft where id = '11111111-1111-1111-1111-111111111111') <> 'N12345' then raise exception 'seller changed the sold aircraft'; end if;
    if (select count(*) from storage.objects where name like '00000000-0000-0000-0000-00000000000a/%') <> 3 then raise exception 'seller deleted the buyer''s files'; end if;
end $$;

-- A buyer who already has an aircraft with flights gets the transferred one added next to it.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
insert into public.flight_logs (aircraft_id, filename, original_filename, started_at, ended_at, storage_path)
values ('33333333-3333-3333-3333-333333333333', 'c.csv', 'c.csv', now(), now(),
        '00000000-0000-0000-0000-00000000000c/33333333-3333-3333-3333-333333333333/c.csv');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
insert into public.aircraft_transfers (aircraft_id, tail_number, to_email, to_phone, code_hash)
values ('11111111-1111-1111-1111-111111111111', 'N12345', 'other@example.com', '4805551111', encode(sha256('HHHH2222'::bytea), 'hex'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
do $$
declare r jsonb;
begin
    r := public.accept_aircraft_transfer('HHHH2222', '4805551111');
    if (r->>'ok')::boolean is not true then raise exception 'second aircraft not accepted: %', r; end if;
    if (select count(*) from public.aircraft) <> 2 then raise exception 'C should have both aircraft'; end if;
    if not exists (select 1 from public.aircraft where tail_number = 'N999C') then raise exception 'C''s own aircraft was removed'; end if;
end $$;
reset role;
-- Put the aircraft back with B for the tests below.
update public.aircraft set owner_id = '00000000-0000-0000-0000-00000000000b' where id = '11111111-1111-1111-1111-111111111111';
update public.flight_logs set owner_id = '00000000-0000-0000-0000-00000000000b' where aircraft_id = '11111111-1111-1111-1111-111111111111';
update public.inbox_uploads set owner_id = '00000000-0000-0000-0000-00000000000b' where aircraft_id = '11111111-1111-1111-1111-111111111111';
update public.aircraft_transfers set status = 'cancelled' where status in ('pending', 'accepted') and to_email = 'other@example.com';

-- Five wrong tries cancel a transfer. B sells to C; C guesses.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
insert into public.aircraft_transfers (aircraft_id, tail_number, to_email, to_phone, code_hash)
values ('11111111-1111-1111-1111-111111111111', 'N12345', 'other@example.com', '4805551111', encode(sha256('ZZZZ7777'::bytea), 'hex'));
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
do $$
declare r jsonb;
begin
    for i in 1..4 loop
        r := public.accept_aircraft_transfer('WRONG' || i, '4805551111');
        if r->>'reason' <> 'mismatch' then raise exception 'try %: %', i, r; end if;
    end loop;
    r := public.accept_aircraft_transfer('WRONG5', '4805551111');
    if r->>'reason' <> 'locked' then raise exception 'not locked after 5 tries: %', r; end if;
    r := public.accept_aircraft_transfer('ZZZZ7777', '4805551111');
    if r->>'ok' <> 'false' then raise exception 'accepted after lockout'; end if;
end $$;

-- B cancels nothing pending now; B can cancel a new one.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
insert into public.aircraft_transfers (aircraft_id, tail_number, to_email, to_phone, code_hash)
values ('11111111-1111-1111-1111-111111111111', 'N12345', 'other@example.com', '4805551111', encode(sha256('YYYY8888'::bytea), 'hex'));
update public.aircraft_transfers set status = 'cancelled' where status = 'pending';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
do $$ begin
    if (public.accept_aircraft_transfer('YYYY8888', '4805551111'))->>'ok' <> 'false' then raise exception 'accepted a cancelled transfer'; end if;
end $$;

-- The seller deletes their account: the buyer keeps everything.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select public.delete_my_account();
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
do $$ begin
    if (select count(*) from public.aircraft) <> 1 then raise exception 'buyer lost the aircraft'; end if;
    if (select count(*) from public.flight_logs) <> 2 then raise exception 'buyer lost logs'; end if;
    if (select count(*) from storage.objects where name like '00000000-0000-0000-0000-00000000000a/%') < 2 then raise exception 'buyer lost access to files'; end if;
end $$;
reset role;

select 'ALL TRANSFER TESTS PASSED' as result;
