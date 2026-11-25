-- 015: one record per club meeting (owner request 25 November 2026). TEST project first.
-- Every meeting is saved under its meeting code (agenda-<club number>-<date>, e.g. agenda-28680376-2026-11-24),
-- so every leader account and device works on the same meeting: the slide operator, the timer and the ballot
-- counter can each save at the same time. The record holds the agenda, the timer times, the ballots typed in on
-- a device and the Table Topics names in separate fields, so saves of different fields never overwrite each
-- other. A save based on an older version keeps the newer data and sets the late value aside, without an error
-- (project/DISTRICT_PLAN.md rule 33). The first agenda download is recorded: from then on the meeting is real.
-- Votes stay anonymous (rule 25): ballots hold choices only, never a voter.
--
-- Who can save: Division G's approved leaders for Division G clubs (they sign in through hdg_officer_access),
-- and anyone whose roles give editing scope over the club (has_club_scope). Read-only division council members
-- can read. Phone votes cast through a voting link stay in hdg_community_private.votes.

create table public.hdg_meetings (
 meeting_id text primary key check (meeting_id ~ '^agenda-[A-Za-z0-9-]{1,100}$'),
 club_number text not null check (club_number ~ '^[1-9][0-9]*$'),
 meeting_date date,
 agenda jsonb not null default '{}'::jsonb check (jsonb_typeof(agenda) = 'object'),
 timer_log jsonb not null default '[]'::jsonb check (jsonb_typeof(timer_log) = 'array'),
 ballots jsonb not null default '[]'::jsonb check (jsonb_typeof(ballots) = 'array'),
 topics jsonb not null default '[]'::jsonb check (jsonb_typeof(topics) = 'array'),
 first_downloaded_at timestamptz,
 created_at timestamptz not null default now(),
 created_by uuid,
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid,
 check (octet_length(agenda::text) + octet_length(timer_log::text) + octet_length(ballots::text) + octet_length(topics::text) < 400000));
create index hdg_meetings_club_date on public.hdg_meetings (club_number, meeting_date desc);
alter table public.hdg_meetings enable row level security;
revoke all on public.hdg_meetings from public, anon, authenticated;

-- Edit history for meetings (key: the meeting code). Same function as 002, with the meetings key added.
create or replace function hdg_sync_private.log_edit() returns trigger language plpgsql security definer set search_path to ''
as $$
declare k text; r jsonb;
begin
 r := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
 k := case tg_table_name
   when 'hdg_clubs' then r->>'club_number'
   when 'hdg_club_alignment' then (r->>'year_start') || ':' || (r->>'club_number')
   when 'hdg_meetings' then r->>'meeting_id'
   else r->>'id' end;
 insert into hdg_sync_private.edit_history(actor, table_name, row_key, op, before, after)
 values (auth.uid(), tg_table_name, k, tg_op,
   case when tg_op <> 'INSERT' then to_jsonb(old) end, case when tg_op <> 'DELETE' then to_jsonb(new) end);
 return coalesce(new, old);
end $$;
create trigger hdg_meetings_history after insert or update or delete on public.hdg_meetings
 for each row execute function hdg_sync_private.log_edit();

-- Club number as stored in the directory: digits without leading zeros (00763437 -> 763437).
create function hdg_sync_private.plain_club_number(p text) returns text language sql immutable set search_path to ''
as $$ select nullif(ltrim(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'), '0'), '') $$;

create function hdg_sync_private.can_edit_meeting(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$
 select hdg_sync_private.is_maintainer()
  or hdg_sync_private.has_club_scope(p_club)
  or (public.hdg_access_mode() = 'leader'
      and left(coalesce(hdg_sync_private.club_area(p_club, hdg_sync_private.year_of(hdg_sync_private.today())), ''), 1) = 'G')
$$;

create function hdg_sync_private.can_read_meeting(p_club text) returns boolean language sql stable security definer set search_path to ''
as $$ select hdg_sync_private.can_edit_meeting(p_club) or hdg_sync_private.has_club_read_scope(p_club) $$;

-- Save a meeting. p_patch may hold agenda, timer_log, ballots, topics and downloaded (true records the first
-- download). The first save creates the record. Answer: {applied, created, updated_at, set_aside: [fields]}.
create function public.hdg_save_meeting(p_meeting_id text, p_meeting_date date, p_patch jsonb, p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare club text; cur timestamptz; d record; result timestamptz; created boolean := false; fields jsonb;
begin
 if p_meeting_id is null or p_meeting_id !~ '^agenda-[A-Za-z0-9-]{1,100}$' then
   raise exception 'Unknown meeting code' using errcode = '22023';
 end if;
 club := hdg_sync_private.plain_club_number(split_part(p_meeting_id, '-', 2));
 if club is null then raise exception 'The meeting code has no club number' using errcode = '22023'; end if;
 if not hdg_sync_private.can_edit_meeting(club) then
   raise exception 'This club is outside your scope' using errcode = '42501';
 end if;
 if jsonb_typeof(p_patch) is distinct from 'object'
    or (p_patch - array['agenda', 'timer_log', 'ballots', 'topics', 'downloaded']) <> '{}'::jsonb
    or (p_patch ? 'agenda' and jsonb_typeof(p_patch->'agenda') <> 'object')
    or exists (select 1 from unnest(array['timer_log', 'ballots', 'topics']) f where p_patch ? f and jsonb_typeof(p_patch->f) <> 'array')
    or (p_patch ? 'downloaded' and jsonb_typeof(p_patch->'downloaded') <> 'boolean') then
   raise exception 'Only agenda, timer_log, ballots, topics and downloaded can be saved' using errcode = '22023';
 end if;
 insert into public.hdg_meetings(meeting_id, club_number, meeting_date, created_by, updated_by)
 values (p_meeting_id, club, p_meeting_date, auth.uid(), auth.uid())
 on conflict (meeting_id) do nothing;
 created := found;
 select updated_at into cur from public.hdg_meetings where meeting_id = p_meeting_id for update;
 fields := p_patch - 'downloaded';
 if created then
   select fields as patch, '{}'::text[] as late into d;
 else
   select * into d from hdg_sync_private.drop_late_fields('hdg_meetings', p_meeting_id, cur, p_expected_updated_at, fields);
 end if;
 if d.patch = '{}'::jsonb and not coalesce((p_patch->>'downloaded')::boolean, false) and not created then
   return jsonb_build_object('applied', false, 'created', false, 'updated_at', cur, 'set_aside', to_jsonb(d.late));
 end if;
 update public.hdg_meetings set
   meeting_date = coalesce(p_meeting_date, meeting_date),
   agenda = case when d.patch ? 'agenda' then d.patch->'agenda' else agenda end,
   timer_log = case when d.patch ? 'timer_log' then d.patch->'timer_log' else timer_log end,
   ballots = case when d.patch ? 'ballots' then d.patch->'ballots' else ballots end,
   topics = case when d.patch ? 'topics' then d.patch->'topics' else topics end,
   first_downloaded_at = case when coalesce((p_patch->>'downloaded')::boolean, false) then coalesce(first_downloaded_at, now()) else first_downloaded_at end,
   updated_at = clock_timestamp(), updated_by = auth.uid()
 where meeting_id = p_meeting_id returning updated_at into result;
 return jsonb_build_object('applied', true, 'created', created, 'updated_at', result, 'set_aside', to_jsonb(d.late));
end $$;

-- Meetings the caller may read: one meeting by code, or a club's meetings (or all readable clubs) from a date.
-- Default window: the last 120 days and everything after. Because meetings follow a similar pattern, the app
-- can start a new agenda from the club's latest meeting.
create function public.hdg_meetings_list(p_club text default null, p_from date default null, p_meeting_id text default null)
returns jsonb language sql stable security definer set search_path to ''
as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'meetingId', m.meeting_id, 'clubNumber', m.club_number, 'meetingDate', m.meeting_date,
   'agenda', m.agenda, 'timerLog', m.timer_log, 'ballots', m.ballots, 'topics', m.topics,
   'firstDownloadedAt', m.first_downloaded_at, 'updatedAt', m.updated_at) order by m.meeting_date desc nulls last, m.meeting_id), '[]'::jsonb)
 from public.hdg_meetings m
 where (p_meeting_id is null or m.meeting_id = p_meeting_id)
   and (p_club is null or m.club_number = hdg_sync_private.plain_club_number(p_club))
   and (p_meeting_id is not null or m.meeting_date is null
        or m.meeting_date >= coalesce(p_from, hdg_sync_private.today() - 120))
   and hdg_sync_private.can_read_meeting(m.club_number)
$$;

revoke execute on function hdg_sync_private.plain_club_number(text), hdg_sync_private.can_edit_meeting(text),
  hdg_sync_private.can_read_meeting(text), public.hdg_save_meeting(text, date, jsonb, timestamptz),
  public.hdg_meetings_list(text, date, text) from public, anon;
grant execute on function public.hdg_save_meeting(text, date, jsonb, timestamptz),
  public.hdg_meetings_list(text, date, text) to authenticated;

-- ---------------------------------------------------------------- the meeting's own role takers
-- Role takers change every meeting (member A is Timer this week, member C next week). A signed-in person gets a
-- meeting function only from THAT meeting's agenda: their verified email gives their person record, and their
-- name, nickname or an alias must match the name on the agenda role. A name that fits more than one person
-- (two members called Eka) gives nobody the role. A "(BTC)" style suffix is ignored when matching. Meeting
-- functions work from the day before the meeting to the day after it.
--   timer          -> saves the timer times
--   ballotCounter  -> saves typed-in ballots, sees ballot results and phone votes
--   ttm            -> saves the Table Topics names
--   tom            -> sees ballot results (rule 27: ballot counter, Toastmaster of the Meeting and VPE)
-- Leaders and club officers (can_edit_meeting) can do all of it; the club's VPE is a club officer.

create function hdg_sync_private.name_key(p text) returns text language sql immutable set search_path to ''
as $$ select nullif(btrim(regexp_replace(regexp_replace(lower(coalesce(p, '')), '\([^)]*\)', ' ', 'g'), '\s+', ' ', 'g')), '') $$;

create function hdg_sync_private.person_name_keys(p_person uuid) returns setof text language sql stable security definer set search_path to ''
as $$
 select distinct k from public.hdg_people p,
   lateral unnest(array[hdg_sync_private.name_key(p.name), hdg_sync_private.name_key(p.nickname)]
                  || array(select hdg_sync_private.name_key(a) from unnest(coalesce(p.aliases, '{}')) a)) k
 where p.id = p_person and k is not null
$$;

-- The one person an agenda name points to: first among the club's active members, otherwise among everyone.
create function hdg_sync_private.agenda_name_person(p_club text, p_name text) returns uuid language plpgsql stable security definer set search_path to ''
as $$
declare key text := hdg_sync_private.name_key(p_name); hits uuid[];
begin
 if key is null then return null; end if;
 select array_agg(distinct p.id) into hits from public.hdg_people p
 join public.hdg_memberships m on m.person_id = p.id and m.club_number = p_club and m.status = 'active'
 where key in (select hdg_sync_private.person_name_keys(p.id));
 if cardinality(hits) = 1 then return hits[1]; end if;
 if cardinality(hits) > 1 then return null; end if;
 select array_agg(distinct p.id) into hits from public.hdg_people p
 where key in (select hdg_sync_private.person_name_keys(p.id));
 return case when cardinality(hits) = 1 then hits[1] end;
end $$;

create function hdg_sync_private.my_meeting_roles(p_meeting_id text) returns text[] language sql stable security definer set search_path to ''
as $$
 select coalesce(array_agg(distinct r.key order by r.key), '{}')
 from public.hdg_meetings m,
   lateral jsonb_each_text(case when jsonb_typeof(m.agenda->'roles') = 'object' then m.agenda->'roles' else '{}'::jsonb end) r
 where m.meeting_id = p_meeting_id
   and m.meeting_date between hdg_sync_private.today() - 1 and hdg_sync_private.today() + 1
   and r.key in ('timer', 'ballotCounter', 'ttm', 'tom')
   and hdg_sync_private.agenda_name_person(m.club_number, r.value) in (select hdg_sync_private.my_people())
$$;

-- What the signed-in person may do in one meeting (the app shows the matching tools).
create function public.hdg_my_meeting_access(p_meeting_id text) returns jsonb language sql stable security definer set search_path to ''
as $$
 with m as (select club_number from public.hdg_meetings where meeting_id = p_meeting_id),
 a as (select coalesce((select hdg_sync_private.can_edit_meeting(club_number) from m), false) leader,
              hdg_sync_private.my_meeting_roles(p_meeting_id) roles)
 select jsonb_build_object('meetingId', p_meeting_id, 'exists', exists (select 1 from m), 'leader', a.leader, 'roles', to_jsonb(a.roles),
   'canEditAgenda', a.leader,
   'canSaveTimer', a.leader or 'timer' = any(a.roles),
   'canSaveBallots', a.leader or 'ballotCounter' = any(a.roles),
   'canSaveTopics', a.leader or 'ttm' = any(a.roles),
   'canSeeResults', a.leader or a.roles && array['ballotCounter', 'tom'])
 from a
$$;

-- Saving: leaders save every field; a meeting's role takers save only their own field.
create or replace function public.hdg_save_meeting(p_meeting_id text, p_meeting_date date, p_patch jsonb, p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare club text; cur timestamptz; d record; result timestamptz; created boolean := false; fields jsonb;
  leader boolean; roles text[];
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
 leader := hdg_sync_private.can_edit_meeting(club);
 if not leader then
   roles := hdg_sync_private.my_meeting_roles(p_meeting_id);
   if p_patch ?| array['agenda', 'downloaded']
      or (p_patch ? 'timer_log' and not 'timer' = any(roles))
      or (p_patch ? 'ballots' and not 'ballotCounter' = any(roles))
      or (p_patch ? 'topics' and not 'ttm' = any(roles)) then
     raise exception 'This part of the meeting belongs to another role' using errcode = '42501';
   end if;
 end if;
 if leader then
   insert into public.hdg_meetings(meeting_id, club_number, meeting_date, created_by, updated_by)
   values (p_meeting_id, club, p_meeting_date, auth.uid(), auth.uid())
   on conflict (meeting_id) do nothing;
   created := found;
 end if;
 select updated_at into cur from public.hdg_meetings where meeting_id = p_meeting_id for update;
 if cur is null then raise exception 'This meeting has not been saved yet' using errcode = '42501'; end if;
 fields := p_patch - 'downloaded';
 if created then
   select fields as patch, '{}'::text[] as late into d;
 else
   select * into d from hdg_sync_private.drop_late_fields('hdg_meetings', p_meeting_id, cur, p_expected_updated_at, fields);
 end if;
 if d.patch = '{}'::jsonb and not coalesce((p_patch->>'downloaded')::boolean, false) and not created then
   return jsonb_build_object('applied', false, 'created', false, 'updated_at', cur, 'set_aside', to_jsonb(d.late));
 end if;
 update public.hdg_meetings set
   meeting_date = case when leader then coalesce(p_meeting_date, meeting_date) else meeting_date end,
   agenda = case when d.patch ? 'agenda' then d.patch->'agenda' else agenda end,
   timer_log = case when d.patch ? 'timer_log' then d.patch->'timer_log' else timer_log end,
   ballots = case when d.patch ? 'ballots' then d.patch->'ballots' else ballots end,
   topics = case when d.patch ? 'topics' then d.patch->'topics' else topics end,
   first_downloaded_at = case when coalesce((p_patch->>'downloaded')::boolean, false) then coalesce(first_downloaded_at, now()) else first_downloaded_at end,
   updated_at = clock_timestamp(), updated_by = auth.uid()
 where meeting_id = p_meeting_id returning updated_at into result;
 return jsonb_build_object('applied', true, 'created', created, 'updated_at', result, 'set_aside', to_jsonb(d.late));
end $$;

-- Reading: leaders and readers see whole meetings; a role taker sees their meeting's agenda, timer and topics,
-- and ballots only as ballot counter or Toastmaster of the Meeting.
create or replace function public.hdg_meetings_list(p_club text default null, p_from date default null, p_meeting_id text default null)
returns jsonb language sql stable security definer set search_path to ''
as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'meetingId', m.meeting_id, 'clubNumber', m.club_number, 'meetingDate', m.meeting_date,
   'agenda', m.agenda, 'timerLog', m.timer_log,
   'ballots', case when full_access or v.roles && array['ballotCounter', 'tom'] then m.ballots else '[]'::jsonb end,
   'topics', m.topics, 'myRoles', to_jsonb(v.roles),
   'firstDownloadedAt', m.first_downloaded_at, 'updatedAt', m.updated_at) order by m.meeting_date desc nulls last, m.meeting_id), '[]'::jsonb)
 from public.hdg_meetings m,
   lateral (select hdg_sync_private.can_read_meeting(m.club_number) full_access) f,
   lateral (select case when f.full_access then '{}'::text[] else hdg_sync_private.my_meeting_roles(m.meeting_id) end roles) v
 where (p_meeting_id is null or m.meeting_id = p_meeting_id)
   and (p_club is null or m.club_number = hdg_sync_private.plain_club_number(p_club))
   and (p_meeting_id is not null or m.meeting_date is null
        or m.meeting_date >= coalesce(p_from, hdg_sync_private.today() - 120))
   and (f.full_access or cardinality(v.roles) > 0)
$$;

-- ---------------------------------------------------------------- phone votes: one ballot per meeting
-- Before: a voting link belonged to the account that published it, so a second account saw no phone votes and
-- a second publish made a second link. Now a meeting has one ballot. Publishing again (by any allowed person)
-- updates the same link and keeps its votes. Leaders and the meeting's ballot counter may publish, close and
-- see the count; the Toastmaster of the Meeting may see the count.
create or replace function public.hdg_manage_ballot(
 p_meeting_id text, p_action text, p_title text default null, p_choices jsonb default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 item hdg_community_private.ballots%rowtype;
 category text;
 nominees jsonb;
 club text := hdg_sync_private.plain_club_number(split_part(coalesce(p_meeting_id, ''), '-', 2));
 roles text[] := hdg_sync_private.my_meeting_roles(p_meeting_id);
 manager boolean;
begin
 if p_meeting_id is null or length(btrim(p_meeting_id)) not between 1 and 200 then
   raise exception 'Select a meeting' using errcode = '22023';
 end if;
 manager := public.hdg_access_mode() = 'leader' or (club is not null and hdg_sync_private.can_edit_meeting(club)) or 'ballotCounter' = any(roles);
 if not (manager or (p_action = 'status' and 'tom' = any(roles))) then
   raise exception 'Only leaders, the ballot counter and the Toastmaster of the Meeting can see this ballot' using errcode = '42501';
 end if;
 case p_action
 when 'publish' then
   if p_title is null or length(btrim(p_title)) not between 1 and 160
     or jsonb_typeof(p_choices) is distinct from 'object'
     or octet_length(p_choices::text) > 40000
     or (p_choices - array['prepared', 'evaluation', 'topics']) <> '{}'::jsonb then
     raise exception 'Invalid ballot title or choices' using errcode = '22023';
   end if;
   foreach category in array array['prepared', 'evaluation', 'topics'] loop
     nominees := p_choices->category;
     if jsonb_typeof(nominees) is distinct from 'array' then
       raise exception 'Missing candidate category' using errcode = '22023';
     end if;
     if jsonb_array_length(nominees) > 100 or exists (
       select 1 from jsonb_array_elements(nominees) candidate
       where jsonb_typeof(candidate) <> 'object'
         or jsonb_typeof(candidate->'id') is distinct from 'string'
         or jsonb_typeof(candidate->'name') is distinct from 'string'
         or length(btrim(candidate->>'id')) not between 1 and 200
         or length(btrim(candidate->>'name')) not between 1 and 160
         or (case when jsonb_typeof(candidate)='object' then candidate - array['id', 'name'] end) <> '{}'::jsonb
     ) or jsonb_array_length(nominees) <> (
       select count(distinct candidate->>'id') from jsonb_array_elements(nominees) candidate
     ) then
       raise exception 'Invalid candidates' using errcode = '22023';
     end if;
   end loop;
   if not exists (select 1 from jsonb_each(p_choices) as c where jsonb_array_length(c.value) > 0) then
     raise exception 'Add at least one candidate' using errcode = '22023';
   end if;
   select * into item from hdg_community_private.ballots where meeting_id = p_meeting_id
   order by expires_at desc limit 1 for update;
   if item.id is null then
     insert into hdg_community_private.ballots(owner_id, meeting_id, title, choices, expires_at)
     values (auth.uid(), p_meeting_id, btrim(p_title), p_choices, now() + interval '24 hours')
     returning * into item;
   else
     update hdg_community_private.ballots
       set title = btrim(p_title), choices = p_choices, expires_at = now() + interval '24 hours', closed = false
     where id = item.id returning * into item;
   end if;
 when 'close' then
   update hdg_community_private.ballots set closed = true
   where id = (select id from hdg_community_private.ballots where meeting_id = p_meeting_id order by expires_at desc limit 1)
   returning * into item;
 when 'status' then
   select * into item from hdg_community_private.ballots where meeting_id = p_meeting_id order by expires_at desc limit 1;
 else
   raise exception 'Unknown ballot action' using errcode = '22023';
 end case;
 if item.id is null then return null; end if;
 return jsonb_build_object(
   'token', item.id, 'open', not item.closed and item.expires_at > now(),
   'expiresAt', item.expires_at, 'choices', item.choices,
   'responses', (select count(*) from hdg_community_private.votes where ballot_id = item.id),
   'counts', coalesce((
     select jsonb_object_agg(category_key, totals) from (
       select category_key, jsonb_object_agg(choice_id, num) as totals from (
         select selection.key as category_key, selection.value as choice_id, count(*) as num
         from hdg_community_private.votes v cross join lateral jsonb_each_text(v.choices) selection
         where v.ballot_id = item.id group by selection.key, selection.value
       ) candidate_totals group by category_key
     ) category_totals
   ), '{}'::jsonb)
 );
end;
$$;

-- Voting links: valid while open and not expired, whoever published them. Before, only a link published by an
-- approved Division G officer worked, so a ballot counter who is a regular member could not run the vote.
-- Publishing is limited by hdg_manage_ballot (leaders and that meeting's ballot counter).
create or replace function public.hdg_open_ballot(p_token uuid)
 returns jsonb language sql stable security definer set search_path to ''
as $function$
 select jsonb_build_object('title', b.title, 'choices', b.choices)
 from hdg_community_private.ballots b
 where b.id = p_token and not b.closed and b.expires_at > now();
$function$;

create or replace function public.hdg_cast_ballot(p_token uuid, p_browser_id uuid, p_choices jsonb)
 returns boolean language plpgsql security definer set search_path to ''
as $function$
declare
 item hdg_community_private.ballots%rowtype;
 category text;
 candidate_id text;
begin
 if p_browser_id is null or jsonb_typeof(p_choices) is distinct from 'object'
    or octet_length(p_choices::text)>1000
    or (p_choices - array['prepared', 'evaluation', 'topics']) <> '{}'::jsonb then
   raise exception 'Invalid ballot response' using errcode = '22023';
 end if;
 select * into item from hdg_community_private.ballots
   where id = p_token and not closed and expires_at > now() for share;
 if not found then
   raise exception 'Voting is closed or this link is invalid' using errcode = '22023';
 end if;
 foreach category in array array['prepared', 'evaluation', 'topics'] loop
   candidate_id := p_choices->>category;
   if jsonb_typeof(p_choices->category) is distinct from 'string' or (candidate_id <> '' and not exists (
     select 1 from jsonb_array_elements(item.choices->category) c where c->>'id' = candidate_id
   )) then
     raise exception 'A choice is missing or is no longer eligible. Refresh the ballot.' using errcode = '22023';
   end if;
 end loop;
 insert into hdg_community_private.votes(ballot_id, browser_id, choices)
 values (item.id, p_browser_id, p_choices) on conflict do nothing;
 return true;
end;
$function$;

revoke execute on function hdg_sync_private.name_key(text), hdg_sync_private.person_name_keys(uuid),
  hdg_sync_private.agenda_name_person(text, text), hdg_sync_private.my_meeting_roles(text),
  public.hdg_my_meeting_access(text), public.hdg_save_meeting(text, date, jsonb, timestamptz),
  public.hdg_meetings_list(text, date, text), public.hdg_manage_ballot(text, text, text, jsonb) from public, anon;
grant execute on function public.hdg_my_meeting_access(text), public.hdg_save_meeting(text, date, jsonb, timestamptz),
  public.hdg_meetings_list(text, date, text), public.hdg_manage_ballot(text, text, text, jsonb) to authenticated;
revoke execute on function public.hdg_open_ballot(uuid), public.hdg_cast_ballot(uuid, uuid, jsonb) from public;
grant execute on function public.hdg_open_ballot(uuid), public.hdg_cast_ballot(uuid, uuid, jsonb) to anon, authenticated;
