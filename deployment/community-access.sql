begin;

create schema hdg_community_private;
revoke all on schema hdg_community_private from public, anon, authenticated;

create table hdg_community_private.beta_members (
 user_id uuid primary key references auth.users(id) on delete cascade
);
alter table hdg_community_private.beta_members enable row level security;

create function public.hdg_access_mode()
returns text language sql stable security definer set search_path = '' as $$
 select coalesce((
   select case
     when exists (select 1 from public.hdg_officer_access a
       where a.user_id = u.id and a.division_code = 'G' and a.active) then 'leader'
     when exists (select 1 from hdg_community_private.beta_members b where b.user_id = u.id) then 'member'
     when exists (
       select 1 from public.hdg_sync_state s
       cross join lateral jsonb_array_elements(s.payload #> '{database,memberships}') as m
       where s.division_code = 'G' and m->>'active' = 'true'
         and coalesce(m->>'pastMember', 'false') <> 'true'
         and lower(btrim(m->>'email')) = lower(btrim(u.email))
     ) then 'member'
     else 'none'
   end
   from auth.users u
   where u.id = auth.uid() and u.email_confirmed_at is not null and btrim(u.email) <> ''
 ), 'none');
$$;

create function public.hdg_member_community()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare snapshot jsonb;
begin
 if public.hdg_access_mode() not in ('member', 'leader') then
   raise exception 'Verified Toastmasters membership required' using errcode = '42501';
 end if;
 select payload->'database' into snapshot from public.hdg_sync_state where division_code = 'G';
 return jsonb_build_object(
   'clubs', coalesce((
     select jsonb_agg(jsonb_build_object('name', c->>'name', 'area', c->>'area',
       'city', c->>'city', 'mode', c->>'mode') order by c->>'name')
     from jsonb_array_elements(snapshot->'clubs') as c
     where nullif(c->>'name', '') is not null
   ), '[]'::jsonb),
   'meetings', coalesce((
     select jsonb_agg(summary order by summary->>'date', summary->>'club')
     from (
       select jsonb_build_object('club', m->>'clubName', 'date', m->>'meetingDate',
         'time', m->>'startTime', 'timezone', m->>'timezone') as summary
       from jsonb_array_elements(snapshot->'meetingAgendaRecords') as m
       where m->>'meetingDate' ~ '^\d{4}-\d{2}-\d{2}$'
         and m->>'meetingDate' >= (now() at time zone 'Asia/Makassar')::date::text
       order by m->>'meetingDate', m->>'clubName' limit 100
     ) upcoming
   ), '[]'::jsonb)
 );
end;
$$;

create table hdg_community_private.ballots (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 meeting_id text not null,
 title text not null,
 choices jsonb not null,
 expires_at timestamptz not null,
 closed boolean not null default false,
 unique (owner_id, meeting_id)
);
create table hdg_community_private.votes (
 ballot_id uuid not null references hdg_community_private.ballots(id) on delete cascade,
 browser_id uuid not null,
 choices jsonb not null,
 primary key (ballot_id, browser_id)
);
alter table hdg_community_private.ballots enable row level security;
alter table hdg_community_private.votes enable row level security;
revoke all on all tables in schema hdg_community_private from public, anon, authenticated;

create function public.hdg_manage_ballot(
 p_meeting_id text, p_action text, p_title text default null, p_choices jsonb default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 item hdg_community_private.ballots%rowtype;
 category text;
 nominees jsonb;
begin
 if public.hdg_access_mode() <> 'leader' then
   raise exception 'Approved leader access required' using errcode = '42501';
 end if;
 if p_meeting_id is null or length(btrim(p_meeting_id)) not between 1 and 200 then
   raise exception 'Select a meeting' using errcode = '22023';
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
   if not exists (
     select 1 from jsonb_each(p_choices) as c where jsonb_array_length(c.value) > 0
   ) then
     raise exception 'Add at least one candidate' using errcode = '22023';
   end if;
   insert into hdg_community_private.ballots(owner_id, meeting_id, title, choices, expires_at)
   values (auth.uid(), p_meeting_id, btrim(p_title), p_choices, now() + interval '24 hours')
   on conflict (owner_id, meeting_id) do update
     set title = excluded.title, choices = excluded.choices, expires_at = excluded.expires_at, closed = false
   returning * into item;
 when 'close' then
   update hdg_community_private.ballots set closed = true
   where owner_id = auth.uid() and meeting_id = p_meeting_id returning * into item;
 when 'status' then
   select * into item from hdg_community_private.ballots
   where owner_id = auth.uid() and meeting_id = p_meeting_id;
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

create function public.hdg_open_ballot(p_token uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('title', b.title, 'choices', b.choices)
 from hdg_community_private.ballots b
 where b.id = p_token and not b.closed and b.expires_at > now()
   and exists (select 1 from public.hdg_officer_access a
     where a.user_id = b.owner_id and a.division_code = 'G' and a.active);
$$;

create function public.hdg_cast_ballot(p_token uuid, p_browser_id uuid, p_choices jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
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
 if not found or not exists (select 1 from public.hdg_officer_access a
     where a.user_id = item.owner_id and a.division_code = 'G' and a.active) then
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
$$;

revoke all on function public.hdg_access_mode(), public.hdg_member_community(),
 public.hdg_manage_ballot(text,text,text,jsonb), public.hdg_open_ballot(uuid),
 public.hdg_cast_ballot(uuid,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.hdg_access_mode(), public.hdg_member_community(),
 public.hdg_manage_ballot(text,text,text,jsonb) to authenticated;
grant execute on function public.hdg_open_ballot(uuid),
 public.hdg_cast_ballot(uuid,uuid,jsonb) to anon, authenticated;

create policy hdg_approved_v632_community_download on storage.objects for select to authenticated
 using (bucket_id = 'hdg-private-app' and name = 'v632-community.html'
        and (select public.hdg_access_mode()) = 'leader');

commit;
