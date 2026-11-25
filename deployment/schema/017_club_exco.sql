-- 017: clubs manage their own Exco (owner decisions, 25 November 2026).
--   Any current officer of a club can change that club's Exco seats; the change applies at once (no Area
--     Director confirmation). Area and Division Directors of the club, approved Division G leaders and the
--     maintainer can do the same.
--   A seat goes to an active member of the club. The previous holder's role ends yesterday, the new one starts
--     today, so access (meeting rights, club scope) follows immediately.
--   Toastmasters officer list imports: the newer wins. A seat changed by the club or a leader on or after the
--     list's date is kept; anything older is replaced by the list. Seats the list leaves empty are vacated the
--     same way.
--   Every change is in hdg_roles' edit history (existing trigger).
-- TEST project first; production with the owner's approval.
begin;

alter table public.hdg_roles add column if not exists source text check (source in ('import', 'club', 'leader', 'legacy'));
alter table public.hdg_roles add column if not exists source_at timestamptz;
comment on column public.hdg_roles.source is 'Who set this seat: a TI officer list import, the club itself, a leader, or the one-off legacy copy (005).';
comment on column public.hdg_roles.source_at is 'For import: the officer list date. For club/leader: when the change was made. Newer wins on the next import.';

create function hdg_sync_private.club_seats() returns text[] language sql immutable set search_path to ''
as $$ select array['club_president', 'club_vpe', 'club_vpm', 'club_vppr', 'club_secretary', 'club_treasurer', 'club_saa'] $$;

-- Is the signed-in account a current officer of this club?
create function hdg_sync_private.is_officer_of(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$ select exists (select 1 from hdg_sync_private.my_roles() r where r.scope_type = 'club' and r.scope_code = p_club) $$;

-- Leader for this club: Area/Division Director in scope, district admin, maintainer, or an approved Division G leader.
create function hdg_sync_private.leads_club(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$
 select hdg_sync_private.can_manage_role('club_president', 'club', p_club, hdg_sync_private.year_of(hdg_sync_private.today()))
  or (public.hdg_access_mode() = 'leader'
      and left(coalesce(hdg_sync_private.club_area(p_club, hdg_sync_private.year_of(hdg_sync_private.today())), ''), 1) = 'G')
$$;

create function hdg_sync_private.can_edit_exco(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$ select hdg_sync_private.is_officer_of(p_club) or hdg_sync_private.leads_club(p_club) $$;

-- The current holder of one seat (latest start wins if a seat ever has two).
create function hdg_sync_private.seat_holder(p_club text, p_role text) returns public.hdg_roles language sql stable security definer set search_path to ''
as $$
 select r.* from public.hdg_roles r
 where r.scope_type = 'club' and r.scope_code = p_club and r.role = p_role
   and r.starts_on <= hdg_sync_private.today() and (r.ends_on is null or r.ends_on >= hdg_sync_private.today())
 order by r.starts_on desc, r.entered_at desc limit 1
$$;

-- End every current holder of a seat now: yesterday if it started earlier, removed if it started today.
create function hdg_sync_private.end_seat(p_club text, p_role text) returns void language plpgsql security definer set search_path to ''
as $$
declare t date := hdg_sync_private.today();
begin
 delete from public.hdg_roles r where r.scope_type = 'club' and r.scope_code = p_club and r.role = p_role
   and r.starts_on >= t;
 update public.hdg_roles r set ends_on = t - 1 where r.scope_type = 'club' and r.scope_code = p_club and r.role = p_role
   and r.starts_on < t and (r.ends_on is null or r.ends_on >= t);
end $$;

create function hdg_sync_private.start_seat(p_club text, p_role text, p_person uuid, p_source text, p_source_at timestamptz)
returns void language plpgsql security definer set search_path to ''
as $$
declare y int := hdg_sync_private.year_of(hdg_sync_private.today());
begin
 if not exists (select 1 from public.hdg_program_years where year_start = y) then
   raise exception 'The program year % is not set up', y using errcode = '22023';
 end if;
 insert into public.hdg_roles(person_id, role, scope_type, scope_code, year_start, starts_on, ends_on, entered_by, source, source_at)
 values (p_person, p_role, 'club', p_club, y, hdg_sync_private.today(), make_date(y + 1, 6, 30), auth.uid(), p_source, p_source_at);
end $$;

-- A club's Exco: its seats and holders, whether this account may change them, and (for those who may) the
-- club's active members to choose from.
create function public.hdg_club_exco(p_club text) returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare club text := hdg_sync_private.plain_club_number(p_club); can boolean;
begin
 if club is null then raise exception 'Unknown club' using errcode = '22023'; end if;
 can := hdg_sync_private.can_edit_exco(club);
 if not (can or hdg_sync_private.has_club_read_scope(club)) then
   raise exception 'This club is outside your scope' using errcode = '42501';
 end if;
 return jsonb_build_object(
  'club', club,
  'canEdit', can,
  'officersAsOf', (select f.as_of from public.hdg_import_freshness f where f.club_number = club and f.kind = 'officers'),
  'seats', (select jsonb_agg(jsonb_build_object(
      'role', s.role, 'person', h.person_id, 'name', p.name, 'memberId', p.ti_member_id, 'since', h.starts_on,
      'source', coalesce(h.source, case when h.id is not null then 'legacy' end), 'changedAt', h.source_at,
      'mine', h.person_id in (select hdg_sync_private.my_people()))
    order by s.n)
    from unnest(hdg_sync_private.club_seats()) with ordinality s(role, n)
    left join lateral hdg_sync_private.seat_holder(club, s.role) h on true
    left join public.hdg_people p on p.id = h.person_id),
  'candidates', case when can then coalesce((select jsonb_agg(jsonb_build_object('person', p.id, 'name', p.name, 'memberId', p.ti_member_id) order by p.name)
      from public.hdg_memberships m join public.hdg_people p on p.id = m.person_id
      where m.club_number = club and m.status = 'active'), '[]'::jsonb) else '[]'::jsonb end);
end $$;

-- Give a seat to an active member of the club, or leave it empty (p_person null). Applies at once.
create function public.hdg_set_club_officer(p_club text, p_role text, p_person uuid) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare club text := hdg_sync_private.plain_club_number(p_club); cur public.hdg_roles; src text;
begin
 if club is null then raise exception 'Unknown club' using errcode = '22023'; end if;
 if p_role is null or not (p_role = any (hdg_sync_private.club_seats())) then
   raise exception 'Unknown Exco seat' using errcode = '22023';
 end if;
 if not hdg_sync_private.can_edit_exco(club) then
   raise exception 'Only this club''s officers and its leaders can change its Exco' using errcode = '42501';
 end if;
 if p_person is not null and not exists (select 1 from public.hdg_memberships m
     where m.person_id = p_person and m.club_number = club and m.status = 'active') then
   raise exception 'Choose an active member of this club' using errcode = '22023';
 end if;
 perform pg_advisory_xact_lock(hashtext('hdg-exco:' || club || ':' || p_role));
 src := case when hdg_sync_private.is_officer_of(club) then 'club' else 'leader' end;
 cur := hdg_sync_private.seat_holder(club, p_role);
 if cur.id is not null and cur.person_id is not distinct from p_person then
   update public.hdg_roles set source = src, source_at = now() where id = cur.id;
 else
   perform hdg_sync_private.end_seat(club, p_role);
   if p_person is not null then perform hdg_sync_private.start_seat(club, p_role, p_person, src, now()); end if;
 end if;
 return public.hdg_club_exco(club);
end $$;

-- A Toastmasters officer list for one club, dated p_as_of. p_seats: [{role, memberId}] for every seat on the list
-- (a seat missing from the list counts as empty). Newer wins; the answer lists what was applied, kept and unmatched.
create function public.hdg_import_club_officers(p_club text, p_as_of date, p_seats jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare club text := hdg_sync_private.plain_club_number(p_club); seat text; mid text; pid uuid; cur public.hdg_roles;
 applied jsonb := '[]'; kept jsonb := '[]'; unmatched jsonb := '[]'; listed jsonb;
begin
 if club is null then raise exception 'Unknown club' using errcode = '22023'; end if;
 if not hdg_sync_private.leads_club(club) then
   raise exception 'Only leaders import officer lists' using errcode = '42501';
 end if;
 if p_as_of is null or p_as_of > hdg_sync_private.today() then
   raise exception 'The officer list needs its date (not in the future)' using errcode = '22023';
 end if;
 if jsonb_typeof(p_seats) is distinct from 'array' then raise exception 'Seats must be a list' using errcode = '22023'; end if;
 foreach seat in array hdg_sync_private.club_seats() loop
   select e.value into listed from jsonb_array_elements(p_seats) e where e.value->>'role' = seat limit 1;
   mid := nullif(ltrim(btrim(coalesce(listed->>'memberId', '')), '0'), '');
   pid := null;
   if mid is not null then
     select p.id into pid from public.hdg_people p where ltrim(p.ti_member_id, '0') = mid;
     if pid is null then unmatched := unmatched || jsonb_build_object('role', seat, 'memberId', listed->>'memberId'); continue; end if;
   end if;
   perform pg_advisory_xact_lock(hashtext('hdg-exco:' || club || ':' || seat));
   cur := hdg_sync_private.seat_holder(club, seat);
   if cur.id is not null and cur.source in ('club', 'leader') and cur.source_at::date >= p_as_of then
     if cur.person_id is distinct from pid then kept := kept || jsonb_build_object('role', seat, 'changedAt', cur.source_at); end if;
     continue;
   end if;
   if cur.id is not null and cur.person_id is not distinct from pid then
     update public.hdg_roles set source = 'import', source_at = p_as_of::timestamptz where id = cur.id;
     continue;
   end if;
   if cur.id is null and pid is null then continue; end if;
   perform hdg_sync_private.end_seat(club, seat);
   if pid is not null then perform hdg_sync_private.start_seat(club, seat, pid, 'import', p_as_of::timestamptz); end if;
   applied := applied || jsonb_build_object('role', seat, 'person', pid);
 end loop;
 if exists (select 1 from public.hdg_clubs c where c.club_number = club) then
   insert into public.hdg_import_freshness(club_number, kind, as_of, imported_by) values (club, 'officers', p_as_of, auth.uid())
   on conflict (club_number, kind) do update set as_of = greatest(public.hdg_import_freshness.as_of, excluded.as_of),
     imported_at = now(), imported_by = excluded.imported_by;
 end if;
 return jsonb_build_object('applied', applied, 'kept', kept, 'unmatched', unmatched);
end $$;

-- The clubs where the signed-in person is a current officer (the Member app shows them a Club Exco tab).
create function public.hdg_my_exco_clubs() returns jsonb language sql stable security definer set search_path to ''
as $$
 select coalesce(jsonb_agg(jsonb_build_object('club', x.club, 'name', x.name) order by x.name), '[]'::jsonb)
 from (select distinct r.scope_code club, coalesce(c.name, r.scope_code) name from hdg_sync_private.my_roles() r
       left join public.hdg_clubs c on c.club_number = r.scope_code where r.scope_type = 'club') x
$$;

-- Seats changed by clubs or leaders since a moment, for the leader app's Exco directory (Division G scope).
create function public.hdg_exco_changes(p_since timestamptz) returns jsonb language sql stable security definer set search_path to ''
as $$
 select coalesce(jsonb_agg(jsonb_build_object('club', r.scope_code, 'role', r.role, 'person', r.person_id, 'name', p.name,
     'memberId', p.ti_member_id, 'source', r.source, 'changedAt', r.source_at, 'active',
     r.starts_on <= hdg_sync_private.today() and (r.ends_on is null or r.ends_on >= hdg_sync_private.today()))
   order by r.source_at), '[]'::jsonb)
 from public.hdg_roles r join public.hdg_people p on p.id = r.person_id
 where r.scope_type = 'club' and r.source in ('club', 'leader') and r.source_at > coalesce(p_since, '-infinity')
   and hdg_sync_private.leads_club(r.scope_code)
$$;

revoke execute on function hdg_sync_private.club_seats(), hdg_sync_private.is_officer_of(text), hdg_sync_private.leads_club(text),
  hdg_sync_private.can_edit_exco(text), hdg_sync_private.seat_holder(text, text), hdg_sync_private.end_seat(text, text),
  hdg_sync_private.start_seat(text, text, uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.hdg_club_exco(text), public.hdg_set_club_officer(text, text, uuid), public.hdg_my_exco_clubs(),
  public.hdg_import_club_officers(text, date, jsonb), public.hdg_exco_changes(timestamptz) from public, anon;
grant execute on function public.hdg_club_exco(text), public.hdg_set_club_officer(text, text, uuid), public.hdg_my_exco_clubs(),
  public.hdg_import_club_officers(text, date, jsonb), public.hdg_exco_changes(timestamptz) to authenticated;

commit;
