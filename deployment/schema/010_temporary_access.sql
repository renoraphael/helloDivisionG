-- 010: temporary access for divisions that are being set up (Phase 1; owner decision 21 November 2026).
-- Before a division's membership and officer lists are imported (Division K: after the owner's call with its
-- Director), the maintainer can give a leader a provisional person record and a role. Signing in then gives
-- access mode 'setup': the launcher shows the division as being set up, with its clubs, and "import members first".
-- Division G is unchanged: 'leader' and 'member' are decided exactly as before; 'setup' only replaces 'none'.
-- TEST project first; production with the owner's approval.

alter table public.hdg_people add column if not exists provisional boolean not null default false;
comment on column public.hdg_people.provisional is
  'Added by hand before the membership import (no member ID yet). The import matches it by email and fills the member ID.';

create or replace function public.hdg_access_mode()
 returns text language sql stable security definer set search_path to ''
as $function$
 select coalesce((
   select case
     when exists (select 1 from public.hdg_officer_access a
       where a.user_id = u.id and a.division_code = 'G' and a.active) then 'leader'
     when exists (select 1 from hdg_community_private.beta_members b where b.user_id = u.id) then 'member'
     when exists (
       select 1 from public.hdg_sync_state s
       cross join lateral jsonb_array_elements(s.payload #> '{database,memberships}') as m
       where s.division_code = 'G' and m->>'active' = 'true'
         and coalesce(m->>'pastMember', 'false') <> 'true'
         and lower(btrim(m->>'email')) = lower(btrim(u.email))
     ) then 'member'
     when exists (select 1 from hdg_sync_private.my_roles()) then 'setup'
     else 'none'
   end
   from auth.users u
   where u.id = auth.uid() and u.email_confirmed_at is not null and btrim(u.email) <> ''
 ), 'none');
$function$;

-- The maintainer (or a district admin) adds a leader who is not imported yet. Returns the person id;
-- an existing person with that email is reused.
create or replace function public.hdg_add_provisional_person(p_name text, p_email text)
returns uuid language plpgsql security definer set search_path to ''
as $$
declare e text := lower(btrim(coalesce(p_email, ''))); pid uuid;
begin
 if not (hdg_sync_private.is_maintainer() or hdg_sync_private.is_district_admin()) then
   raise exception 'Maintainer or district admin only' using errcode = '42501';
 end if;
 if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(btrim(coalesce(p_name, ''))) = 0 then
   raise exception 'A name and a valid email are required' using errcode = '22023';
 end if;
 select id into pid from public.hdg_people where email = e order by provisional, updated_at desc limit 1;
 if pid is null then
   insert into public.hdg_people(name, email, provisional) values (left(btrim(p_name), 160), e, true) returning id into pid;
 end if;
 return pid;
end $$;

-- What the signed-in person may see while divisions are being set up: their roles and, for each division in
-- their scope, how far its setup is (clubs and areas loaded, members imported or not). Counts only, no member data.
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
      or exists (select 1 from r where r.role = 'division_director' and r.scope_code = d.code)
      or exists (select 1 from r where r.role = 'area_director' and left(r.scope_code, 1) = d.code)
      or exists (select 1 from r join public.hdg_club_alignment a on a.club_number = r.scope_code and a.year_start = y.yr
                 where r.scope_type = 'club' and left(a.area_code, 1) = d.code))
 select jsonb_build_object(
   'name', (select coalesce(nickname, name) from me),
   'provisional', coalesce((select provisional from me), false),
   'roles', coalesce((select jsonb_agg(jsonb_build_object('role', role, 'scope', scope_code) order by role) from r), '[]'),
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

revoke execute on function public.hdg_add_provisional_person(text, text), public.hdg_my_context() from public, anon;
grant execute on function public.hdg_add_provisional_person(text, text), public.hdg_my_context() to authenticated;
