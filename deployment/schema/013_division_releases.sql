-- 013: release slots for division apps (Phase 1, owner request 23 November 2026). TEST project first.
-- A division other than Division G gets its own app build (deployment/build_division_app.py) in channel 'division'
-- with its division code, e.g. v655-division-k.html. Signing in with a role in that division (access mode 'setup')
-- then opens that build, but only when one is current; otherwise the "being set up" page stays.
-- Only people whose roles cover that division can download its file.

alter table public.hdg_releases add column if not exists division_code text check (division_code is null or division_code ~ '^[A-Z]$');
alter table public.hdg_releases drop constraint hdg_releases_channel_check;
alter table public.hdg_releases add constraint hdg_releases_channel_check check (channel in ('community', 'member', 'division'));
alter table public.hdg_releases add constraint hdg_releases_division_channel check ((channel = 'division') = (division_code is not null));
alter table public.hdg_releases drop constraint hdg_releases_file_check;
alter table public.hdg_releases add constraint hdg_releases_file_check check (file ~ '^v[0-9]{3,4}-[a-z]+(-[a-z])?\.html$');
alter table public.hdg_releases drop constraint hdg_releases_channel_version_key;
create unique index if not exists hdg_releases_channel_division_version on public.hdg_releases (channel, coalesce(division_code, ''), version);
drop index if exists public.hdg_releases_one_current;
create unique index hdg_releases_one_current on public.hdg_releases (channel, coalesce(division_code, '')) where is_current;

-- Divisions covered by the signed-in person's roles (Division Director, council, Area Director, club officer).
create or replace function hdg_sync_private.my_role_divisions() returns setof text language sql stable security definer set search_path to ''
as $$
 select distinct case when r.scope_type = 'division' then r.scope_code
                      when r.scope_type = 'area' then left(r.scope_code, 1)
                      when r.scope_type = 'club' then left(hdg_sync_private.club_area(r.scope_code, hdg_sync_private.year_of(hdg_sync_private.today())), 1) end
 from hdg_sync_private.my_roles() r where r.scope_type in ('division', 'area', 'club')
$$;

create or replace function hdg_sync_private.my_channel() returns text language sql stable security definer set search_path to ''
as $$ select case public.hdg_access_mode() when 'leader' then 'community' when 'member' then 'member' when 'setup' then 'division' end $$;

create or replace function hdg_sync_private.release_file_allowed(p_name text) returns boolean language sql stable security definer set search_path to ''
as $$ select exists (select 1 from public.hdg_releases r where r.is_current and r.channel = hdg_sync_private.my_channel()
  and (r.channel <> 'division' or r.division_code in (select hdg_sync_private.my_role_divisions()))
  and p_name in (r.file, r.file || '.gz')) $$;

-- The launcher's question. A division app is offered only for a division the person has a role in (first by code).
create or replace function public.hdg_current_release() returns jsonb language sql stable security definer set search_path to ''
as $$ select jsonb_build_object('channel', r.channel, 'version', r.version, 'file', r.file, 'sha256', r.sha256, 'division', r.division_code)
  from public.hdg_releases r where r.is_current and r.channel = hdg_sync_private.my_channel()
   and (r.channel <> 'division' or r.division_code in (select hdg_sync_private.my_role_divisions()))
  order by r.division_code limit 1 $$;

create or replace function public.hdg_add_release(p_channel text, p_version text, p_file text, p_sha256 text, p_notes text default null)
returns void language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 if p_channel = 'division' then raise exception 'Use hdg_add_division_release for division apps' using errcode = '22023'; end if;
 insert into public.hdg_releases(channel, version, file, sha256, notes, added_by)
 values (p_channel, p_version, p_file, p_sha256, p_notes, auth.uid())
 on conflict (channel, coalesce(division_code, ''), version) do update set file = excluded.file, sha256 = excluded.sha256, notes = excluded.notes;
end $$;

create or replace function public.hdg_add_division_release(p_division text, p_version text, p_file text, p_sha256 text, p_notes text default null)
returns void language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 insert into public.hdg_releases(channel, division_code, version, file, sha256, notes, added_by)
 values ('division', upper(p_division), p_version, p_file, p_sha256, p_notes, auth.uid())
 on conflict (channel, coalesce(division_code, ''), version) do update set file = excluded.file, sha256 = excluded.sha256, notes = excluded.notes;
end $$;

-- Switching and rolling back a division app (same as the other channels, per division).
create or replace function public.hdg_set_division_release(p_division text, p_version text) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare r public.hdg_releases%rowtype;
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 select * into r from public.hdg_releases where channel = 'division' and division_code = upper(p_division) and version = p_version;
 if not found then raise exception 'Release % is not registered for division %', p_version, p_division using errcode = '22023'; end if;
 update public.hdg_releases set is_current = false where channel = 'division' and division_code = r.division_code and is_current and id <> r.id;
 update public.hdg_releases set is_current = true, made_current_at = now() where id = r.id;
 insert into hdg_sync_private.access_log(actor, action, detail)
 values (auth.uid(), 'set release', jsonb_build_object('channel', 'division', 'division', r.division_code, 'version', p_version));
 return jsonb_build_object('channel', 'division', 'division', r.division_code, 'version', p_version, 'file', r.file);
end $$;

create or replace function public.hdg_clear_division_release(p_division text) returns void
language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 update public.hdg_releases set is_current = false where channel = 'division' and division_code = upper(p_division);
 insert into hdg_sync_private.access_log(actor, action, detail)
 values (auth.uid(), 'clear release', jsonb_build_object('channel', 'division', 'division', upper(p_division)));
end $$;

revoke execute on function hdg_sync_private.my_role_divisions(), public.hdg_add_division_release(text, text, text, text, text),
  public.hdg_set_division_release(text, text), public.hdg_clear_division_release(text) from public, anon;
grant execute on function hdg_sync_private.my_role_divisions(), public.hdg_add_division_release(text, text, text, text, text),
  public.hdg_set_division_release(text, text), public.hdg_clear_division_release(text) to authenticated;
