-- 007: one-step release rollback (Phase 0, step 10; project/DISTRICT_PLAN.md rule 30). TEST project first.
-- Every uploaded app file is registered here. The launcher asks which file is current for the signed-in
-- person's channel (leaders: community, members: member) and loads that one. Rolling back is one call
-- (hdg_rollback_release) that makes the previous release current again; its file is still in storage.
-- Only the current file of each channel can be downloaded through this table's policy, so access stays as
-- tight as the per-version policies. Existing per-version policies keep working alongside it.

create table public.hdg_releases (
 id bigint generated always as identity primary key,
 channel text not null check (channel in ('community', 'member')),
 version text not null check (version ~ '^v[0-9]{3,4}$'),
 file text not null check (file ~ '^v[0-9]{3,4}-[a-z]+\.html$'),
 sha256 text check (sha256 ~ '^[0-9a-f]{64}$'),
 notes text,
 added_at timestamptz not null default now(), added_by uuid,
 is_current boolean not null default false,
 made_current_at timestamptz,
 unique (channel, version));
create unique index hdg_releases_one_current on public.hdg_releases (channel) where is_current;
alter table public.hdg_releases enable row level security;
revoke all on public.hdg_releases from public, anon, authenticated;

create function hdg_sync_private.my_channel() returns text language sql stable security definer set search_path to ''
as $$ select case public.hdg_access_mode() when 'leader' then 'community' when 'member' then 'member' end $$;

-- Used by the storage policy: is this object the current file (or its .gz copy) for the caller's channel?
create function hdg_sync_private.release_file_allowed(p_name text) returns boolean language sql stable security definer set search_path to ''
as $$ select exists (select 1 from public.hdg_releases r where r.is_current and r.channel = hdg_sync_private.my_channel()
  and p_name in (r.file, r.file || '.gz')) $$;

-- The launcher's question: which file should I load? Null if the caller has no access or nothing is registered.
create function public.hdg_current_release() returns jsonb language sql stable security definer set search_path to ''
as $$ select jsonb_build_object('channel', r.channel, 'version', r.version, 'file', r.file, 'sha256', r.sha256)
  from public.hdg_releases r where r.is_current and r.channel = hdg_sync_private.my_channel() $$;

create function public.hdg_add_release(p_channel text, p_version text, p_file text, p_sha256 text, p_notes text default null)
returns void language plpgsql security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 insert into public.hdg_releases(channel, version, file, sha256, notes, added_by)
 values (p_channel, p_version, p_file, p_sha256, p_notes, auth.uid())
 on conflict (channel, version) do update set file = excluded.file, sha256 = excluded.sha256, notes = excluded.notes;
end $$;

-- Make a registered release current (a new release, or any earlier one).
create function public.hdg_set_release(p_channel text, p_version text) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare r public.hdg_releases%rowtype;
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 select * into r from public.hdg_releases where channel = p_channel and version = p_version;
 if not found then raise exception 'Release % is not registered for %', p_version, p_channel using errcode = '22023'; end if;
 update public.hdg_releases set is_current = false where channel = p_channel and is_current and id <> r.id;
 update public.hdg_releases set is_current = true, made_current_at = now() where id = r.id;
 insert into hdg_sync_private.access_log(actor, action, detail)
 values (auth.uid(), 'set release', jsonb_build_object('channel', p_channel, 'version', p_version));
 return jsonb_build_object('channel', p_channel, 'version', p_version, 'file', r.file);
end $$;

-- One step back: the release that was current before this one.
create function public.hdg_rollback_release(p_channel text) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare prev text;
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 select r.version into prev from public.hdg_releases r
 where r.channel = p_channel and not r.is_current and r.made_current_at is not null
 order by r.made_current_at desc limit 1;
 if prev is null then raise exception 'There is no earlier release to go back to' using errcode = '22023'; end if;
 return public.hdg_set_release(p_channel, prev);
end $$;

create function public.hdg_list_releases(p_channel text)
returns table(version text, file text, sha256 text, added_at timestamptz, is_current boolean, made_current_at timestamptz)
language plpgsql stable security definer set search_path to ''
as $$
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode = '42501'; end if;
 return query select r.version, r.file, r.sha256, r.added_at, r.is_current, r.made_current_at
   from public.hdg_releases r where r.channel = p_channel order by r.id desc;
end $$;

create policy hdg_current_release_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and hdg_sync_private.release_file_allowed(name));

revoke execute on function hdg_sync_private.my_channel(), hdg_sync_private.release_file_allowed(text),
  public.hdg_current_release(), public.hdg_add_release(text, text, text, text, text), public.hdg_set_release(text, text),
  public.hdg_rollback_release(text), public.hdg_list_releases(text) from public, anon, authenticated;
grant execute on function hdg_sync_private.my_channel(), hdg_sync_private.release_file_allowed(text),
  public.hdg_current_release(), public.hdg_add_release(text, text, text, text, text), public.hdg_set_release(text, text),
  public.hdg_rollback_release(text), public.hdg_list_releases(text) to authenticated;
