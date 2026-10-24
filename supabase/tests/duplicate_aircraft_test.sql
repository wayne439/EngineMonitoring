\set ON_ERROR_STOP on
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000a', 'w@x.com'), ('00000000-0000-0000-0000-00000000000b', 't@x.com');
insert into public.aircraft (id, owner_id, tail_number, model, profile, created_at) values
 ('a0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','N63KA','SR22 Turbo (turbonormalized)','{"lockedAt":"2026-10-01T00:00:00Z"}', now()-interval '5 days'),
 ('a0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000a','n63ka ','SR22 Turbo','{}', now()-interval '4 days'),
 ('a0000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000a','','SR22 Turbo','{}', now()-interval '3 days'),
 ('b0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000b','N24AM','SR22T','{}', now()-interval '3 days'),
 ('b0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000b','N99XX','SR22','{}', now()-interval '2 days'),
 ('b0000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000b','','SR22','{}', now()-interval '1 days');
insert into public.flight_logs (owner_id, aircraft_id, filename, original_filename, started_at, ended_at, storage_path) values
 ('00000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000002','f1','f1',now(),now(),'p1'),
 ('00000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000002','f2','f2',now(),now(),'p2'),
 ('00000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000001','f1','f1',now(),now(),'p1b'),
 ('00000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000003','f3','f3',now(),now(),'p3'),
 ('00000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000003','f2','f2',now(),now(),'p2c'),
 ('00000000-0000-0000-0000-00000000000b','b0000000-0000-0000-0000-000000000001','t1','t1',now(),now(),'q1');
insert into public.inbox_uploads (owner_id, aircraft_id, original_filename, storage_path) values
 ('00000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000003','poh.pdf','x');
\i supabase/fix-duplicate-aircraft.sql
do $$ begin
  if (select count(*) from public.aircraft where owner_id='00000000-0000-0000-0000-00000000000a') <> 1 then raise exception 'W should have 1 aircraft'; end if;
  if (select count(*) from public.flight_logs where owner_id='00000000-0000-0000-0000-00000000000a') <> 3 then raise exception 'W flights %', (select count(*) from public.flight_logs where owner_id='00000000-0000-0000-0000-00000000000a'); end if;
  if (select profile->>'lockedAt' from public.aircraft where owner_id='00000000-0000-0000-0000-00000000000a') is null then raise exception 'lost locked profile'; end if;
  if (select count(*) from public.inbox_uploads where aircraft_id is null) <> 0 then raise exception 'upload lost'; end if;
  if (select count(*) from public.aircraft where owner_id='00000000-0000-0000-0000-00000000000b') <> 2 then raise exception 'T should keep 2 real aircraft'; end if;
end $$;
\i supabase/fix-duplicate-aircraft.sql
select 'DUP TESTS PASSED';
