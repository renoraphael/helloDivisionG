-- 005: copy a division's shared record (hdg_sync_state) into the per-record tables, and compare (Phase 0, step 7).
-- TEST project first. In production this only runs after the owner approves (project/DISTRICT_PLAN.md rule 31).
-- The copy only adds to the new tables: hdg_sync_state and its revision history are never changed.
-- Safe to re-run: identities come from TI club number and member ID (rule 9), manual fields and
-- hand-corrected TI fields already in the new tables are kept (rule 11), and unchanged rows are not rewritten.
-- Neither function is callable through the API; the maintainer runs them as the database owner.
-- Privacy: every district user can read hdg_clubs, and a person can read their own hdg_people row. So the copy
-- puts only public club information (name, city, meeting mode) in hdg_clubs, and keeps the leader-only club
-- fields (renewals, risk, notes, visits...) and leaders' notes about members in hdg_sync_private.legacy_records,
-- which no app user can read. Who may see those after the switch is decided then.

create table if not exists hdg_sync_private.legacy_records (
 kind text not null check (kind in ('club', 'member_notes')),
 key text not null,
 data jsonb not null,
 copied_at timestamptz not null default now(),
 primary key (kind, key));
alter table hdg_sync_private.legacy_records enable row level security;
revoke all on hdg_sync_private.legacy_records from public, anon, authenticated;

create or replace function hdg_sync_private.safe_date(t text) returns date language plpgsql immutable set search_path to ''
as $$ begin return case when t ~ '^\d{4}-\d{2}-\d{2}$' then t::date end; exception when others then return null; end $$;

create or replace function hdg_sync_private.legacy_role(t text) returns text language sql immutable set search_path to ''
as $$ select case t
  when 'Club President' then 'club_president' when 'Club VP Education' then 'club_vpe'
  when 'Club VP Membership' then 'club_vpm' when 'Club VP PR' then 'club_vppr'
  when 'Club Secretary' then 'club_secretary' when 'Club Treasurer' then 'club_treasurer'
  when 'Club Sergeant at Arms' then 'club_saa' end $$;

-- TI writes club numbers with leading zeros (00123456); the same club can appear as 123456. One form is stored:
-- without leading zeros. The app can pad to 8 digits for display.
create or replace function hdg_sync_private.club_no(t text) returns text language sql immutable set search_path to ''
as $$ select case when ltrim(btrim(coalesce(t, '')), '0') ~ '^[1-9][0-9]*$' then ltrim(btrim(t), '0') end $$;

-- Legacy membership rows with a usable member ID, one per member and club.
create or replace function hdg_sync_private.legacy_memberships(db jsonb)
returns table(mid text, club text, e jsonb) language sql immutable set search_path to ''
as $$
 select distinct on (e->>'memberId', hdg_sync_private.club_no(e->>'clubNumber'))
   e->>'memberId', hdg_sync_private.club_no(e->>'clubNumber'), e
 from jsonb_array_elements(coalesce(db->'memberships', '[]')) e
 where coalesce(e->>'memberId', '') ~ '^[0-9A-Za-z]{1,20}$' and hdg_sync_private.club_no(e->>'clubNumber') is not null
 order by e->>'memberId', hdg_sync_private.club_no(e->>'clubNumber'), (e->>'active')::boolean desc nulls last
$$;

create or replace function hdg_sync_private.copy_legacy_division(p_division text, p_year int, p_payload jsonb default null)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare db jsonb; st jsonb; result jsonb := '{}'; n int; needs_id jsonb := '[]';
begin
 if p_payload is null then
   select payload into p_payload from public.hdg_sync_state where division_code = p_division;
 end if;
 db := p_payload->'database'; st := coalesce(p_payload->'settings', '{}');
 if jsonb_typeof(db) is distinct from 'object' then raise exception 'No shared record for division %', p_division; end if;

 insert into public.hdg_divisions(code, name) values (p_division, 'Division ' || p_division) on conflict do nothing;
 insert into public.hdg_program_years(year_start, transition_opens) values (p_year, make_date(p_year, 5, 15)) on conflict do nothing;

 insert into public.hdg_areas(year_start, code, division_code)
 select distinct p_year, a, p_division from (
   select e->>'code' a from jsonb_array_elements(coalesce(db->'areas', '[]')) e
   union select e->>'area' from jsonb_array_elements(db->'clubs') e) x
 where a ~ ('^' || p_division || '[0-9]{1,2}$')
 on conflict do nothing;

 -- Clubs. Name and city come from the legacy record only for new clubs; everything else is kept under details.legacy.
 -- Time zone: East Java is WIB; the rest of Division G (Bali, Sulawesi, Kalimantan, online) starts as WITA
 -- and can be corrected per club in the app.
 insert into public.hdg_clubs(club_number, name, city, timezone, currency, details)
 select hdg_sync_private.club_no(e->>'number'), left(btrim(e->>'name'), 160), nullif(btrim(e->>'city'), ''),
   case e->>'island' when 'East Java' then 'Asia/Jakarta' when 'Papua' then 'Asia/Jayapura' else 'Asia/Makassar' end, 'IDR',
   case when coalesce(btrim(e->>'mode'), '') <> '' then jsonb_build_object('meeting_mode', btrim(e->>'mode')) else '{}' end
 from jsonb_array_elements(db->'clubs') e
 where hdg_sync_private.club_no(e->>'number') is not null and length(btrim(coalesce(e->>'name', ''))) > 0
 on conflict (club_number) do nothing;
 get diagnostics n = row_count; result := result || jsonb_build_object('clubs', n);

 -- Leader-only club fields, kept privately.
 insert into hdg_sync_private.legacy_records(kind, key, data)
 select 'club', hdg_sync_private.club_no(e->>'number'), e - array['number', 'name', 'city', 'area']
 from jsonb_array_elements(db->'clubs') e where hdg_sync_private.club_no(e->>'number') is not null
 on conflict (kind, key) do update set data = excluded.data, copied_at = now()
   where hdg_sync_private.legacy_records.data is distinct from excluded.data;

 insert into public.hdg_club_alignment(year_start, club_number, area_code)
 select p_year, hdg_sync_private.club_no(e->>'number'), e->>'area' from jsonb_array_elements(db->'clubs') e
 where e->>'area' ~ ('^' || p_division || '[0-9]{1,2}$')
   and exists (select 1 from public.hdg_clubs c where c.club_number = hdg_sync_private.club_no(e->>'number'))
 on conflict (year_start, club_number) do nothing;

 -- People, one per member ID. The row used for name and email is the active one with the latest renewal.
 with m as (select * from hdg_sync_private.legacy_memberships(db)),
 rep as (select distinct on (mid) mid, e from m order by mid, (e->>'active')::boolean desc nulls last, e->>'renewThrough' desc nulls last),
 nick as (
   select mid, array_agg(x order by o, x) xs from (
     select distinct on (m.mid, btrim(x)) m.mid, btrim(x) x, o from m,
       lateral (select m.e->>'nickname' x, 0 o
                union all select jsonb_array_elements_text(case when jsonb_typeof(m.e->'nicknames') = 'array' then m.e->'nicknames' else '[]' end), 1
                union all select jsonb_array_elements_text(case when jsonb_typeof(v->'nicknames') = 'array' then v->'nicknames' else '[]' end), 2
                  from jsonb_each(coalesce(db->'memberIdentityAliases', '{}')) a(k, v) where v->>'memberId' = m.mid) y
     where coalesce(btrim(x), '') <> '' order by m.mid, btrim(x), o) z
   group by mid),
 x as (select 1)
 insert into public.hdg_people(ti_member_id, name, email, nickname, aliases)
 select r.mid, left(btrim(r.e->>'name'), 160), nullif(lower(btrim(r.e->>'email')), ''),
   left(nick.xs[1], 80), coalesce(nick.xs[2:21], '{}')
 from rep r left join nick using (mid)
 where length(btrim(coalesce(r.e->>'name', ''))) > 0
 on conflict (ti_member_id) do update set
   name = case when public.hdg_people.hand_corrected ? 'name' then public.hdg_people.name else excluded.name end,
   email = case when public.hdg_people.hand_corrected ? 'email' then public.hdg_people.email else excluded.email end,
   nickname = coalesce(public.hdg_people.nickname, excluded.nickname),
   aliases = case when cardinality(public.hdg_people.aliases) = 0 then excluded.aliases else public.hdg_people.aliases end
 where (public.hdg_people.name, public.hdg_people.email, public.hdg_people.nickname, public.hdg_people.aliases)
   is distinct from (
   case when public.hdg_people.hand_corrected ? 'name' then public.hdg_people.name else excluded.name end,
   case when public.hdg_people.hand_corrected ? 'email' then public.hdg_people.email else excluded.email end,
   coalesce(public.hdg_people.nickname, excluded.nickname),
   case when cardinality(public.hdg_people.aliases) = 0 then excluded.aliases else public.hdg_people.aliases end);
 get diagnostics n = row_count; result := result || jsonb_build_object('people', n);

 -- Leaders' notes about members, kept privately (one record per member ID, notes from every club).
 insert into hdg_sync_private.legacy_records(kind, key, data)
 select 'member_notes', mid, jsonb_agg(jsonb_build_object('club', club, 'notes', btrim(e->>'notes')) order by club)
 from hdg_sync_private.legacy_memberships(db) where coalesce(btrim(e->>'notes'), '') <> '' group by mid
 on conflict (kind, key) do update set data = excluded.data, copied_at = now()
   where hdg_sync_private.legacy_records.data is distinct from excluded.data;

 insert into public.hdg_memberships(person_id, club_number, status, joined_on, paid_until)
 select p.id, m.club,
   case when (m.e->>'active')::boolean then 'active' when (m.e->>'pastMember')::boolean then 'past' else 'lapsed' end,
   hdg_sync_private.safe_date(m.e->>'clubJoinDate'), hdg_sync_private.safe_date(m.e->>'renewThrough')
 from hdg_sync_private.legacy_memberships(db) m
 join public.hdg_people p on p.ti_member_id = m.mid
 join public.hdg_clubs c on c.club_number = m.club
 on conflict (person_id, club_number) do update set status = excluded.status, joined_on = excluded.joined_on, paid_until = excluded.paid_until
 where (public.hdg_memberships.status, public.hdg_memberships.joined_on, public.hdg_memberships.paid_until)
   is distinct from (excluded.status, excluded.joined_on, excluded.paid_until);
 get diagnostics n = row_count; result := result || jsonb_build_object('memberships', n);

 -- Club officers for this program year, matched by member ID. Roles outside the officer list are not copied.
 insert into public.hdg_roles(person_id, role, scope_type, scope_code, year_start, starts_on, ends_on)
 select distinct on (p.id, x.r, c.club_number) p.id, x.r, 'club', c.club_number, p_year,
   least(greatest(coalesce(hdg_sync_private.safe_date(btrim(split_part(e->>'term', '–', 1))), make_date(p_year, 7, 1)),
                  make_date(p_year, 7, 1)), make_date(p_year + 1, 6, 30)),
   make_date(p_year + 1, 6, 30)
 from jsonb_array_elements(coalesce(db->'exco', '[]')) e
 cross join lateral (select hdg_sync_private.legacy_role(e->>'role') r) x
 join public.hdg_people p on p.ti_member_id = e->>'memberId'
 join public.hdg_clubs c on c.club_number = hdg_sync_private.club_no(e->>'clubNumber')
 where x.r is not null and not exists (select 1 from public.hdg_roles h
   where h.person_id = p.id and h.role = x.r and h.scope_code = c.club_number and h.year_start = p_year);
 get diagnostics n = row_count; result := result || jsonb_build_object('officer_roles', n);

 -- Area and Division Directors are stored by name only in the shared record. People are matched by member ID,
 -- never by name (rule 9), so these are listed for the maintainer to assign in the app.
 select coalesce(jsonb_agg(jsonb_build_object('role', 'area_director', 'scope', e->>'code', 'name', e->>'director')), '[]')
   into needs_id from jsonb_array_elements(coalesce(db->'areas', '[]')) e where coalesce(btrim(e->>'director'), '') <> '';
 if coalesce(btrim(st->>'divisionDirector'), '') <> '' then
   needs_id := needs_id || jsonb_build_array(jsonb_build_object('role', 'division_director', 'scope', p_division, 'name', st->>'divisionDirector'));
 end if;
 return result || jsonb_build_object('assign_in_app', needs_id);
end $$;

-- Checks that the new tables hold what the shared record holds. Every row should have ok = true.
create or replace function hdg_sync_private.compare_legacy_division(p_division text, p_year int, p_payload jsonb default null)
returns table(check_name text, legacy bigint, copied bigint, ok boolean)
language plpgsql stable security definer set search_path to ''
as $$
declare db jsonb;
begin
 if p_payload is null then select payload into p_payload from public.hdg_sync_state where division_code = p_division; end if;
 db := p_payload->'database';
 return query
 with lc as (select hdg_sync_private.club_no(e->>'number') num, e->>'area' area from jsonb_array_elements(db->'clubs') e
        where hdg_sync_private.club_no(e->>'number') is not null),
 lm as (select * from hdg_sync_private.legacy_memberships(db)),
 nm as (select p.ti_member_id mid, m.club_number club, m.status, p.email, p.nickname from public.hdg_memberships m
        join public.hdg_people p on p.id = m.person_id where m.club_number in (select num from lc)),
 lx as (select distinct e->>'memberId' mid, hdg_sync_private.legacy_role(e->>'role') r, hdg_sync_private.club_no(e->>'clubNumber') club
        from jsonb_array_elements(coalesce(db->'exco', '[]')) e where hdg_sync_private.legacy_role(e->>'role') is not null
          and hdg_sync_private.club_no(e->>'clubNumber') in (select num from (select hdg_sync_private.club_no(c->>'number') num
              from jsonb_array_elements(db->'clubs') c) cc)),
 nx as (select p.ti_member_id mid, r.role r, r.scope_code club from public.hdg_roles r join public.hdg_people p on p.id = r.person_id
        where r.year_start = p_year and r.scope_type = 'club' and r.scope_code in (select num from lc))
 select x.check_name, x.legacy, x.copied, x.legacy = x.copied from (
  select 'clubs in this division'::text, (select count(*) from lc),
    (select count(*) from public.hdg_club_alignment a where a.year_start = p_year and a.club_number in (select num from lc) and left(a.area_code, 1) = p_division), null::boolean
  union all select 'clubs in the same area', (select count(*) from lc),
    (select count(*) from lc join public.hdg_club_alignment a on a.year_start = p_year and a.club_number = lc.num and a.area_code = lc.area), null
  union all select 'people (distinct member IDs)', (select count(distinct mid) from lm), (select count(distinct mid) from nm), null
  union all select 'memberships', (select count(*) from lm), (select count(*) from nm), null
  union all select 'active memberships', (select count(*) from lm where (e->>'active')::boolean),
    (select count(*) from nm where status = 'active'), null
  union all select 'emails identical', (select count(distinct mid) from lm where coalesce(e->>'email', '') <> ''),
    (select count(distinct lm.mid) from lm join nm on nm.mid = lm.mid and nm.club = lm.club where nm.email = lower(btrim(lm.e->>'email'))), null
  union all select 'members with a nickname', (select count(distinct mid) from lm where coalesce(btrim(e->>'nickname'), '') <> ''
      or jsonb_array_length(case when jsonb_typeof(e->'nicknames') = 'array' then e->'nicknames' else '[]' end) > 0),
    (select count(distinct mid) from nm where nickname is not null and mid in (select mid from lm where coalesce(btrim(e->>'nickname'), '') <> ''
      or jsonb_array_length(case when jsonb_typeof(e->'nicknames') = 'array' then e->'nicknames' else '[]' end) > 0)), null
  union all select 'club officers', (select count(*) from lx), (select count(*) from lx where (mid, r, club) in (select * from nx)), null
  union all select 'active members in club ' || lc.num,
    (select count(*) from lm where lm.club = lc.num and (lm.e->>'active')::boolean),
    (select count(*) from nm where nm.club = lc.num and nm.status = 'active'), null from lc
 ) x(check_name, legacy, copied, ok);
end $$;

revoke execute on function hdg_sync_private.club_no(text), hdg_sync_private.safe_date(text), hdg_sync_private.legacy_role(text),
  hdg_sync_private.legacy_memberships(jsonb), hdg_sync_private.copy_legacy_division(text, int, jsonb),
  hdg_sync_private.compare_legacy_division(text, int, jsonb) from public, anon, authenticated;
