-- 011: division council roles (owner decision, 23 November 2026). TEST project first.
-- Every division has a council beside its Director and Area Directors: Assistant Directors for Program Quality and
-- Club Growth, a TLI chair, an Administration Manager and a PR Manager at division level, an advisor, the immediate
-- past Director and similar (Division G has a smaller one). They are one role, 'division_council', with a title.
--  * Read-only by default: they see the people and clubs of their division, and cannot edit.
--  * Exceptions: the maintainer, a district admin or that division's Director can grant editing to one person's role
--    (hdg_grant_role_edit); every change is logged.
--  * Division-level Administration and PR Managers are this role, never the district 'am' / 'prm' roles
--    (the district Administration Manager has Trio-like access across the district).

alter table public.hdg_roles add column if not exists title text check (title is null or length(btrim(title)) between 1 and 80);
alter table public.hdg_roles add column if not exists edit_granted boolean not null default false;

alter table public.hdg_roles drop constraint hdg_roles_role_check;
alter table public.hdg_roles add constraint hdg_roles_role_check check (role in (
  'club_president', 'club_vpe', 'club_vpm', 'club_vppr', 'club_secretary', 'club_treasurer', 'club_saa',
  'area_director', 'division_director', 'division_council',
  'district_director', 'pqd', 'cgd', 'am', 'prm', 'fm', 'lm', 'alignment_chair', 'district_team',
  'maintainer'));
alter table public.hdg_roles drop constraint hdg_roles_check;
alter table public.hdg_roles add constraint hdg_roles_check check (scope_type = case
  when role like 'club\_%' then 'club'
  when role = 'area_director' then 'area'
  when role in ('division_director', 'division_council') then 'division'
  when role = 'maintainer' then 'system'
  else 'district' end);

-- Divisions where the signed-in person holds an active council role (only those with editing granted, if asked).
create or replace function hdg_sync_private.my_council_divisions(p_edit boolean) returns setof text
language sql stable security definer set search_path to ''
as $$
 select r.scope_code from public.hdg_roles r
 where r.role = 'division_council' and r.person_id in (select hdg_sync_private.my_people())
   and r.starts_on <= hdg_sync_private.today() and (r.ends_on is null or r.ends_on >= hdg_sync_private.today())
   and (not p_edit or r.edit_granted)
$$;

-- Edit scope: as before, plus council members whose editing was granted.
create or replace function hdg_sync_private.has_club_scope(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$
 with a as (select hdg_sync_private.club_area(p_club, hdg_sync_private.year_of(hdg_sync_private.today())) area)
 select exists (
   select 1 from hdg_sync_private.my_roles() r, a
   where r.role in ('district_director', 'pqd', 'cgd', 'am')
      or (r.role = 'division_director' and r.scope_code = left(a.area, 1))
      or (r.role = 'area_director' and r.scope_code = a.area)
      or (r.scope_type = 'club' and r.scope_code = p_club))
   or exists (select 1 from a where left(a.area, 1) in (select hdg_sync_private.my_council_divisions(true)))
$$;

-- Read scope: edit scope plus every council member of the club's division.
create or replace function hdg_sync_private.has_club_read_scope(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$
 select hdg_sync_private.has_club_scope(p_club)
   or left(coalesce(hdg_sync_private.club_area(p_club, hdg_sync_private.year_of(hdg_sync_private.today())), ''), 1)
      in (select hdg_sync_private.my_council_divisions(false))
$$;

create or replace function hdg_sync_private.can_see_person(p_person uuid) returns boolean language sql stable security definer set search_path to ''
as $$
 select p_person in (select hdg_sync_private.my_people())
     or hdg_sync_private.is_district_admin()
     or exists (select 1 from public.hdg_memberships m
                where m.person_id = p_person and hdg_sync_private.has_club_read_scope(m.club_number))
$$;

drop policy if exists hdg_freshness_read on public.hdg_import_freshness;
create policy hdg_freshness_read on public.hdg_import_freshness for select to authenticated using (hdg_sync_private.has_club_read_scope(club_number));

create or replace function public.hdg_edit_history(p_table text, p_key text)
returns table(id bigint, at timestamptz, actor uuid, op text, before jsonb, after jsonb, undone_at timestamptz)
language sql stable security definer set search_path to ''
as $$
 select h.id, h.at, h.actor, h.op, h.before, h.after, h.undone_at from hdg_sync_private.edit_history h
 where h.table_name = p_table and h.row_key = p_key
   and case p_table
     when 'hdg_people' then hdg_sync_private.can_see_person(p_key::uuid)
     when 'hdg_clubs' then hdg_sync_private.has_club_read_scope(p_key) or hdg_sync_private.is_district_admin()
     else hdg_sync_private.is_maintainer() end
 order by h.id desc limit 200
$$;

-- A Division Director gives council roles inside their own division (district admins and the maintainer: any).
create or replace function hdg_sync_private.can_manage_role(p_role text, p_scope_type text, p_scope_code text, p_year int)
returns boolean language sql stable security definer set search_path to ''
as $$
 select case
  when p_role = 'maintainer' then hdg_sync_private.is_maintainer()
  when hdg_sync_private.is_maintainer() or hdg_sync_private.is_district_admin() then true
  when p_role = 'division_council' then exists (select 1 from hdg_sync_private.my_roles() r
      where r.role = 'division_director' and r.scope_code = p_scope_code)
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

create or replace function public.hdg_assign_role(p_person uuid, p_role text, p_scope_code text, p_year int)
returns uuid language plpgsql security definer set search_path to ''
as $$
declare scope text; y public.hdg_program_years%rowtype; today date := hdg_sync_private.today(); new_id uuid;
begin
 scope := case when p_role like 'club\_%' then 'club' when p_role = 'area_director' then 'area'
   when p_role in ('division_director', 'division_council') then 'division' when p_role = 'maintainer' then 'system' else 'district' end;
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

-- Title of a council role (e.g. "Assistant Director Program Quality"), set by whoever may manage that role.
create or replace function public.hdg_set_role_title(p_role_id uuid, p_title text) returns void
language plpgsql security definer set search_path to ''
as $$
declare r public.hdg_roles%rowtype;
begin
 select * into r from public.hdg_roles where id = p_role_id;
 if not found or not hdg_sync_private.can_manage_role(r.role, r.scope_type, r.scope_code, coalesce(r.year_start, 0)) then
   raise exception 'You cannot change this role' using errcode = '42501';
 end if;
 update public.hdg_roles set title = nullif(left(btrim(coalesce(p_title, '')), 80), '') where id = p_role_id;
end $$;

-- Exception: allow (or withdraw) editing for one council role. Maintainer, district admin or that division's Director.
create or replace function public.hdg_grant_role_edit(p_role_id uuid, p_granted boolean) returns void
language plpgsql security definer set search_path to ''
as $$
declare r public.hdg_roles%rowtype;
begin
 select * into r from public.hdg_roles where id = p_role_id;
 if not found or r.role <> 'division_council' then raise exception 'Only council roles have an editing exception' using errcode = '22023'; end if;
 if not hdg_sync_private.can_manage_role(r.role, r.scope_type, r.scope_code, coalesce(r.year_start, 0)) then
   raise exception 'You cannot change this role' using errcode = '42501';
 end if;
 update public.hdg_roles set edit_granted = coalesce(p_granted, false) where id = p_role_id;
 insert into hdg_sync_private.access_log(actor, action, detail)
 values (auth.uid(), 'council edit ' || case when p_granted then 'granted' else 'withdrawn' end,
         jsonb_build_object('role_id', p_role_id, 'division', r.scope_code));
end $$;

-- Leadership directory: council members appear with their title.
drop function if exists public.hdg_leadership_directory();
create function public.hdg_leadership_directory()
returns table(name text, nickname text, role text, title text, scope_code text, year_start int)
language sql stable security definer set search_path to ''
as $$
 select p.name, p.nickname, r.role, r.title, r.scope_code, r.year_start from public.hdg_roles r join public.hdg_people p on p.id = r.person_id
 where hdg_sync_private.is_district_user() and r.role not in ('maintainer', 'district_team')
   and r.starts_on <= hdg_sync_private.today() and (r.ends_on is null or r.ends_on >= hdg_sync_private.today())
 order by r.scope_type, r.scope_code, r.role, r.title
$$;

-- The setup page also lists the division of a council member.
create or replace function public.hdg_my_context()
returns jsonb language sql stable security definer set search_path to ''
as $$
 with me as (select p.id, p.name, p.nickname, p.provisional from public.hdg_people p
             where p.id in (select hdg_sync_private.my_people()) order by p.provisional limit 1),
 r as (select * from hdg_sync_private.my_roles()),
 y as (select hdg_sync_private.year_of(hdg_sync_private.today()) yr),
 divs as (
   select distinct d.code from public.hdg_divisions d, y
   where exists (select 1 from r where r.role in ('maintainer', 'district_director', 'pqd', 'cgd', 'am', 'prm', 'fm', 'lm', 'alignment_chair'))
      or exists (select 1 from r where r.role in ('division_director', 'division_council') and r.scope_code = d.code)
      or exists (select 1 from r where r.role = 'area_director' and left(r.scope_code, 1) = d.code)
      or exists (select 1 from r join public.hdg_club_alignment a on a.club_number = r.scope_code and a.year_start = y.yr
                 where r.scope_type = 'club' and left(a.area_code, 1) = d.code))
 select jsonb_build_object(
   'name', (select coalesce(nickname, name) from me),
   'provisional', coalesce((select provisional from me), false),
   'roles', coalesce((select jsonb_agg(jsonb_build_object('role', rr.role, 'scope', rr.scope_code, 'title', rr.title) order by rr.role)
                      from public.hdg_roles rr where rr.person_id in (select hdg_sync_private.my_people())
                        and rr.starts_on <= hdg_sync_private.today() and (rr.ends_on is null or rr.ends_on >= hdg_sync_private.today())), '[]'),
   'divisions', coalesce((select jsonb_agg(jsonb_build_object(
       'code', d.code, 'name', dv.name,
       'clubs', (select count(*) from public.hdg_club_alignment a, y where a.year_start = y.yr and a.status = 'approved' and left(a.area_code, 1) = d.code),
       'areas', (select count(*) from public.hdg_areas ar, y where ar.year_start = y.yr and ar.division_code = d.code),
       'members', (select count(distinct m.person_id) from public.hdg_memberships m join public.hdg_club_alignment a
                     on a.club_number = m.club_number join y on a.year_start = y.yr
                   where left(a.area_code, 1) = d.code and m.status = 'active')) order by d.code)
     from divs d join public.hdg_divisions dv on dv.code = d.code), '[]'))
 where exists (select 1 from me)
$$;

revoke execute on function hdg_sync_private.my_council_divisions(boolean), hdg_sync_private.has_club_read_scope(text),
  public.hdg_set_role_title(uuid, text), public.hdg_grant_role_edit(uuid, boolean), public.hdg_leadership_directory()
  from public, anon;
grant execute on function hdg_sync_private.my_council_divisions(boolean), hdg_sync_private.has_club_read_scope(text),
  public.hdg_set_role_title(uuid, text), public.hdg_grant_role_edit(uuid, boolean), public.hdg_leadership_directory()
  to authenticated;
