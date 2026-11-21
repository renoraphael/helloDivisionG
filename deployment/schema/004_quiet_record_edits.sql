-- 004: per-record edits never show a "someone else changed this" error (owner decision, 21 November 2026,
-- project/DISTRICT_PLAN.md rule 33). Replaces the three edit functions from 002. TEST project first.
--
-- An edit names the version it was based on (p_expected_updated_at). If the record changed since then:
--  * fields that nobody else changed in the meantime are still saved (two people editing different
--    fields of the same person both keep their change);
--  * fields that someone else changed in the meantime keep the newer value; the late value is set aside
--    in hdg_sync_private.superseded_edits so the maintainer can recover it.
-- The answer is always a normal result: {applied, updated_at, set_aside: [fields]}. The app reloads the
-- record from updated_at; it shows no error.

create table hdg_sync_private.superseded_edits (
 id bigint generated always as identity primary key,
 at timestamptz not null default now(),
 actor uuid,
 table_name text not null,
 row_key text not null,
 based_on timestamptz,
 patch jsonb not null,
 recovered_at timestamptz);
alter table hdg_sync_private.superseded_edits enable row level security;
revoke all on hdg_sync_private.superseded_edits from public, anon, authenticated;

-- Fields of p_fields that another edit changed after p_since, read from the edit history.
create function hdg_sync_private.fields_changed_since(p_table text, p_key text, p_since timestamptz, p_fields text[])
returns text[] language sql stable security definer set search_path to ''
as $$
 select coalesce(array_agg(distinct f), '{}') from hdg_sync_private.edit_history h, unnest(p_fields) f
 where h.table_name = p_table and h.row_key = p_key and h.op = 'UPDATE'
   and (h.after->>'updated_at')::timestamptz > p_since
   and (h.before->f) is distinct from (h.after->f)
$$;

-- Removes late fields from a patch and keeps them aside. Returns the patch that may still be applied.
create function hdg_sync_private.drop_late_fields(p_table text, p_key text, p_current timestamptz,
  p_expected timestamptz, p_patch jsonb, out patch jsonb, out late text[])
language plpgsql security definer set search_path to ''
as $$
begin
 patch := p_patch; late := '{}';
 if p_current is not distinct from p_expected then return; end if;
 late := hdg_sync_private.fields_changed_since(p_table, p_key, coalesce(p_expected, '-infinity'),
   array(select jsonb_object_keys(p_patch)));
 if cardinality(late) > 0 then
   insert into hdg_sync_private.superseded_edits(actor, table_name, row_key, based_on, patch)
   values (auth.uid(), p_table, p_key, p_expected,
     (select jsonb_object_agg(k, v) from jsonb_each(p_patch) e(k, v) where k = any(late)));
   patch := p_patch - late;
 end if;
end $$;

drop function public.hdg_update_my_profile(uuid, jsonb, timestamptz);
drop function public.hdg_update_person(uuid, jsonb, timestamptz);
drop function public.hdg_update_club(text, jsonb, timestamptz);

create function public.hdg_update_my_profile(p_person uuid, p_patch jsonb, p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare cur timestamptz; d record; result timestamptz;
begin
 if p_person not in (select hdg_sync_private.my_people()) then
   raise exception 'You can only edit your own profile here' using errcode = '42501';
 end if;
 if jsonb_typeof(p_patch) is distinct from 'object'
    or (p_patch - array['nickname', 'aliases', 'pronunciation', 'photo_path', 'photo_consent']) <> '{}'::jsonb then
   raise exception 'Only nickname, aliases, pronunciation, photo and photo consent can be changed' using errcode = '22023';
 end if;
 select updated_at into cur from public.hdg_people where id = p_person for update;
 select * into d from hdg_sync_private.drop_late_fields('hdg_people', p_person::text, cur, p_expected_updated_at, p_patch);
 if d.patch = '{}'::jsonb then
   return jsonb_build_object('applied', false, 'updated_at', cur, 'set_aside', to_jsonb(d.late));
 end if;
 update public.hdg_people set
   nickname = case when d.patch ? 'nickname' then nullif(btrim(d.patch->>'nickname'), '') else nickname end,
   aliases = case when d.patch ? 'aliases' then array(select btrim(x) from jsonb_array_elements_text(d.patch->'aliases') x where btrim(x) <> '') else aliases end,
   pronunciation = case when d.patch ? 'pronunciation' then nullif(btrim(d.patch->>'pronunciation'), '') else pronunciation end,
   photo_path = case when d.patch ? 'photo_path' then nullif(d.patch->>'photo_path', '') else photo_path end,
   photo_consent = case when d.patch ? 'photo_consent' then (d.patch->>'photo_consent')::boolean else photo_consent end,
   updated_at = clock_timestamp(), updated_by = auth.uid()
 where id = p_person returning updated_at into result;
 return jsonb_build_object('applied', true, 'updated_at', result, 'set_aside', to_jsonb(d.late));
end $$;

-- Leaders edit people in their scope. TI fields corrected by hand are recorded in hand_corrected.
create function public.hdg_update_person(p_person uuid, p_patch jsonb, p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare cur timestamptz; d record; result timestamptz; corrected jsonb := '{}'; f text;
begin
 if not (hdg_sync_private.is_district_admin() or exists (
     select 1 from public.hdg_memberships m where m.person_id = p_person and hdg_sync_private.has_club_scope(m.club_number))) then
   raise exception 'This person is outside your scope' using errcode = '42501';
 end if;
 if jsonb_typeof(p_patch) is distinct from 'object' or (p_patch - array['nickname', 'aliases', 'pronunciation', 'photo_path',
     'photo_consent', 'notes', 'name', 'email', 'city', 'ti_member_id']) <> '{}'::jsonb then
   raise exception 'Unknown or protected field' using errcode = '22023';
 end if;
 select updated_at into cur from public.hdg_people where id = p_person for update;
 select * into d from hdg_sync_private.drop_late_fields('hdg_people', p_person::text, cur, p_expected_updated_at, p_patch);
 if d.patch = '{}'::jsonb then
   return jsonb_build_object('applied', false, 'updated_at', cur, 'set_aside', to_jsonb(d.late));
 end if;
 foreach f in array array['name', 'email', 'city', 'ti_member_id'] loop
   if d.patch ? f then
     corrected := corrected || jsonb_build_object(f, jsonb_build_object('value', d.patch->f, 'by', auth.uid(), 'at', now()));
   end if;
 end loop;
 update public.hdg_people set
   nickname = case when d.patch ? 'nickname' then nullif(btrim(d.patch->>'nickname'), '') else nickname end,
   aliases = case when d.patch ? 'aliases' then array(select btrim(x) from jsonb_array_elements_text(d.patch->'aliases') x where btrim(x) <> '') else aliases end,
   pronunciation = case when d.patch ? 'pronunciation' then nullif(btrim(d.patch->>'pronunciation'), '') else pronunciation end,
   photo_path = case when d.patch ? 'photo_path' then nullif(d.patch->>'photo_path', '') else photo_path end,
   photo_consent = case when d.patch ? 'photo_consent' then (d.patch->>'photo_consent')::boolean else photo_consent end,
   notes = case when d.patch ? 'notes' then nullif(btrim(d.patch->>'notes'), '') else notes end,
   name = case when d.patch ? 'name' then btrim(d.patch->>'name') else name end,
   email = case when d.patch ? 'email' then nullif(lower(btrim(d.patch->>'email')), '') else email end,
   city = case when d.patch ? 'city' then nullif(btrim(d.patch->>'city'), '') else city end,
   ti_member_id = case when d.patch ? 'ti_member_id' then nullif(btrim(d.patch->>'ti_member_id'), '') else ti_member_id end,
   hand_corrected = hand_corrected || corrected,
   updated_at = clock_timestamp(), updated_by = auth.uid()
 where id = p_person returning updated_at into result;
 return jsonb_build_object('applied', true, 'updated_at', result, 'set_aside', to_jsonb(d.late));
end $$;

create function public.hdg_update_club(p_club text, p_patch jsonb, p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare cur timestamptz; d record; result timestamptz;
begin
 if not (hdg_sync_private.has_club_scope(p_club) or hdg_sync_private.is_district_admin()) then
   raise exception 'This club is outside your scope' using errcode = '42501';
 end if;
 if jsonb_typeof(p_patch) is distinct from 'object'
    or (p_patch - array['name', 'city', 'timezone', 'currency', 'details']) <> '{}'::jsonb
    or (p_patch ? 'details' and jsonb_typeof(p_patch->'details') <> 'object') then
   raise exception 'Unknown club field' using errcode = '22023';
 end if;
 select updated_at into cur from public.hdg_clubs where club_number = p_club for update;
 select * into d from hdg_sync_private.drop_late_fields('hdg_clubs', p_club, cur, p_expected_updated_at, p_patch);
 if d.patch = '{}'::jsonb then
   return jsonb_build_object('applied', false, 'updated_at', cur, 'set_aside', to_jsonb(d.late));
 end if;
 update public.hdg_clubs set
   name = coalesce(nullif(btrim(d.patch->>'name'), ''), name),
   city = case when d.patch ? 'city' then nullif(btrim(d.patch->>'city'), '') else city end,
   timezone = coalesce(d.patch->>'timezone', timezone),
   currency = coalesce(d.patch->>'currency', currency),
   details = case when d.patch ? 'details' then details || (d.patch->'details') else details end,
   updated_at = clock_timestamp(), updated_by = auth.uid()
 where club_number = p_club returning updated_at into result;
 return jsonb_build_object('applied', true, 'updated_at', result, 'set_aside', to_jsonb(d.late));
end $$;

revoke execute on function hdg_sync_private.fields_changed_since(text, text, timestamptz, text[]),
  hdg_sync_private.drop_late_fields(text, text, timestamptz, timestamptz, jsonb) from public, anon, authenticated;
revoke execute on function public.hdg_update_my_profile(uuid, jsonb, timestamptz), public.hdg_update_person(uuid, jsonb, timestamptz),
  public.hdg_update_club(text, jsonb, timestamptz) from public, anon;
grant execute on function public.hdg_update_my_profile(uuid, jsonb, timestamptz), public.hdg_update_person(uuid, jsonb, timestamptz),
  public.hdg_update_club(text, jsonb, timestamptz) to authenticated;
