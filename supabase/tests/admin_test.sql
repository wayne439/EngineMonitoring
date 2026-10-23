-- Admin tester-status tests. Run on a fresh database after supabase_stub.sql and schema.sql.
\set ON_ERROR_STOP on
grant select, insert, update, delete on public.aircraft, public.flight_logs, public.inbox_uploads to authenticated;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-00000000000a', 'Wayne@FueledConsulting.com', '{"full_name":"Wayne"}'),
    ('00000000-0000-0000-0000-00000000000b', 'tom@example.com', '{"full_name":"Tom"}');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
insert into public.aircraft (id, tail_number, make, model, monitor) values ('22222222-2222-2222-2222-222222222222', 'N1TOM', 'Cirrus', 'SR22', 'Cirrus Perspective (Garmin)');
insert into public.inbox_uploads (aircraft_id, source, category, original_filename, storage_path, status) values
    ('22222222-2222-2222-2222-222222222222', 'web', 'poh-limits', 'poh.pdf', '00000000-0000-0000-0000-00000000000b/inbox/1-poh.pdf', 'stored'),
    ('22222222-2222-2222-2222-222222222222', 'web', 'poh-limits', 'poh.pdf', '00000000-0000-0000-0000-00000000000b/inbox/2-poh.pdf', 'stored'),
    ('22222222-2222-2222-2222-222222222222', 'web', 'logs', 'a.csv', '00000000-0000-0000-0000-00000000000b/inbox/a.csv', 'received');
do $$ begin
    if public.is_app_admin() then raise exception 'tester is admin'; end if;
    begin
        perform * from public.admin_tester_status();
        raise exception 'tester saw admin status';
    exception when insufficient_privilege then null;
    end;
    begin
        perform public.admin_tester_detail('tom@example.com');
        raise exception 'tester saw admin detail';
    exception when insufficient_privilege then null;
    end;
    begin
        perform 1 from public.app_admins;
        raise exception 'tester read app_admins';
    exception when insufficient_privilege then null;
    end;
end $$;
-- Testers can delete their own uploads (duplicate POH).
delete from public.inbox_uploads where storage_path like '%2-poh.pdf';
do $$ begin
    if (select count(*) from public.inbox_uploads) <> 2 then raise exception 'tester could not delete an upload'; end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
do $$
declare r record;
begin
    if not public.is_app_admin() then raise exception 'admin not recognised (email case)'; end if;
    select * into r from public.admin_tester_status() s where s.email = 'tom@example.com';
    if r.tail_number <> 'N1TOM' or r.uploads <> 2 or r.uploads_waiting <> 1 or r.flights <> 0 or r.full_name <> 'Tom' then
        raise exception 'bad status %', r;
    end if;
    if r.documents <> 'logs x1, poh-limits x1' then raise exception 'documents %', r.documents; end if;
    if (select count(*) from public.admin_tester_status()) <> 2 then raise exception 'admin should see every account'; end if;
end $$;
do $$
declare d jsonb := public.admin_tester_detail('TOM@example.com');
begin
    if jsonb_array_length(d -> 'uploads') <> 2 or jsonb_array_length(d -> 'flights') <> 0 then raise exception 'detail %', d; end if;
    if not exists (select 1 from jsonb_array_elements(d -> 'uploads') e where e ->> 'filename' = 'a.csv' and e ->> 'status' = 'received')
    then raise exception 'upload missing %', d; end if;
end $$;
reset role;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000c', 'Sales@EnginePulse.net');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
do $$ begin
    if not public.is_app_admin() then raise exception 'sales@ should be admin'; end if;
end $$;
reset role;
select 'ALL ADMIN TESTS PASSED' as result;
