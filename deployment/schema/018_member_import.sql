-- 018: the Toastmasters member list goes into the per-record tables (hdg_people, hdg_memberships).
-- Rules (project/DISTRICT_PLAN.md): 1 city only, never street address or phone (rows carry only the fields below);
-- 9 people matched by member ID; 11 imports never overwrite manual fields, and a hand-corrected TI field that differs
-- is reported so the leader chooses; 12 who and when, and undo; 13 freshest list wins per club; 14 leaders import only
-- clubs they lead. New joiners become choosable for Club Exco seats (017) at once.
-- Test project first; production only with the owner's approval.

begin;

-- One row per club per import, and the state of every row it changed, so the import can be undone.
create table hdg_sync_private.member_imports (
 id uuid primary key default gen_random_uuid(),
 club_number text not null references public.hdg_clubs,
 as_of date not null,
 snapshot boolean not null,
 previous_as_of date,
 counts jsonb not null default '{}',
 imported_at timestamptz not null default now(),
 imported_by uuid,
 undone_at timestamptz,
 undone_by uuid);
create index member_imports_club on hdg_sync_private.member_imports (club_number, imported_at desc);

create table hdg_sync_private.member_import_changes (
 import_id uuid not null references hdg_sync_private.member_imports on delete cascade,
 table_name text not null check (table_name in ('hdg_people', 'hdg_memberships')),
 row_id uuid not null,
 before jsonb,                          -- null: the import created this row
 after_updated_at timestamptz not null, -- undo only restores rows nobody changed since
 primary key (import_id, table_name, row_id));

-- Member IDs are matched without leading zeros (TI writes 01234567, some exports drop the zero).
create index if not exists hdg_people_member_id_plain on public.hdg_people (ltrim(ti_member_id, '0'));

alter table hdg_sync_private.member_imports enable row level security;
alter table hdg_sync_private.member_import_changes enable row level security;
revoke all on hdg_sync_private.member_imports, hdg_sync_private.member_import_changes from public, anon, authenticated;

create function hdg_sync_private.iso_date(p text) returns date language plpgsql immutable set search_path to ''
as $$
begin
 if p is null or p !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
 return p::date;
exception when others then return null;
end $$;

create function hdg_sync_private.note_import_change(p_import uuid, p_table text, p_id uuid, p_before jsonb, p_after timestamptz)
returns void language sql security definer set search_path to ''
as $$
 insert into hdg_sync_private.member_import_changes(import_id, table_name, row_id, before, after_updated_at)
 values (p_import, p_table, p_id, p_before, p_after)
 on conflict (import_id, table_name, row_id) do update set after_updated_at = excluded.after_updated_at
$$;

-- Import one club's rows from a Toastmasters member list dated p_as_of.
-- Row keys: memberId (required), name, email, city, active (false = lapsed), joinedOn, paidUntil (YYYY-MM-DD).
-- p_snapshot: members of the club missing from the list become past members.
create function public.hdg_import_club_members(p_club text, p_as_of date, p_rows jsonb, p_snapshot boolean) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare club text := hdg_sync_private.plain_club_number(p_club); fresh date; imp uuid; r jsonb; mid text;
 p public.hdg_people; m public.hdg_memberships; f text; ti text; cur text; changed boolean; new_p public.hdg_people;
 v_status text; v_join date; v_paid date; seen uuid[] := '{}'; conflicts jsonb := '[]'; when_now timestamptz := now();
 n_new_people int := 0; n_people int := 0; n_new_m int := 0; n_m int := 0; n_left int := 0; n_skipped int := 0; n_same int := 0;
 allowed text[] := array['memberId', 'name', 'email', 'city', 'active', 'joinedOn', 'paidUntil'];
begin
 if club is null or not exists (select 1 from public.hdg_clubs c where c.club_number = club) then
   raise exception 'Unknown club' using errcode = '22023';
 end if;
 if not hdg_sync_private.leads_club(club) then
   raise exception 'Only leaders of this club''s area or division import its member list' using errcode = '42501';
 end if;
 if p_as_of is null or p_as_of > hdg_sync_private.today() then
   raise exception 'The member list needs its date (not in the future)' using errcode = '22023';
 end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 3000 then
   raise exception 'Rows must be a list of 1 to 3000 members' using errcode = '22023';
 end if;
 if exists (select 1 from jsonb_array_elements(p_rows) e
            where jsonb_typeof(e.value) <> 'object' or exists (select 1 from jsonb_object_keys(e.value) k where k <> all (allowed))) then
   raise exception 'Rows may only hold member ID, name, email, city, status and dates' using errcode = '22023';
 end if;

 perform pg_advisory_xact_lock(hashtext('hdg-roster:' || club));
 select as_of into fresh from public.hdg_import_freshness where club_number = club and kind = 'roster';
 if fresh > p_as_of then
   return jsonb_build_object('stale', true, 'newerAsOf', fresh);
 end if;
 insert into hdg_sync_private.member_imports(club_number, as_of, snapshot, previous_as_of, imported_by)
 values (club, p_as_of, coalesce(p_snapshot, false), fresh, auth.uid()) returning id into imp;

 for r in select e.value from jsonb_array_elements(p_rows) e loop
   mid := nullif(ltrim(btrim(coalesce(r->>'memberId', '')), '0'), '');
   if mid is null or mid !~ '^[0-9A-Za-z]{1,20}$' then n_skipped := n_skipped + 1; continue; end if;
   v_status := case when r->'active' = 'false'::jsonb then 'lapsed' else 'active' end;
   v_join := hdg_sync_private.iso_date(r->>'joinedOn');
   v_paid := hdg_sync_private.iso_date(r->>'paidUntil');

   select * into p from public.hdg_people where ltrim(ti_member_id, '0') = mid for update;
   if not found then
     if nullif(btrim(coalesce(r->>'name', '')), '') is null then n_skipped := n_skipped + 1; continue; end if;
     insert into public.hdg_people(ti_member_id, name, email, city, updated_by)
     values (case when mid ~ '^[0-9]+$' then lpad(mid, 8, '0') else mid end,
             left(regexp_replace(btrim(r->>'name'), '\s+', ' ', 'g'), 160),
             nullif(lower(btrim(coalesce(r->>'email', ''))), ''), nullif(btrim(coalesce(r->>'city', '')), ''), auth.uid())
     returning * into p;
     perform hdg_sync_private.note_import_change(imp, 'hdg_people', p.id, null, p.updated_at);
     n_new_people := n_new_people + 1;
   else
     new_p := p; changed := false;
     foreach f in array array['name', 'email', 'city'] loop
       ti := case f when 'name' then left(regexp_replace(btrim(coalesce(r->>'name', '')), '\s+', ' ', 'g'), 160)
                    when 'email' then lower(btrim(coalesce(r->>'email', ''))) else btrim(coalesce(r->>'city', '')) end;
       ti := nullif(ti, '');
       if ti is null then continue; end if;   -- an empty cell never blanks a field
       cur := case f when 'name' then p.name when 'email' then p.email else p.city end;
       if ti is not distinct from cur then continue; end if;
       if p.hand_corrected ? f then
         if ti is distinct from (p.hand_corrected->f->>'dismissedTi') then
           conflicts := conflicts || jsonb_build_object('person', p.id, 'memberId', p.ti_member_id, 'field', f, 'yours', cur, 'ti', ti);
         end if;
         continue;
       end if;
       changed := true;
       if f = 'name' then new_p.name := ti; elsif f = 'email' then new_p.email := ti; else new_p.city := ti; end if;
     end loop;
     if changed then
       perform hdg_sync_private.note_import_change(imp, 'hdg_people', p.id, to_jsonb(p), when_now);
       update public.hdg_people set name = new_p.name, email = new_p.email, city = new_p.city, updated_at = when_now, updated_by = auth.uid()
       where id = p.id;
       n_people := n_people + 1;
     end if;
   end if;
   seen := seen || p.id;

   select * into m from public.hdg_memberships where person_id = p.id and club_number = club for update;
   if not found then
     insert into public.hdg_memberships(person_id, club_number, status, joined_on, paid_until, source_as_of, updated_by)
     values (p.id, club, v_status, v_join, v_paid, p_as_of, auth.uid()) returning * into m;
     perform hdg_sync_private.note_import_change(imp, 'hdg_memberships', m.id, null, m.updated_at);
     n_new_m := n_new_m + 1;
   elsif (m.status, m.joined_on, m.paid_until) is distinct from (v_status, coalesce(v_join, m.joined_on), coalesce(v_paid, m.paid_until)) then
     perform hdg_sync_private.note_import_change(imp, 'hdg_memberships', m.id, to_jsonb(m), when_now);
     update public.hdg_memberships set status = v_status, joined_on = coalesce(v_join, joined_on), paid_until = coalesce(v_paid, paid_until),
       source_as_of = p_as_of, updated_at = when_now, updated_by = auth.uid()
     where id = m.id;
     n_m := n_m + 1;
   else
     n_same := n_same + 1;
   end if;
 end loop;

 if coalesce(p_snapshot, false) and cardinality(seen) > 0 then
   for m in select * from public.hdg_memberships x where x.club_number = club and x.status <> 'past' and x.person_id <> all (seen) for update loop
     perform hdg_sync_private.note_import_change(imp, 'hdg_memberships', m.id, to_jsonb(m), when_now);
     update public.hdg_memberships set status = 'past', source_as_of = p_as_of, updated_at = when_now, updated_by = auth.uid() where id = m.id;
     n_left := n_left + 1;
   end loop;
 end if;

 insert into public.hdg_import_freshness(club_number, kind, as_of, imported_by) values (club, 'roster', p_as_of, auth.uid())
 on conflict (club_number, kind) do update set as_of = greatest(public.hdg_import_freshness.as_of, excluded.as_of),
   imported_at = now(), imported_by = excluded.imported_by;
 update hdg_sync_private.member_imports set counts = jsonb_build_object('newPeople', n_new_people, 'updatedPeople', n_people,
   'newMemberships', n_new_m, 'updatedMemberships', n_m, 'left', n_left, 'unchanged', n_same, 'skipped', n_skipped,
   'conflicts', jsonb_array_length(conflicts)) where id = imp;
 return jsonb_build_object('import', imp, 'newPeople', n_new_people, 'updatedPeople', n_people, 'newMemberships', n_new_m,
   'updatedMemberships', n_m, 'left', n_left, 'unchanged', n_same, 'skipped', n_skipped, 'conflicts', conflicts);
end $$;

-- A hand-corrected name, email or city differs from the member list: take the list's value, or keep yours
-- (the list's value is remembered, so the same difference is not asked again).
create function public.hdg_resolve_import_conflict(p_person uuid, p_field text, p_ti_value text, p_take boolean) returns void
language plpgsql security definer set search_path to ''
as $$
declare v text := nullif(btrim(coalesce(p_ti_value, '')), '');
begin
 if p_field not in ('name', 'email', 'city') or v is null then raise exception 'Unknown field or empty value' using errcode = '22023'; end if;
 if not exists (select 1 from public.hdg_memberships m where m.person_id = p_person and hdg_sync_private.leads_club(m.club_number)) then
   raise exception 'This person is outside your scope' using errcode = '42501';
 end if;
 if p_take then
   update public.hdg_people set
     name = case when p_field = 'name' then left(v, 160) else name end,
     email = case when p_field = 'email' then lower(v) else email end,
     city = case when p_field = 'city' then v else city end,
     hand_corrected = hand_corrected - p_field, updated_at = now(), updated_by = auth.uid()
   where id = p_person;
 else
   update public.hdg_people set hand_corrected = jsonb_set(hand_corrected, array[p_field, 'dismissedTi'], to_jsonb(v)),
     updated_at = now(), updated_by = auth.uid()
   where id = p_person and hand_corrected ? p_field;
 end if;
end $$;

-- Undo a club's latest member list import: the person who ran it, a district admin or the maintainer.
-- Rows changed by someone else since are left as they are and counted.
create function public.hdg_undo_member_import(p_import uuid) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare i hdg_sync_private.member_imports; c hdg_sync_private.member_import_changes; restored int := 0; skipped int := 0;
begin
 select * into i from hdg_sync_private.member_imports where id = p_import and undone_at is null;
 if not found then raise exception 'This import cannot be undone (already undone or unknown)' using errcode = '22023'; end if;
 if not (i.imported_by = auth.uid() or hdg_sync_private.is_district_admin() or hdg_sync_private.is_maintainer()) then
   raise exception 'Only the person who ran this import, a district admin or the maintainer can undo it' using errcode = '42501';
 end if;
 if exists (select 1 from hdg_sync_private.member_imports x where x.club_number = i.club_number and x.undone_at is null
            and x.imported_at > i.imported_at) then
   raise exception 'A newer import of this club exists; undo that one first' using errcode = 'PT409';
 end if;
 perform pg_advisory_xact_lock(hashtext('hdg-roster:' || i.club_number));
 -- Memberships first (a person created by the import can only go once their membership has gone).
 for c in select * from hdg_sync_private.member_import_changes where import_id = p_import order by (table_name = 'hdg_people') loop
   if c.table_name = 'hdg_memberships' then
     if c.before is null then
       delete from public.hdg_memberships where id = c.row_id and updated_at = c.after_updated_at;
     else
       update public.hdg_memberships t set (status, joined_on, paid_until, source_as_of, updated_at, updated_by)
         = (select b.status, b.joined_on, b.paid_until, b.source_as_of, now(), auth.uid() from jsonb_populate_record(null::public.hdg_memberships, c.before) b)
       where t.id = c.row_id and t.updated_at = c.after_updated_at;
     end if;
   elsif c.before is null then
     delete from public.hdg_people t where t.id = c.row_id and t.updated_at = c.after_updated_at and t.user_id is null
       and not exists (select 1 from public.hdg_memberships x where x.person_id = t.id)
       and not exists (select 1 from public.hdg_roles x where x.person_id = t.id);
   else
     update public.hdg_people t set (name, email, city, updated_at, updated_by)
       = (select b.name, b.email, b.city, now(), auth.uid() from jsonb_populate_record(null::public.hdg_people, c.before) b)
     where t.id = c.row_id and t.updated_at = c.after_updated_at;
   end if;
   if found then restored := restored + 1; else skipped := skipped + 1; end if;
 end loop;
 if i.previous_as_of is null then
   delete from public.hdg_import_freshness where club_number = i.club_number and kind = 'roster'
     and not exists (select 1 from hdg_sync_private.member_imports x where x.club_number = i.club_number and x.undone_at is null and x.id <> i.id);
 else
   update public.hdg_import_freshness set as_of = i.previous_as_of, imported_at = now(), imported_by = auth.uid()
   where club_number = i.club_number and kind = 'roster';
 end if;
 update hdg_sync_private.member_imports set undone_at = now(), undone_by = auth.uid() where id = p_import;
 return jsonb_build_object('restored', restored, 'changedSince', skipped);
end $$;

revoke execute on function hdg_sync_private.iso_date(text),
  hdg_sync_private.note_import_change(uuid, text, uuid, jsonb, timestamptz) from public, anon, authenticated;
revoke execute on function public.hdg_import_club_members(text, date, jsonb, boolean),
  public.hdg_resolve_import_conflict(uuid, text, text, boolean), public.hdg_undo_member_import(uuid) from public, anon;
grant execute on function public.hdg_import_club_members(text, date, jsonb, boolean),
  public.hdg_resolve_import_conflict(uuid, text, text, boolean), public.hdg_undo_member_import(uuid) to authenticated;

commit;
