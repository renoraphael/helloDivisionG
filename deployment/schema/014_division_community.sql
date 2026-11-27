-- RETIRED FOR PRODUCTION (owner decision 27 November 2026). Synthetic tests only.
-- 014: the data a division app receives at sign-in (Phase 1, owner request 23 November 2026). TEST project first.
-- Same shape as the Division G Member projection (deployment/member-v632-runtime.js reads it), built from the
-- per-record tables: the division's clubs for the current program year (public club information from the imported
-- directory), the latest DCP goals, club officers and the division's leaders by name, and member names for the
-- agenda name list only where the caller may see those members. No emails, phone numbers or member IDs.
-- Answers only people whose roles cover that division, the maintainer and district admins; anyone else gets null.

create or replace function hdg_sync_private.meeting_mode(f text) returns text language sql immutable set search_path to ''
as $$ select case
  when f is null or btrim(f) = '' then 'In-person'
  when lower(f) like '%hybrid%' or lower(f) like '%online option%' or lower(f) like '%and online%' then 'Hybrid'
  when lower(f) like '%online%' and lower(f) not like '%person%' then 'Online'
  else 'In-person' end $$;

create or replace function public.hdg_division_community(p_division text) returns jsonb
language sql stable security definer set search_path to ''
as $$
 with y as (select hdg_sync_private.year_of(hdg_sync_private.today()) yr, hdg_sync_private.today() d),
 ok as (select upper(coalesce(p_division, '')) ~ '^[A-Z]$'
          and (upper(p_division) in (select hdg_sync_private.my_role_divisions())
               or hdg_sync_private.is_maintainer() or hdg_sync_private.is_district_admin()) allowed),
 cl as (select c.*, a.area_code from public.hdg_clubs c
        join public.hdg_club_alignment a on a.club_number = c.club_number join y on a.year_start = y.yr
        where a.status = 'approved' and left(a.area_code, 1) = upper(p_division)),
 fig as (select distinct on (f.club_number) f.club_number, f.dcp_goals_met from public.hdg_club_figures f
         where f.club_number in (select club_number from cl) order by f.club_number, f.as_of desc),
 rl as (select r.role, r.scope_type, r.scope_code, r.title, coalesce(p.nickname, p.name) as name
        from public.hdg_roles r join public.hdg_people p on p.id = r.person_id, y
        where r.starts_on <= y.d and (r.ends_on is null or r.ends_on >= y.d)),
 me as (select coalesce(p.nickname, p.name) n from public.hdg_people p
        where p.id in (select hdg_sync_private.my_people()) order by p.provisional limit 1)
 select case when (select allowed from ok) then jsonb_build_object(
  'memberName', (select n from me),
  'updated', now(),
  'division', upper(p_division),
  'clubs', coalesce((select jsonb_agg(jsonb_build_object(
     'number', cl.club_number, 'name', cl.name, 'area', cl.area_code, 'city', cl.city,
     'island', coalesce(cl.details->'directory'->>'state_or_territory', cl.details->'directory'->>'country', ''),
     'mode', hdg_sync_private.meeting_mode(cl.details->'directory'->>'meeting_format'),
     'meetingMode', hdg_sync_private.meeting_mode(cl.details->'directory'->>'meeting_format'),
     'dcpGoals', fig.dcp_goals_met,
     'schedule', coalesce(cl.details->'directory'->>'meeting_schedule', ''),
     'timezone', public.hdg_timezone_label(cl.timezone),
     'locationTitle', coalesce(cl.details->'directory'->>'venue', ''),
     'locationAddress', coalesce(cl.details->'directory'->>'street_address', ''),
     'publicLocation', coalesce(cl.details->'directory'->>'published_venue_address',
                                concat_ws(' · ', cl.details->'directory'->>'venue', cl.city)),
     'inactive', false) order by cl.area_code, cl.name)
     from cl left join fig on fig.club_number = cl.club_number), '[]'),
  'clubOfficers', coalesce((select jsonb_agg(jsonb_build_object('clubNumber', r.scope_code, 'name', r.name, 'role', case r.role
       when 'club_president' then 'Club President' when 'club_vpe' then 'Club VP Education'
       when 'club_vpm' then 'Club VP Membership' when 'club_vppr' then 'Club VP PR' when 'club_secretary' then 'Club Secretary'
       when 'club_treasurer' then 'Club Treasurer' when 'club_saa' then 'Club Sergeant at Arms' end))
     from rl r where r.scope_type = 'club' and r.scope_code in (select club_number from cl)), '[]'),
  'leaders', coalesce((select jsonb_agg(x order by x->>'role', x->>'scope') from (
       select jsonb_build_object('role', 'Division Director', 'scope', upper(p_division), 'name', r.name) x
       from rl r where r.role = 'division_director' and r.scope_code = upper(p_division)
       union all
       select jsonb_build_object('role', 'Area Director', 'scope', ar.code,
              'name', coalesce((select r.name from rl r where r.role = 'area_director' and r.scope_code = ar.code limit 1), ''))
       from public.hdg_areas ar join y on ar.year_start = y.yr where ar.division_code = upper(p_division)) l), '[]'),
  'agendaMembers', coalesce((select jsonb_agg(jsonb_build_object('clubNumber', m.club_number, 'name', p.name,
       'nicknames', to_jsonb(array_remove(array_prepend(p.nickname, p.aliases), null))))
     from public.hdg_memberships m join public.hdg_people p on p.id = m.person_id
     where m.status = 'active' and m.club_number in (select club_number from cl)
       and hdg_sync_private.has_club_read_scope(m.club_number)), '[]'),
  'clubAgendaDefaults', '{}'::jsonb,
  'events', '[]'::jsonb)
 end
$$;

revoke execute on function hdg_sync_private.meeting_mode(text), public.hdg_division_community(text) from public, anon;
grant execute on function public.hdg_division_community(text) to authenticated;
