-- Merges duplicate aircraft rows (run once in the Supabase SQL editor; safe to run again).
--
-- Before 0.9.8 (128) a device could create its own copy of an account's aircraft (signing in on a new device,
-- or switching accounts, before the account's aircraft had loaded). The app used only the first copy, so
-- nobody saw them; the aircraft menu in 0.9.8 lists them all.
--
-- For each account, copies with the same tail number become one aircraft: the copy with the most flights is
-- kept, the others' flights and uploads move to it (a flight already there by file name is not duplicated),
-- and the empty copies are deleted. Copies with no tail number are merged into the account's aircraft when
-- the account has exactly one tail number, and deleted when they hold nothing. Different tail numbers are
-- never merged. Prints what it did.

do $$
declare
    o record;
    g record;
    keeper uuid;
    best record;
    tails int;
    moved int;
    dropped int;
    removed int;
begin
    for o in select distinct owner_id from public.aircraft loop
        select count(distinct upper(btrim(tail_number))) into tails
          from public.aircraft where owner_id = o.owner_id and btrim(tail_number) <> '';

        for g in
            select upper(btrim(tail_number)) as tail from public.aircraft
             where owner_id = o.owner_id and btrim(tail_number) <> ''
             group by 1 having count(*) > 1
            union
            -- Blank copies join the account's only tail number (or form their own group when there is none).
            select coalesce((select upper(btrim(tail_number)) from public.aircraft
                              where owner_id = o.owner_id and btrim(tail_number) <> '' limit 1), '')
             where exists (select 1 from public.aircraft where owner_id = o.owner_id and btrim(tail_number) = '')
               and tails <= 1
        loop
            -- Keep the copy with the most flights, then a locked profile, then confirmed limits, then the oldest.
            select a.id into keeper
              from public.aircraft a
             where a.owner_id = o.owner_id
               and (upper(btrim(a.tail_number)) = g.tail or btrim(a.tail_number) = '')
             order by (select count(*) from public.flight_logs f where f.aircraft_id = a.id) desc,
                      (a.profile ->> 'lockedAt') is not null desc,
                      a.limits_confirmed desc,
                      btrim(a.tail_number) <> '' desc,
                      a.created_at
             limit 1;
            if keeper is null then continue; end if;

            -- The keeper takes the most complete profile in the group (a locked one, most recently changed).
            select a.* into best
              from public.aircraft a
             where a.owner_id = o.owner_id and a.id <> keeper
               and (upper(btrim(a.tail_number)) = g.tail or btrim(a.tail_number) = '')
               and (a.profile ->> 'lockedAt') is not null
             order by a.updated_at desc limit 1;
            if best.id is not null and (select (profile ->> 'lockedAt') is null from public.aircraft where id = keeper) then
                update public.aircraft k
                   set tail_number = best.tail_number, make = best.make, model = best.model, year = best.year,
                       engine_model = best.engine_model, cylinders = best.cylinders, is_turbocharged = best.is_turbocharged,
                       monitor = best.monitor, limits_confirmed = best.limits_confirmed, profile = best.profile
                 where k.id = keeper;
            end if;
            best := null;

            -- Flights: move the ones the keeper doesn't have; drop exact duplicates (same file name).
            with dups as (
                select f.id from public.flight_logs f
                 where f.aircraft_id in (select id from public.aircraft where owner_id = o.owner_id and id <> keeper
                                          and (upper(btrim(tail_number)) = g.tail or btrim(tail_number) = ''))
                   and exists (select 1 from public.flight_logs k where k.aircraft_id = keeper and k.filename = f.filename))
            delete from public.flight_logs where id in (select id from dups);
            get diagnostics dropped = row_count;
            -- Two copies may both hold the same file name: move one of each.
            with movers as (
                select distinct on (f.filename) f.id from public.flight_logs f
                 where f.aircraft_id in (select id from public.aircraft where owner_id = o.owner_id and id <> keeper
                                          and (upper(btrim(tail_number)) = g.tail or btrim(tail_number) = ''))
                 order by f.filename, f.uploaded_at)
            update public.flight_logs set aircraft_id = keeper where id in (select id from movers);
            get diagnostics moved = row_count;
            delete from public.flight_logs f
             where f.aircraft_id in (select id from public.aircraft where owner_id = o.owner_id and id <> keeper
                                      and (upper(btrim(tail_number)) = g.tail or btrim(tail_number) = ''));

            update public.inbox_uploads set aircraft_id = keeper
             where owner_id = o.owner_id
               and aircraft_id in (select id from public.aircraft where owner_id = o.owner_id and id <> keeper
                                    and (upper(btrim(tail_number)) = g.tail or btrim(tail_number) = ''));

            delete from public.aircraft
             where owner_id = o.owner_id and id <> keeper
               and (upper(btrim(tail_number)) = g.tail or btrim(tail_number) = '');
            get diagnostics removed = row_count;

            if removed > 0 then
                raise notice 'account %: kept aircraft % (%), merged % copies, moved % flights, % duplicate flights dropped',
                    o.owner_id, keeper, nullif(g.tail, ''), removed, moved, dropped;
            end if;
        end loop;

        -- Several tail numbers and blank copies with nothing in them: remove the empty ones.
        delete from public.aircraft a
         where a.owner_id = o.owner_id and btrim(a.tail_number) = '' and tails > 1
           and not exists (select 1 from public.flight_logs f where f.aircraft_id = a.id)
           and not exists (select 1 from public.inbox_uploads i where i.aircraft_id = a.id)
           and not exists (select 1 from public.aircraft_transfers t where t.aircraft_id = a.id and t.status = 'pending');
    end loop;
end $$;

-- What's left: one row per aircraft.
select u.email, a.tail_number, nullif(btrim(a.make || ' ' || a.model), '') as aircraft,
       (select count(*) from public.flight_logs f where f.aircraft_id = a.id) as flights,
       a.created_at
  from public.aircraft a join auth.users u on u.id = a.owner_id
 order by u.email, a.created_at;
