-- 019: member and officer lists for clubs outside Division G (owner decisions, 27 November 2026).
-- One app for every division (later Hello District 87). Imports for another division go straight into the
-- per-record tables, scoped by role (rule 14). A division's imports open only when the maintainer opens them,
-- after Malaysian PDPA / Indonesian UU PDP requirements are met for it (rule 4). Division G is open.
-- Test project first; production only with the owner's approval.

begin;

-- Is the member list import open for this club's division (this program year)?
create function hdg_sync_private.import_open(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$
 select coalesce((select d.config->>'memberImport' = 'open' from public.hdg_divisions d
   where d.code = left(hdg_sync_private.club_area(p_club, hdg_sync_private.year_of(hdg_sync_private.today())), 1)), false)
$$;

update public.hdg_divisions set config = config || '{"memberImport": "open"}', updated_at = now() where code = 'G';

-- The maintainer opens or closes a division's imports.
create function public.hdg_set_division_import(p_division text, p_open boolean) returns void
language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 update public.hdg_divisions set config = config || jsonb_build_object('memberImport', case when p_open then 'open' else 'closed' end),
   updated_at = now(), updated_by = auth.uid()
 where code = p_division;
 if not found then raise exception 'Unknown division' using errcode = '22023'; end if;
end $$;

-- Every club in the district this program year (public club information), with whether the signed-in
-- leader may import its lists, and why not.
create function public.hdg_import_clubs() returns jsonb language sql stable security definer set search_path to ''
as $$
 select coalesce(jsonb_agg(jsonb_build_object('club', c.club_number, 'name', c.name, 'area', a.area_code,
     'division', left(a.area_code, 1),
     'canImport', l.leads and o.open,
     'reason', case when not l.leads then 'scope' when not o.open then 'closed' end)
   order by a.area_code, c.name), '[]'::jsonb)
 from public.hdg_clubs c
 join public.hdg_club_alignment a on a.club_number = c.club_number and a.status = 'approved'
   and a.year_start = hdg_sync_private.year_of(hdg_sync_private.today())
 cross join lateral (select hdg_sync_private.leads_club(c.club_number) leads) l
 cross join lateral (select hdg_sync_private.import_open(c.club_number) open) o
 where c.closed_on is null and auth.uid() is not null
$$;

-- The import functions from 017 and 018 move behind a check that the division is open.
alter function public.hdg_import_club_members(text, date, jsonb, boolean) set schema hdg_sync_private;
alter function hdg_sync_private.hdg_import_club_members(text, date, jsonb, boolean) rename to import_club_members;
alter function public.hdg_import_club_officers(text, date, jsonb) set schema hdg_sync_private;
alter function hdg_sync_private.hdg_import_club_officers(text, date, jsonb) rename to import_club_officers;
revoke execute on function hdg_sync_private.import_club_members(text, date, jsonb, boolean),
  hdg_sync_private.import_club_officers(text, date, jsonb) from public, anon, authenticated;

create function public.hdg_import_club_members(p_club text, p_as_of date, p_rows jsonb, p_snapshot boolean) returns jsonb
language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.import_open(hdg_sync_private.plain_club_number(p_club)) then
   raise exception 'Member list imports for this division are not open yet' using errcode = '42501';
 end if;
 return hdg_sync_private.import_club_members(p_club, p_as_of, p_rows, p_snapshot);
end $$;

create function public.hdg_import_club_officers(p_club text, p_as_of date, p_seats jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.import_open(hdg_sync_private.plain_club_number(p_club)) then
   raise exception 'Officer list imports for this division are not open yet' using errcode = '42501';
 end if;
 return hdg_sync_private.import_club_officers(p_club, p_as_of, p_seats);
end $$;

revoke execute on function hdg_sync_private.import_open(text) from public, anon, authenticated;
revoke execute on function public.hdg_set_division_import(text, boolean), public.hdg_import_clubs(),
  public.hdg_import_club_members(text, date, jsonb, boolean), public.hdg_import_club_officers(text, date, jsonb) from public, anon;
grant execute on function public.hdg_set_division_import(text, boolean), public.hdg_import_clubs(),
  public.hdg_import_club_members(text, date, jsonb, boolean), public.hdg_import_club_officers(text, date, jsonb) to authenticated;

commit;
