-- 016: more for role takers and club members (owner decision 25 November 2026).
--   Club officers and leaders: everything (unchanged, can_edit_meeting).
--   Toastmaster of the Meeting: edits the whole agenda of their meeting, from the day before it to 60 days ahead.
--   Every role taker (any agenda role, speaker or evaluator): fixes their own agenda line in that window; on the
--     meeting day (day before to day after) also saves timer times, Table Topics names and ballots.
--   Club members (active membership): see their club's meetings, put themselves into an empty role or a new
--     speaker line, and on the meeting day step in to save timer times, Table Topics names and ballots.
--   Ballots: leaders, the ballot counter and the Toastmaster replace the list and see results; anyone else who
--     may help only adds new ballot rows (they cannot see or remove other ballots).
--   People from other clubs who hold no role in the meeting, and guests, get nothing.
-- An agenda save by someone allowed only their own line keeps the stored agenda and takes over only the changes
-- that are theirs; anything else is left as stored and reported back as "trimmed".
begin;

create function hdg_sync_private.is_mine(p_club text, p_name text) returns boolean language sql stable security definer set search_path to ''
as $$ select coalesce(hdg_sync_private.agenda_name_person(p_club, p_name) in (select hdg_sync_private.my_people()), false) $$;

create function hdg_sync_private.my_name_keys() returns setof text language sql stable security definer set search_path to ''
as $$ select distinct k from hdg_sync_private.my_people() p, lateral hdg_sync_private.person_name_keys(p) k $$;

-- Roles the signed-in person holds in one agenda: role keys, plus 'speaker' and 'evaluator'.
-- A cheap name check runs first, so only names that could be theirs go through the full match.
create function hdg_sync_private.agenda_roles_of_me(p_club text, p_agenda jsonb) returns text[] language sql stable security definer set search_path to ''
as $$
 with mine as (select array(select hdg_sync_private.my_name_keys()) keys),
 names as (
   select r.key role, r.value person from jsonb_each_text(case when jsonb_typeof(p_agenda->'roles') = 'object' then p_agenda->'roles' else '{}'::jsonb end) r
   where r.key ~ '^[A-Za-z]{1,40}$'
   union all
   select 'speaker', s->>'name' from jsonb_array_elements(case when jsonb_typeof(p_agenda->'speakers') = 'array' then p_agenda->'speakers' else '[]'::jsonb end) s
   where jsonb_typeof(s) = 'object'
   union all
   select 'evaluator', s->>'evaluator' from jsonb_array_elements(case when jsonb_typeof(p_agenda->'speakers') = 'array' then p_agenda->'speakers' else '[]'::jsonb end) s
   where jsonb_typeof(s) = 'object'
 )
 select coalesce(array_agg(distinct n.role order by n.role), '{}') from names n, mine
 where case when hdg_sync_private.name_key(n.person) = any(mine.keys) then hdg_sync_private.is_mine(p_club, n.person) else false end
$$;

-- On the meeting day (day before to day after): every role this person holds. Used by hdg_manage_ballot.
create or replace function hdg_sync_private.my_meeting_roles(p_meeting_id text) returns text[] language sql stable security definer set search_path to ''
as $$
 select coalesce((select hdg_sync_private.agenda_roles_of_me(m.club_number, m.agenda) from public.hdg_meetings m
   where m.meeting_id = p_meeting_id
     and m.meeting_date between hdg_sync_private.today() - 1 and hdg_sync_private.today() + 1), '{}')
$$;

create function hdg_sync_private.is_club_member(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$
 select exists (select 1 from public.hdg_memberships m
   where m.club_number = p_club and m.status = 'active' and m.person_id in (select hdg_sync_private.my_people()))
$$;

-- What the signed-in person may do in one meeting.
create function hdg_sync_private.meeting_rights(p_meeting_id text) returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare m public.hdg_meetings%rowtype; club text; reader boolean; day boolean; upcoming boolean; member boolean;
  roles text[] := '{}'; today_roles text[] := '{}'; helper boolean; counter boolean;
begin
 club := hdg_sync_private.plain_club_number(split_part(coalesce(p_meeting_id, ''), '-', 2));
 if club is null then return jsonb_build_object('leader', false, 'read', false, 'roles', '[]'::jsonb, 'clubMember', false,
   'agenda', 'none', 'timer_log', false, 'topics', false, 'ballots', 'none', 'seeBallots', false, 'downloaded', false); end if;
 if hdg_sync_private.can_edit_meeting(club) then
   return jsonb_build_object('leader', true, 'read', true, 'roles', '[]'::jsonb, 'clubMember', hdg_sync_private.is_club_member(club),
     'agenda', 'full', 'timer_log', true, 'topics', true, 'ballots', 'replace', 'seeBallots', true, 'downloaded', true);
 end if;
 reader := hdg_sync_private.has_club_read_scope(club);
 member := hdg_sync_private.is_club_member(club);
 select * into m from public.hdg_meetings where meeting_id = p_meeting_id;
 day := coalesce(m.meeting_date between hdg_sync_private.today() - 1 and hdg_sync_private.today() + 1, false);
 upcoming := coalesce(m.meeting_date between hdg_sync_private.today() - 1 and hdg_sync_private.today() + 60, false);
 if m.meeting_id is not null and upcoming then roles := hdg_sync_private.agenda_roles_of_me(club, m.agenda); end if;
 if day then today_roles := roles; end if;
 helper := day and (cardinality(today_roles) > 0 or member);
 counter := day and today_roles && array['ballotCounter', 'tom'];
 return jsonb_build_object('leader', false, 'read', reader or member or cardinality(roles) > 0,
   'roles', to_jsonb(roles), 'clubMember', member,
   'agenda', case when m.meeting_id is null then 'none'
                  when upcoming and 'tom' = any(roles) then 'full'
                  when upcoming and (member or cardinality(roles) > 0) then 'own' else 'none' end,
   'timer_log', helper, 'topics', helper,
   'ballots', case when counter then 'replace' when helper then 'append' else 'none' end,
   'seeBallots', reader or counter,
   'downloaded', upcoming and 'tom' = any(roles));
end $$;

-- Keep the stored agenda and take over only the person's own changes: a role that was empty or theirs and is
-- set to them, a speaker line or evaluator part that was empty or theirs and stays theirs, or a new speaker line
-- in their own name (sign up). Everything else stays as stored.
create function hdg_sync_private.merge_own_agenda(p_club text, p_old jsonb, p_new jsonb) returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare result jsonb := coalesce(p_old, '{}'::jsonb); k text; v text; was text; i int;
  olds jsonb; news jsonb; os jsonb; ns jsonb; e jsonb; roles jsonb;
begin
 roles := case when jsonb_typeof(result->'roles') = 'object' then result->'roles' else '{}'::jsonb end;
 if jsonb_typeof(p_new->'roles') = 'object' then
   for k, v in select key, value from jsonb_each_text(p_new->'roles') loop
     was := roles->>k;
     if k ~ '^[A-Za-z]{1,40}$' and v is distinct from was
        and (nullif(btrim(coalesce(was, '')), '') is null or hdg_sync_private.is_mine(p_club, was))
        and hdg_sync_private.is_mine(p_club, v) then
       roles := roles || jsonb_build_object(k, v);
     end if;
   end loop;
   if roles is distinct from coalesce(result->'roles', '{}'::jsonb) then result := result || jsonb_build_object('roles', roles); end if;
 end if;
 olds := case when jsonb_typeof(result->'speakers') = 'array' then result->'speakers' else '[]'::jsonb end;
 news := case when jsonb_typeof(p_new->'speakers') = 'array' then p_new->'speakers' else '[]'::jsonb end;
 for i in 0 .. jsonb_array_length(news) - 1 loop
   ns := news->i;
   continue when jsonb_typeof(ns) is distinct from 'object';
   os := olds->i;
   if os is null then
     if i = jsonb_array_length(olds) and jsonb_array_length(olds) < 30 and hdg_sync_private.is_mine(p_club, ns->>'name') then
       olds := olds || jsonb_build_array((select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(ns) where key not like 'evaluator%'));
     end if;
     continue;
   end if;
   continue when jsonb_typeof(os) is distinct from 'object' or ns = os;
   e := os;
   if (nullif(btrim(coalesce(os->>'name', '')), '') is null or hdg_sync_private.is_mine(p_club, os->>'name'))
      and hdg_sync_private.is_mine(p_club, ns->>'name') then
     e := (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(e) where key like 'evaluator%')
       || (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(ns) where key not like 'evaluator%');
   end if;
   if (nullif(btrim(coalesce(os->>'evaluator', '')), '') is null or hdg_sync_private.is_mine(p_club, os->>'evaluator'))
      and hdg_sync_private.is_mine(p_club, ns->>'evaluator') then
     e := (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(e) where key not like 'evaluator%')
       || (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(ns) where key like 'evaluator%');
   end if;
   olds := jsonb_set(olds, array[i::text], e);
 end loop;
 if olds is distinct from coalesce(result->'speakers', '[]'::jsonb) then result := result || jsonb_build_object('speakers', olds); end if;
 return result;
end $$;

create or replace function public.hdg_my_meeting_access(p_meeting_id text) returns jsonb language sql stable security definer set search_path to ''
as $$
 select r || jsonb_build_object('meetingId', p_meeting_id,
   'exists', exists (select 1 from public.hdg_meetings where meeting_id = p_meeting_id),
   'canEditAgenda', r->>'agenda' <> 'none', 'canSaveTimer', (r->>'timer_log')::boolean,
   'canSaveBallots', r->>'ballots' <> 'none', 'canSaveTopics', (r->>'topics')::boolean,
   'canSeeResults', (r->>'seeBallots')::boolean)
 from (select hdg_sync_private.meeting_rights(p_meeting_id) r) x
$$;

create or replace function public.hdg_save_meeting(p_meeting_id text, p_meeting_date date, p_patch jsonb, p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare club text; cur timestamptz; d record; result timestamptz; created boolean := false; fields jsonb; patch jsonb;
  rights jsonb; leader boolean; stored public.hdg_meetings%rowtype; trimmed text[] := '{}'; merged jsonb;
begin
 if p_meeting_id is null or p_meeting_id !~ '^agenda-[A-Za-z0-9-]{1,100}$' then
   raise exception 'Unknown meeting code' using errcode = '22023';
 end if;
 club := hdg_sync_private.plain_club_number(split_part(p_meeting_id, '-', 2));
 if club is null then raise exception 'The meeting code has no club number' using errcode = '22023'; end if;
 if jsonb_typeof(p_patch) is distinct from 'object'
    or (p_patch - array['agenda', 'timer_log', 'ballots', 'topics', 'downloaded']) <> '{}'::jsonb
    or (p_patch ? 'agenda' and jsonb_typeof(p_patch->'agenda') <> 'object')
    or exists (select 1 from unnest(array['timer_log', 'ballots', 'topics']) f where p_patch ? f and jsonb_typeof(p_patch->f) <> 'array')
    or (p_patch ? 'downloaded' and jsonb_typeof(p_patch->'downloaded') <> 'boolean') then
   raise exception 'Only agenda, timer_log, ballots, topics and downloaded can be saved' using errcode = '22023';
 end if;
 rights := hdg_sync_private.meeting_rights(p_meeting_id);
 leader := (rights->>'leader')::boolean;
 patch := p_patch;
 if not leader then
   select * into stored from public.hdg_meetings where meeting_id = p_meeting_id for update;
   if stored.meeting_id is null then
     raise exception 'This meeting has not been saved by its club yet' using errcode = '42501';
   end if;
   -- A download mark from someone else is simply not recorded.
   if not (rights->>'downloaded')::boolean then patch := patch - 'downloaded'; end if;
   if (patch ? 'agenda' and rights->>'agenda' = 'none')
      or (patch ? 'timer_log' and not (rights->>'timer_log')::boolean)
      or (patch ? 'topics' and not (rights->>'topics')::boolean)
      or (patch ? 'ballots' and rights->>'ballots' = 'none') then
     raise exception 'This part of the meeting belongs to another role' using errcode = '42501';
   end if;
   if patch ? 'agenda' and rights->>'agenda' = 'own' then
     merged := hdg_sync_private.merge_own_agenda(club, stored.agenda, patch->'agenda');
     if (merged - 'warnings'::text) is distinct from ((patch->'agenda') - 'warnings'::text) then trimmed := array_append(trimmed, 'agenda'); end if;
     if merged = stored.agenda then patch := patch - 'agenda'; else patch := jsonb_set(patch, '{agenda}', merged); end if;
   end if;
   if patch ? 'ballots' and rights->>'ballots' = 'append' then
     merged := stored.ballots || coalesce((select jsonb_agg(b) from jsonb_array_elements(patch->'ballots') b
       where jsonb_typeof(b) = 'object' and jsonb_typeof(b->'id') = 'string'
         and not exists (select 1 from jsonb_array_elements(stored.ballots) o where o->>'id' = b->>'id')), '[]'::jsonb);
     trimmed := array_append(trimmed, 'ballots');   -- the helper cannot see the full list; they get back only what they may see
     if jsonb_array_length(merged) > 1000 then raise exception 'Too many ballots' using errcode = '22023'; end if;
     if merged = stored.ballots then patch := patch - 'ballots'; else patch := jsonb_set(patch, '{ballots}', merged); end if;
   end if;
 else
   insert into public.hdg_meetings(meeting_id, club_number, meeting_date, created_by, updated_by)
   values (p_meeting_id, club, p_meeting_date, auth.uid(), auth.uid())
   on conflict (meeting_id) do nothing;
   created := found;
 end if;
 select updated_at into cur from public.hdg_meetings where meeting_id = p_meeting_id for update;
 if cur is null then raise exception 'This meeting has not been saved yet' using errcode = '42501'; end if;
 fields := patch - 'downloaded';
 if created then
   select fields as patch, '{}'::text[] as late into d;
 else
   -- Added ballots were merged into the stored list under the row lock above, so they are never late.
   select * into d from hdg_sync_private.drop_late_fields('hdg_meetings', p_meeting_id, cur, p_expected_updated_at,
     case when not leader and rights->>'ballots' = 'append' then fields - 'ballots'::text else fields end);
   if not leader and rights->>'ballots' = 'append' and fields ? 'ballots' then
     d.patch := d.patch || jsonb_build_object('ballots', fields->'ballots');
   end if;
 end if;
 if d.patch = '{}'::jsonb and not coalesce((patch->>'downloaded')::boolean, false) and not created then
   return jsonb_build_object('applied', false, 'created', false, 'updated_at', cur, 'set_aside', to_jsonb(d.late), 'trimmed', to_jsonb(trimmed));
 end if;
 update public.hdg_meetings set
   meeting_date = case when leader then coalesce(p_meeting_date, meeting_date) else meeting_date end,
   agenda = case when d.patch ? 'agenda' then d.patch->'agenda' else agenda end,
   timer_log = case when d.patch ? 'timer_log' then d.patch->'timer_log' else timer_log end,
   ballots = case when d.patch ? 'ballots' then d.patch->'ballots' else ballots end,
   topics = case when d.patch ? 'topics' then d.patch->'topics' else topics end,
   first_downloaded_at = case when coalesce((patch->>'downloaded')::boolean, false) then coalesce(first_downloaded_at, now()) else first_downloaded_at end,
   updated_at = clock_timestamp(), updated_by = auth.uid()
 where meeting_id = p_meeting_id returning updated_at into result;
 return jsonb_build_object('applied', true, 'created', created, 'updated_at', result, 'set_aside', to_jsonb(d.late), 'trimmed', to_jsonb(trimmed));
end $$;

-- Reading: leaders and readers see whole meetings; club members and role takers see the agenda, times and Table
-- Topics; ballots only with seeBallots. Each meeting carries the reader's rights so the app sends only what counts.
create or replace function public.hdg_meetings_list(p_club text default null, p_from date default null, p_meeting_id text default null)
returns jsonb language sql stable security definer set search_path to ''
as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'meetingId', m.meeting_id, 'clubNumber', m.club_number, 'meetingDate', m.meeting_date,
   'agenda', m.agenda, 'timerLog', m.timer_log,
   'ballots', case when (v.r->>'seeBallots')::boolean then m.ballots else '[]'::jsonb end,
   'topics', m.topics, 'myRoles', v.r->'roles', 'rights', v.r,
   'firstDownloadedAt', m.first_downloaded_at, 'updatedAt', m.updated_at) order by m.meeting_date desc nulls last, m.meeting_id), '[]'::jsonb)
 from public.hdg_meetings m,
   lateral (select hdg_sync_private.meeting_rights(m.meeting_id) r) v
 where (p_meeting_id is null or m.meeting_id = p_meeting_id)
   and (p_club is null or m.club_number = hdg_sync_private.plain_club_number(p_club))
   and (p_meeting_id is not null or m.meeting_date is null
        or m.meeting_date >= coalesce(p_from, hdg_sync_private.today() - 120))
   and ((v.r->>'leader')::boolean or (v.r->>'read')::boolean)
$$;

revoke execute on function hdg_sync_private.is_mine(text, text), hdg_sync_private.my_name_keys(),
  hdg_sync_private.agenda_roles_of_me(text, jsonb), hdg_sync_private.is_club_member(text),
  hdg_sync_private.meeting_rights(text), hdg_sync_private.merge_own_agenda(text, jsonb, jsonb) from public, anon, authenticated;

commit;
