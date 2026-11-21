-- 002: per-record foundation for Division G, Division K and District 87 (Phase 0, steps 3 to 6).
-- Rules: project/DISTRICT_PLAN.md. Test project first; production only after the owner approves.
-- Additive: the existing hdg_sync_state record, its revision history and every v645 function are untouched.

-- Program years run 1 July to 30 June. year_start 2026 means 2026-27.
create table public.hdg_program_years (
 year_start int primary key check (year_start between 2020 and 2100),
 transition_opens date not null,          -- 15 May, or the first day of the District conference
 starts_on date generated always as (make_date(year_start, 7, 1)) stored,
 ends_on date generated always as (make_date(year_start + 1, 6, 30)) stored,
 alignment_approved_at timestamptz,
 alignment_approved_by uuid,
 check (transition_opens between make_date(year_start, 1, 1) and make_date(year_start, 6, 30)));

create table public.hdg_divisions (
 code text primary key check (code ~ '^[A-Z]$'),
 district_code text not null default '87',
 name text not null,
 config jsonb not null default '{}' check (jsonb_typeof(config) = 'object'),   -- branding and defaults
 updated_at timestamptz not null default now(), updated_by uuid);

-- Clubs by TI club number. Names can change; history is kept in the edit log.
create table public.hdg_clubs (
 club_number text primary key check (club_number ~ '^[1-9][0-9]*$'),
 name text not null check (length(btrim(name)) between 1 and 160),
 city text,
 timezone text not null default 'Asia/Makassar'
   check (timezone in ('Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura', 'Asia/Kuala_Lumpur', 'Asia/Brunei')),
 currency text not null default 'IDR' check (currency in ('IDR', 'MYR', 'BND')),
 details jsonb not null default '{}' check (jsonb_typeof(details) = 'object'),  -- venue, schedule, fee, links, logo
 chartered_on date,
 closed_on date,
 updated_at timestamptz not null default now(), updated_by uuid);

-- Areas and club alignment are stored per program year, so realignment never rewrites history.
create table public.hdg_areas (
 year_start int not null references public.hdg_program_years,
 code text not null check (code ~ '^[A-Z][0-9]{1,2}$'),
 division_code text not null references public.hdg_divisions,
 primary key (year_start, code),
 check (left(code, 1) = division_code));

create table public.hdg_club_alignment (
 year_start int not null references public.hdg_program_years,
 club_number text not null references public.hdg_clubs,
 area_code text not null,
 status text not null default 'approved' check (status in ('draft', 'approved')),
 updated_at timestamptz not null default now(), updated_by uuid,
 primary key (year_start, club_number),
 foreign key (year_start, area_code) references public.hdg_areas);

-- People are matched by Toastmasters member ID. No street address or phone column exists by design.
create table public.hdg_people (
 id uuid primary key default gen_random_uuid(),
 ti_member_id text unique check (ti_member_id ~ '^[0-9A-Za-z]{1,20}$'),
 name text not null check (length(btrim(name)) between 1 and 160),   -- from TI
 email text check (email = lower(btrim(email))),                      -- from TI
 city text,                                                           -- from TI, city only
 user_id uuid unique references auth.users on delete set null,
 -- Manual fields: imports never overwrite these.
 nickname text check (length(nickname) <= 80),
 aliases text[] not null default '{}' check (cardinality(aliases) <= 20),
 pronunciation text check (length(pronunciation) <= 160),
 photo_path text,
 photo_consent boolean not null default false,
 notes text check (length(notes) <= 2000),
 -- TI fields corrected by hand: {field: {value, by, at}}. The next import asks before overwriting.
 hand_corrected jsonb not null default '{}' check (jsonb_typeof(hand_corrected) = 'object'),
 updated_at timestamptz not null default now(), updated_by uuid);
create index hdg_people_email on public.hdg_people (email);

-- One person can belong to several clubs, in any division. Past memberships are kept.
create table public.hdg_memberships (
 id uuid primary key default gen_random_uuid(),
 person_id uuid not null references public.hdg_people on delete cascade,
 club_number text not null references public.hdg_clubs,
 status text not null check (status in ('active', 'lapsed', 'past')),
 joined_on date,
 paid_until date,
 source_as_of date,                        -- date of the TI export this came from
 updated_at timestamptz not null default now(), updated_by uuid,
 unique (person_id, club_number));
create index hdg_memberships_club on public.hdg_memberships (club_number);

-- Roles with terms. Officers take over on 1 July and drop back to member on 30 June automatically,
-- because a role is active only between starts_on and ends_on. The maintainer role has no end date.
create table public.hdg_roles (
 id uuid primary key default gen_random_uuid(),
 person_id uuid not null references public.hdg_people on delete cascade,
 role text not null check (role in (
   'club_president', 'club_vpe', 'club_vpm', 'club_vppr', 'club_secretary', 'club_treasurer', 'club_saa',
   'area_director', 'division_director',
   'district_director', 'pqd', 'cgd', 'am', 'prm', 'fm', 'lm', 'alignment_chair', 'district_team',
   'maintainer')),
 scope_type text not null,
 scope_code text not null,
 year_start int references public.hdg_program_years,
 starts_on date not null,
 ends_on date,
 entered_by uuid,
 entered_at timestamptz not null default now(),
 check (scope_type = case
   when role like 'club\_%' then 'club'
   when role = 'area_director' then 'area'
   when role = 'division_director' then 'division'
   when role = 'maintainer' then 'system'
   else 'district' end),
 check ((role = 'maintainer') = (year_start is null)),
 check ((role = 'maintainer') = (ends_on is null)),
 check (ends_on is null or ends_on >= starts_on));
create index hdg_roles_person on public.hdg_roles (person_id);

-- Freshest data wins: the newest TI export date per club and kind.
create table public.hdg_import_freshness (
 club_number text not null references public.hdg_clubs,
 kind text not null check (kind in ('roster', 'officers')),
 as_of date not null,
 imported_at timestamptz not null default now(),
 imported_by uuid,
 primary key (club_number, kind));

-- Edit history (who, what, when) and the maintainer's access log. Not readable directly.
create table hdg_sync_private.edit_history (
 id bigint generated always as identity primary key,
 at timestamptz not null default now(),
 actor uuid,
 table_name text not null,
 row_key text not null,
 op text not null,
 before jsonb,
 after jsonb,
 undone_at timestamptz,
 undone_by uuid);
create index edit_history_row on hdg_sync_private.edit_history (table_name, row_key);

create table hdg_sync_private.access_log (
 id bigint generated always as identity primary key,
 at timestamptz not null default now(),
 actor uuid not null,
 action text not null,
 detail jsonb not null default '{}');

alter table public.hdg_program_years enable row level security;
alter table public.hdg_divisions enable row level security;
alter table public.hdg_clubs enable row level security;
alter table public.hdg_areas enable row level security;
alter table public.hdg_club_alignment enable row level security;
alter table public.hdg_people enable row level security;
alter table public.hdg_memberships enable row level security;
alter table public.hdg_roles enable row level security;
alter table public.hdg_import_freshness enable row level security;
alter table hdg_sync_private.edit_history enable row level security;
alter table hdg_sync_private.access_log enable row level security;

-- ---------------------------------------------------------------- helpers
create function hdg_sync_private.today() returns date language sql stable set search_path to ''
as $$ select (now() at time zone 'Asia/Makassar')::date $$;

create function hdg_sync_private.year_of(d date) returns int language sql immutable set search_path to ''
as $$ select extract(year from d)::int - case when extract(month from d) < 7 then 1 else 0 end $$;

create function public.hdg_timezone_label(tz text) returns text language sql immutable set search_path to ''
as $$ select case tz when 'Asia/Jakarta' then 'WIB' when 'Asia/Makassar' then 'WITA' when 'Asia/Jayapura' then 'WIT'
  when 'Asia/Kuala_Lumpur' then 'MYT' when 'Asia/Brunei' then 'BNT' end $$;

-- The people records that belong to the signed-in account: linked, or matched by confirmed email.
create function hdg_sync_private.my_people() returns setof uuid language sql stable security definer set search_path to ''
as $$
 select p.id from public.hdg_people p join auth.users u on u.id = auth.uid()
 where p.user_id = u.id
    or (p.user_id is null and u.email_confirmed_at is not null and p.email = lower(btrim(u.email)))
$$;

-- Active roles of the signed-in account today.
create function hdg_sync_private.my_roles() returns table(role text, scope_type text, scope_code text)
language sql stable security definer set search_path to ''
as $$
 select r.role, r.scope_type, r.scope_code from public.hdg_roles r
 where r.person_id in (select hdg_sync_private.my_people())
   and r.starts_on <= hdg_sync_private.today()
   and (r.ends_on is null or r.ends_on >= hdg_sync_private.today())
$$;

create function hdg_sync_private.is_maintainer() returns boolean language sql stable security definer set search_path to ''
as $$ select exists (select 1 from hdg_sync_private.my_roles() where role = 'maintainer') $$;

-- District-wide member access: Trio and Administration Manager (rule table in DISTRICT_PLAN.md).
create function hdg_sync_private.is_district_admin() returns boolean language sql stable security definer set search_path to ''
as $$ select exists (select 1 from hdg_sync_private.my_roles() where role in ('district_director', 'pqd', 'cgd', 'am')) $$;

create function hdg_sync_private.club_area(p_club text, p_year int) returns text language sql stable security definer set search_path to ''
as $$ select area_code from public.hdg_club_alignment where club_number = p_club and year_start = p_year and status = 'approved' $$;

-- May the signed-in account see and edit the members of this club (this program year)?
create function hdg_sync_private.has_club_scope(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$
 with a as (select hdg_sync_private.club_area(p_club, hdg_sync_private.year_of(hdg_sync_private.today())) area)
 select exists (
   select 1 from hdg_sync_private.my_roles() r, a
   where r.role in ('district_director', 'pqd', 'cgd', 'am')
      or (r.role = 'division_director' and r.scope_code = left(a.area, 1))
      or (r.role = 'area_director' and r.scope_code = a.area)
      or (r.scope_type = 'club' and r.scope_code = p_club))
$$;

create function hdg_sync_private.can_see_person(p_person uuid) returns boolean language sql stable security definer set search_path to ''
as $$
 select p_person in (select hdg_sync_private.my_people())
     or hdg_sync_private.is_district_admin()
     or exists (select 1 from public.hdg_memberships m
                where m.person_id = p_person and hdg_sync_private.has_club_scope(m.club_number))
$$;

-- Signed in with a confirmed email and known to the district (any person record or role).
create function hdg_sync_private.is_district_user() returns boolean language sql stable security definer set search_path to ''
as $$ select exists (select 1 from hdg_sync_private.my_people()) $$;

-- ---------------------------------------------------------------- read policies
create policy hdg_years_read on public.hdg_program_years for select to authenticated using ((select hdg_sync_private.is_district_user()));
create policy hdg_divisions_read on public.hdg_divisions for select to authenticated using ((select hdg_sync_private.is_district_user()));
create policy hdg_clubs_read on public.hdg_clubs for select to authenticated using ((select hdg_sync_private.is_district_user()));
create policy hdg_areas_read on public.hdg_areas for select to authenticated using ((select hdg_sync_private.is_district_user()));
create policy hdg_alignment_read on public.hdg_club_alignment for select to authenticated
 using ((select hdg_sync_private.is_district_user()) and (status = 'approved'
   or exists (select 1 from hdg_sync_private.my_roles() r where r.role in ('district_director', 'pqd', 'cgd', 'am', 'alignment_chair', 'maintainer'))));
create policy hdg_roles_read on public.hdg_roles for select to authenticated using ((select hdg_sync_private.is_district_user()));
create policy hdg_people_read on public.hdg_people for select to authenticated using (hdg_sync_private.can_see_person(id));
create policy hdg_memberships_read on public.hdg_memberships for select to authenticated using (hdg_sync_private.can_see_person(person_id));
create policy hdg_freshness_read on public.hdg_import_freshness for select to authenticated using (hdg_sync_private.has_club_scope(club_number));

revoke all on public.hdg_program_years, public.hdg_divisions, public.hdg_clubs, public.hdg_areas, public.hdg_club_alignment,
  public.hdg_people, public.hdg_memberships, public.hdg_roles, public.hdg_import_freshness from anon, authenticated;
grant select on public.hdg_program_years, public.hdg_divisions, public.hdg_clubs, public.hdg_areas, public.hdg_club_alignment,
  public.hdg_people, public.hdg_memberships, public.hdg_roles, public.hdg_import_freshness to authenticated;
-- All writes go through the functions below; no table accepts direct inserts or updates.

-- ---------------------------------------------------------------- edit history
create function hdg_sync_private.log_edit() returns trigger language plpgsql security definer set search_path to ''
as $$
declare k text; r jsonb;
begin
 r := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
 k := case tg_table_name
   when 'hdg_clubs' then r->>'club_number'
   when 'hdg_club_alignment' then (r->>'year_start') || ':' || (r->>'club_number')
   else r->>'id' end;
 insert into hdg_sync_private.edit_history(actor, table_name, row_key, op, before, after)
 values (auth.uid(), tg_table_name, k, tg_op,
   case when tg_op <> 'INSERT' then to_jsonb(old) end, case when tg_op <> 'DELETE' then to_jsonb(new) end);
 return coalesce(new, old);
end $$;
create trigger hdg_people_history after insert or update or delete on public.hdg_people for each row execute function hdg_sync_private.log_edit();
create trigger hdg_memberships_history after insert or update or delete on public.hdg_memberships for each row execute function hdg_sync_private.log_edit();
create trigger hdg_clubs_history after insert or update or delete on public.hdg_clubs for each row execute function hdg_sync_private.log_edit();
create trigger hdg_roles_history after insert or update or delete on public.hdg_roles for each row execute function hdg_sync_private.log_edit();
create trigger hdg_alignment_history after insert or update or delete on public.hdg_club_alignment for each row execute function hdg_sync_private.log_edit();

-- ---------------------------------------------------------------- write functions
-- Every update names the version it is based on (updated_at), so two people editing at once
-- never silently overwrite each other: the second save is refused and must reload.

create function public.hdg_update_my_profile(p_person uuid, p_patch jsonb, p_expected_updated_at timestamptz)
returns timestamptz language plpgsql security definer set search_path to ''
as $$
declare result timestamptz;
begin
 if p_person not in (select hdg_sync_private.my_people()) then
   raise exception 'You can only edit your own profile here' using errcode = '42501';
 end if;
 if jsonb_typeof(p_patch) is distinct from 'object'
    or (p_patch - array['nickname', 'aliases', 'pronunciation', 'photo_path', 'photo_consent']) <> '{}'::jsonb then
   raise exception 'Only nickname, aliases, pronunciation, photo and photo consent can be changed' using errcode = '22023';
 end if;
 update public.hdg_people set
   nickname = case when p_patch ? 'nickname' then nullif(btrim(p_patch->>'nickname'), '') else nickname end,
   aliases = case when p_patch ? 'aliases' then array(select btrim(x) from jsonb_array_elements_text(p_patch->'aliases') x where btrim(x) <> '') else aliases end,
   pronunciation = case when p_patch ? 'pronunciation' then nullif(btrim(p_patch->>'pronunciation'), '') else pronunciation end,
   photo_path = case when p_patch ? 'photo_path' then nullif(p_patch->>'photo_path', '') else photo_path end,
   photo_consent = case when p_patch ? 'photo_consent' then (p_patch->>'photo_consent')::boolean else photo_consent end,
   updated_at = now(), updated_by = auth.uid()
 where id = p_person and updated_at = p_expected_updated_at
 returning updated_at into result;
 if result is null then
   raise exception 'Someone else changed this profile. Reload and try again.' using errcode = 'PT409';
 end if;
 return result;
end $$;

-- Leaders edit people in their scope. TI fields corrected by hand are recorded in hand_corrected.
create function public.hdg_update_person(p_person uuid, p_patch jsonb, p_expected_updated_at timestamptz)
returns timestamptz language plpgsql security definer set search_path to ''
as $$
declare result timestamptz; corrected jsonb := '{}'; f text;
begin
 if not (hdg_sync_private.is_district_admin() or exists (
     select 1 from public.hdg_memberships m where m.person_id = p_person and hdg_sync_private.has_club_scope(m.club_number))) then
   raise exception 'This person is outside your scope' using errcode = '42501';
 end if;
 if jsonb_typeof(p_patch) is distinct from 'object' or (p_patch - array['nickname', 'aliases', 'pronunciation', 'photo_path',
     'photo_consent', 'notes', 'name', 'email', 'city', 'ti_member_id']) <> '{}'::jsonb then
   raise exception 'Unknown or protected field' using errcode = '22023';
 end if;
 foreach f in array array['name', 'email', 'city', 'ti_member_id'] loop
   if p_patch ? f then
     corrected := corrected || jsonb_build_object(f, jsonb_build_object('value', p_patch->f, 'by', auth.uid(), 'at', now()));
   end if;
 end loop;
 update public.hdg_people set
   nickname = case when p_patch ? 'nickname' then nullif(btrim(p_patch->>'nickname'), '') else nickname end,
   aliases = case when p_patch ? 'aliases' then array(select btrim(x) from jsonb_array_elements_text(p_patch->'aliases') x where btrim(x) <> '') else aliases end,
   pronunciation = case when p_patch ? 'pronunciation' then nullif(btrim(p_patch->>'pronunciation'), '') else pronunciation end,
   photo_path = case when p_patch ? 'photo_path' then nullif(p_patch->>'photo_path', '') else photo_path end,
   photo_consent = case when p_patch ? 'photo_consent' then (p_patch->>'photo_consent')::boolean else photo_consent end,
   notes = case when p_patch ? 'notes' then nullif(btrim(p_patch->>'notes'), '') else notes end,
   name = case when p_patch ? 'name' then btrim(p_patch->>'name') else name end,
   email = case when p_patch ? 'email' then nullif(lower(btrim(p_patch->>'email')), '') else email end,
   city = case when p_patch ? 'city' then nullif(btrim(p_patch->>'city'), '') else city end,
   ti_member_id = case when p_patch ? 'ti_member_id' then nullif(btrim(p_patch->>'ti_member_id'), '') else ti_member_id end,
   hand_corrected = hand_corrected || corrected,
   updated_at = now(), updated_by = auth.uid()
 where id = p_person and updated_at = p_expected_updated_at
 returning updated_at into result;
 if result is null then
   raise exception 'Someone else changed this person. Reload and try again.' using errcode = 'PT409';
 end if;
 return result;
end $$;

create function public.hdg_update_club(p_club text, p_patch jsonb, p_expected_updated_at timestamptz)
returns timestamptz language plpgsql security definer set search_path to ''
as $$
declare result timestamptz;
begin
 if not (hdg_sync_private.has_club_scope(p_club) or hdg_sync_private.is_district_admin()) then
   raise exception 'This club is outside your scope' using errcode = '42501';
 end if;
 if jsonb_typeof(p_patch) is distinct from 'object'
    or (p_patch - array['name', 'city', 'timezone', 'currency', 'details']) <> '{}'::jsonb
    or (p_patch ? 'details' and jsonb_typeof(p_patch->'details') <> 'object') then
   raise exception 'Unknown club field' using errcode = '22023';
 end if;
 update public.hdg_clubs set
   name = coalesce(nullif(btrim(p_patch->>'name'), ''), name),
   city = case when p_patch ? 'city' then nullif(btrim(p_patch->>'city'), '') else city end,
   timezone = coalesce(p_patch->>'timezone', timezone),
   currency = coalesce(p_patch->>'currency', currency),
   details = case when p_patch ? 'details' then details || (p_patch->'details') else details end,
   updated_at = now(), updated_by = auth.uid()
 where club_number = p_club and updated_at = p_expected_updated_at
 returning updated_at into result;
 if result is null then
   raise exception 'Someone else changed this club. Reload and try again.' using errcode = 'PT409';
 end if;
 return result;
end $$;

-- Who may give a role: the maintainer and district admins give any role (only a maintainer gives
-- maintainer); a Division Director gives area and club roles inside their division; an Area Director
-- gives club roles inside their area. Next year's roles can be entered once the transition window opens.
create function hdg_sync_private.can_manage_role(p_role text, p_scope_type text, p_scope_code text, p_year int)
returns boolean language sql stable security definer set search_path to ''
as $$
 select case
  when p_role = 'maintainer' then hdg_sync_private.is_maintainer()
  when hdg_sync_private.is_maintainer() or hdg_sync_private.is_district_admin() then true
  when p_scope_type = 'area' then exists (select 1 from hdg_sync_private.my_roles() r
      where r.role = 'division_director' and r.scope_code = left(p_scope_code, 1))
  when p_scope_type = 'club' then exists (
      select 1 from hdg_sync_private.my_roles() r
      cross join lateral (select coalesce(hdg_sync_private.club_area(p_scope_code, p_year),
                                          hdg_sync_private.club_area(p_scope_code, p_year - 1)) area) a
      where (r.role = 'division_director' and r.scope_code = left(a.area, 1))
         or (r.role = 'area_director' and r.scope_code = a.area))
  else false end
$$;

create function public.hdg_assign_role(p_person uuid, p_role text, p_scope_code text, p_year int)
returns uuid language plpgsql security definer set search_path to ''
as $$
declare scope text; y public.hdg_program_years%rowtype; today date := hdg_sync_private.today(); new_id uuid;
begin
 scope := case when p_role like 'club\_%' then 'club' when p_role = 'area_director' then 'area'
   when p_role = 'division_director' then 'division' when p_role = 'maintainer' then 'system' else 'district' end;
 if not hdg_sync_private.can_manage_role(p_role, scope, p_scope_code, p_year) then
   raise exception 'You cannot give this role' using errcode = '42501';
 end if;
 if p_role = 'maintainer' then
   insert into public.hdg_roles(person_id, role, scope_type, scope_code, year_start, starts_on, ends_on, entered_by)
   values (p_person, p_role, 'system', 'system', null, today, null, auth.uid()) returning id into new_id;
   return new_id;
 end if;
 select * into y from public.hdg_program_years where year_start = p_year;
 if not found then raise exception 'Unknown program year' using errcode = '22023'; end if;
 if today > y.ends_on then raise exception 'That program year has ended' using errcode = '22023'; end if;
 if today < y.transition_opens then
   raise exception 'Officers for % can be entered from %', p_year, y.transition_opens using errcode = '22023';
 end if;
 insert into public.hdg_roles(person_id, role, scope_type, scope_code, year_start, starts_on, ends_on, entered_by)
 values (p_person, p_role, scope, p_scope_code, p_year, greatest(y.starts_on, today), y.ends_on, auth.uid())
 returning id into new_id;
 return new_id;
end $$;

create function public.hdg_end_role(p_role_id uuid, p_ends_on date)
returns void language plpgsql security definer set search_path to ''
as $$
declare r public.hdg_roles%rowtype;
begin
 select * into r from public.hdg_roles where id = p_role_id;
 if not found or not hdg_sync_private.can_manage_role(r.role, r.scope_type, r.scope_code, coalesce(r.year_start, 0)) then
   raise exception 'You cannot change this role' using errcode = '42501';
 end if;
 if r.role = 'maintainer' and (select count(*) from public.hdg_roles where role = 'maintainer'
     and (ends_on is null or ends_on >= hdg_sync_private.today())) <= 1 then
   raise exception 'The last maintainer cannot be removed' using errcode = '42501';
 end if;
 update public.hdg_roles set ends_on = greatest(starts_on, p_ends_on) where id = p_role_id;
end $$;

-- Realignment: draft next year's alignment, then approve it. Takes effect on 1 July with the officer handover.
create function hdg_sync_private.can_realign() returns boolean language sql stable security definer set search_path to ''
as $$ select exists (select 1 from hdg_sync_private.my_roles()
  where role in ('maintainer', 'district_director', 'pqd', 'cgd', 'am', 'alignment_chair')) $$;

create function public.hdg_set_alignment(p_year int, p_club text, p_area text)
returns void language plpgsql security definer set search_path to ''
as $$
declare current_year int := hdg_sync_private.year_of(hdg_sync_private.today());
begin
 if not hdg_sync_private.can_realign() then raise exception 'Realignment authority required' using errcode = '42501'; end if;
 if p_year < current_year then raise exception 'Past program years cannot be realigned' using errcode = '22023'; end if;
 if p_year = current_year and exists (select 1 from public.hdg_club_alignment where year_start = p_year and club_number = p_club) then
   raise exception 'Mid-year changes are only for new charters; realign for next year instead' using errcode = '22023';
 end if;
 insert into public.hdg_club_alignment(year_start, club_number, area_code, status, updated_by)
 values (p_year, p_club, p_area, case when p_year = current_year then 'approved' else 'draft' end, auth.uid())
 on conflict (year_start, club_number) do update set area_code = excluded.area_code, status = excluded.status,
   updated_at = now(), updated_by = auth.uid();
end $$;

create function public.hdg_approve_alignment(p_year int)
returns int language plpgsql security definer set search_path to ''
as $$
declare n int;
begin
 if not hdg_sync_private.can_realign() then raise exception 'Realignment authority required' using errcode = '42501'; end if;
 update public.hdg_club_alignment set status = 'approved', updated_at = now(), updated_by = auth.uid()
 where year_start = p_year and status = 'draft';
 get diagnostics n = row_count;
 update public.hdg_program_years set alignment_approved_at = now(), alignment_approved_by = auth.uid() where year_start = p_year;
 return n;
end $$;

-- Undo an edit to a person or club: the person who made it, a district admin, or the maintainer.
create function public.hdg_undo_edit(p_history_id bigint)
returns void language plpgsql security definer set search_path to ''
as $$
declare h hdg_sync_private.edit_history%rowtype;
begin
 select * into h from hdg_sync_private.edit_history where id = p_history_id and undone_at is null and op = 'UPDATE';
 if not found or h.table_name not in ('hdg_people', 'hdg_clubs') then
   raise exception 'This edit cannot be undone here' using errcode = '22023';
 end if;
 if not (h.actor = auth.uid() or hdg_sync_private.is_district_admin() or hdg_sync_private.is_maintainer()) then
   raise exception 'Only the person who made this edit, a district admin or the maintainer can undo it' using errcode = '42501';
 end if;
 if h.table_name = 'hdg_people' then
   update public.hdg_people t set (nickname, aliases, pronunciation, photo_path, photo_consent, notes, name, email, city,
       ti_member_id, hand_corrected, updated_at, updated_by)
     = (select r.nickname, r.aliases, r.pronunciation, r.photo_path, r.photo_consent, r.notes, r.name, r.email, r.city,
         r.ti_member_id, r.hand_corrected, now(), auth.uid()
        from jsonb_populate_record(null::public.hdg_people, h.before) r)
   where t.id = (h.before->>'id')::uuid and t.updated_at = (h.after->>'updated_at')::timestamptz;
 else
   update public.hdg_clubs t set (name, city, timezone, currency, details, updated_at, updated_by)
     = (select r.name, r.city, r.timezone, r.currency, r.details, now(), auth.uid()
        from jsonb_populate_record(null::public.hdg_clubs, h.before) r)
   where t.club_number = h.before->>'club_number' and t.updated_at = (h.after->>'updated_at')::timestamptz;
 end if;
 if not found then raise exception 'This record has changed since; undo the later edit first' using errcode = 'PT409'; end if;
 update hdg_sync_private.edit_history set undone_at = now(), undone_by = auth.uid() where id = p_history_id;
end $$;

-- Edit history for one record, for anyone who can see that record.
create function public.hdg_edit_history(p_table text, p_key text)
returns table(id bigint, at timestamptz, actor uuid, op text, before jsonb, after jsonb, undone_at timestamptz)
language sql stable security definer set search_path to ''
as $$
 select h.id, h.at, h.actor, h.op, h.before, h.after, h.undone_at from hdg_sync_private.edit_history h
 where h.table_name = p_table and h.row_key = p_key
   and case p_table
     when 'hdg_people' then hdg_sync_private.can_see_person(p_key::uuid)
     when 'hdg_clubs' then hdg_sync_private.has_club_scope(p_key) or hdg_sync_private.is_district_admin()
     else hdg_sync_private.is_maintainer() end
 order by h.id desc limit 200
$$;

-- The maintainer does not read member records through normal access. This function logs every use.
create function public.hdg_maintainer_people(p_division text)
returns setof public.hdg_people language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 insert into hdg_sync_private.access_log(actor, action, detail)
 values (auth.uid(), 'read people', jsonb_build_object('division', p_division));
 return query select p.* from public.hdg_people p where exists (
   select 1 from public.hdg_memberships m join public.hdg_club_alignment a on a.club_number = m.club_number
   where m.person_id = p.id and a.year_start = hdg_sync_private.year_of(hdg_sync_private.today())
     and a.status = 'approved' and left(a.area_code, 1) = p_division);
end $$;

-- Leadership directory: names and roles are visible to every district user.
create function public.hdg_leadership_directory()
returns table(name text, nickname text, role text, scope_code text, year_start int)
language sql stable security definer set search_path to ''
as $$
 select p.name, p.nickname, r.role, r.scope_code, r.year_start from public.hdg_roles r join public.hdg_people p on p.id = r.person_id
 where hdg_sync_private.is_district_user() and r.role not in ('maintainer', 'district_team')
   and r.starts_on <= hdg_sync_private.today() and (r.ends_on is null or r.ends_on >= hdg_sync_private.today())
 order by r.scope_type, r.scope_code, r.role
$$;

revoke execute on all functions in schema public, hdg_sync_private from public, anon;
grant execute on function public.hdg_update_my_profile(uuid, jsonb, timestamptz), public.hdg_update_person(uuid, jsonb, timestamptz),
  public.hdg_update_club(text, jsonb, timestamptz), public.hdg_assign_role(uuid, text, text, int), public.hdg_end_role(uuid, date),
  public.hdg_set_alignment(int, text, text), public.hdg_approve_alignment(int), public.hdg_undo_edit(bigint),
  public.hdg_edit_history(text, text), public.hdg_maintainer_people(text), public.hdg_leadership_directory(),
  public.hdg_timezone_label(text) to authenticated;
-- RLS policies call these helpers as the signed-in user.
grant execute on function hdg_sync_private.today(), hdg_sync_private.year_of(date), hdg_sync_private.my_people(),
  hdg_sync_private.my_roles(), hdg_sync_private.is_maintainer(), hdg_sync_private.is_district_admin(),
  hdg_sync_private.club_area(text, int), hdg_sync_private.has_club_scope(text), hdg_sync_private.can_see_person(uuid),
  hdg_sync_private.is_district_user(), hdg_sync_private.can_manage_role(text, text, text, int),
  hdg_sync_private.can_realign() to authenticated;
-- v645 functions keep their original grants.
grant execute on function public.hdg_access_mode(), public.hdg_manage_ballot(text,text,text,jsonb), public.hdg_manage_officer(text,boolean),
  public.hdg_save_web_state(bigint,jsonb,uuid), public.hdg_member_community() to authenticated;
grant execute on function public.hdg_cast_ballot(uuid,uuid,jsonb), public.hdg_open_ballot(uuid) to anon, authenticated;
grant execute on function hdg_sync_private.manage_officer(text,boolean), hdg_sync_private.save_web_state(bigint,jsonb,uuid) to authenticated;
