-- 012: district team members in the leadership directory (owner decision, 23 November 2026). TEST project first.
-- District team chairs (Program Quality and Club Growth teams, the Immediate Past District Director and similar) use
-- the existing 'district_team' role with a title. They see no member records (like the PR, Finance and Logistics
-- Managers); they now appear in the leadership directory with their title. Only the maintainer stays out of it.
-- District roles, including 'district_team', are given and titled by the maintainer or a district admin
-- (hdg_assign_role, hdg_set_role_title; unchanged).
create or replace function public.hdg_leadership_directory()
returns table(name text, nickname text, role text, title text, scope_code text, year_start int)
language sql stable security definer set search_path to ''
as $$
 select p.name, p.nickname, r.role, r.title, r.scope_code, r.year_start from public.hdg_roles r join public.hdg_people p on p.id = r.person_id
 where hdg_sync_private.is_district_user() and r.role <> 'maintainer'
   and r.starts_on <= hdg_sync_private.today() and (r.ends_on is null or r.ends_on >= hdg_sync_private.today())
 order by r.scope_type, r.scope_code, r.role, r.title
$$;
