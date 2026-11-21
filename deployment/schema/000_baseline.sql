-- Hello Division G: production database structure as of 20 November 2026 (v645).
-- Structure only, no records. Read from production with catalog queries and applied
-- to the test project (see deployment/schema/README.md). Do not apply to production.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists hdg_private;
create schema if not exists hdg_sync_private;
create schema if not exists hdg_community_private;
revoke all on schema hdg_private, hdg_sync_private, hdg_community_private from public;
grant usage on schema hdg_sync_private to authenticated;

-- Tables
create table public.hdg_sync_state (division_code text not null, revision bigint not null default 1, payload jsonb not null, updated_at timestamp with time zone not null default now(), updated_by uuid);
create table public.hdg_officer_access (user_id uuid not null, division_code text not null default 'G'::text, app_role text not null, active boolean not null default true, approved_at timestamp with time zone not null default now());
create table hdg_community_private.ballots (id uuid not null default gen_random_uuid(), owner_id uuid not null, meeting_id text not null, title text not null, choices jsonb not null, expires_at timestamp with time zone not null, closed boolean not null default false);
create table hdg_community_private.beta_members (user_id uuid not null);
create table hdg_community_private.club_agenda_defaults (club_number text not null, settings jsonb not null);
create table hdg_community_private.votes (ballot_id uuid not null, browser_id uuid not null, choices jsonb not null);
create table hdg_private.web_imports (id uuid not null default gen_random_uuid(), source_sha256 text not null, exported_at timestamp with time zone not null, imported_at timestamp with time zone not null default now(), source_text text not null, payload jsonb not null);
create table hdg_private.import_chunks (source_sha256 text not null, "position" integer not null, chunk_text text not null);
create table hdg_private.import_collections (import_id uuid not null, collection text not null, value jsonb not null);
create table hdg_sync_private.initial_administrators (email text not null, created_at timestamp with time zone not null default now());
create table hdg_sync_private.revision_history (revision bigint not null, payload jsonb not null, updated_at timestamp with time zone not null, updated_by uuid);
create table hdg_sync_private.save_receipts (request_id uuid not null, actor uuid not null, base_revision bigint not null, payload_hash text not null, result_revision bigint not null, created_at timestamp with time zone not null default now());

-- Constraints
alter table hdg_community_private.ballots add constraint ballots_pkey PRIMARY KEY (id);
alter table hdg_community_private.ballots add constraint ballots_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table hdg_community_private.ballots add constraint ballots_owner_id_meeting_id_key UNIQUE (owner_id, meeting_id);
alter table hdg_community_private.beta_members add constraint beta_members_pkey PRIMARY KEY (user_id);
alter table hdg_community_private.beta_members add constraint beta_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table hdg_community_private.club_agenda_defaults add constraint club_agenda_defaults_settings_check CHECK ((jsonb_typeof(settings) = 'object'::text));
alter table hdg_community_private.club_agenda_defaults add constraint club_agenda_defaults_club_number_check CHECK ((club_number ~ '^[1-9][0-9]*$'::text));
alter table hdg_community_private.club_agenda_defaults add constraint club_agenda_defaults_pkey PRIMARY KEY (club_number);
alter table hdg_community_private.votes add constraint votes_ballot_id_fkey FOREIGN KEY (ballot_id) REFERENCES hdg_community_private.ballots(id) ON DELETE CASCADE;
alter table hdg_community_private.votes add constraint votes_pkey PRIMARY KEY (ballot_id, browser_id);
alter table public.hdg_officer_access add constraint hdg_officer_access_pkey PRIMARY KEY (user_id, division_code);
alter table public.hdg_officer_access add constraint hdg_officer_access_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.hdg_officer_access add constraint hdg_officer_access_app_role_check CHECK ((app_role = ANY (ARRAY['administrator'::text, 'officer'::text])));
alter table hdg_private.import_chunks add constraint import_chunks_position_check CHECK (("position" >= 0));
alter table hdg_private.import_chunks add constraint import_chunks_pkey PRIMARY KEY (source_sha256, "position");
alter table hdg_private.web_imports add constraint web_imports_pkey PRIMARY KEY (id);
alter table hdg_private.web_imports add constraint web_imports_payload_check CHECK (((payload ->> 'format'::text) = 'hello-division-dashboard'::text));
alter table hdg_private.web_imports add constraint web_imports_check CHECK ((encode(sha256(convert_to(source_text, 'UTF8'::name)), 'hex'::text) = source_sha256));
alter table hdg_private.web_imports add constraint web_imports_check1 CHECK ((payload = (source_text)::jsonb));
alter table hdg_private.web_imports add constraint web_imports_source_sha256_key UNIQUE (source_sha256);
alter table hdg_private.web_imports add constraint web_imports_source_sha256_check CHECK ((source_sha256 ~ '^[0-9a-f]{64}$'::text));
alter table hdg_private.web_imports add constraint web_imports_payload_check1 CHECK ((jsonb_typeof((payload #> '{data,database}'::text[])) = 'object'::text));
alter table hdg_private.import_collections add constraint import_collections_pkey PRIMARY KEY (import_id, collection);
alter table hdg_private.import_collections add constraint import_collections_import_id_fkey FOREIGN KEY (import_id) REFERENCES hdg_private.web_imports(id);
alter table hdg_sync_private.initial_administrators add constraint initial_administrators_pkey PRIMARY KEY (email);
alter table hdg_sync_private.initial_administrators add constraint initial_administrators_email_check CHECK ((email = lower(email)));
alter table hdg_sync_private.revision_history add constraint revision_history_pkey PRIMARY KEY (revision);
alter table hdg_sync_private.revision_history add constraint revision_history_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
alter table hdg_sync_private.save_receipts add constraint save_receipts_pkey PRIMARY KEY (request_id);
alter table hdg_sync_private.save_receipts add constraint save_receipts_actor_fkey FOREIGN KEY (actor) REFERENCES auth.users(id);
alter table public.hdg_sync_state add constraint hdg_sync_state_pkey PRIMARY KEY (division_code);
alter table public.hdg_sync_state add constraint hdg_sync_state_payload_check CHECK ((jsonb_typeof((payload -> 'database'::text)) = 'object'::text));
alter table public.hdg_sync_state add constraint hdg_sync_state_division_code_check CHECK ((division_code = 'G'::text));
alter table public.hdg_sync_state add constraint hdg_sync_state_revision_check CHECK ((revision > 0));
alter table public.hdg_sync_state add constraint hdg_sync_state_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);

-- Functions
CREATE OR REPLACE FUNCTION hdg_sync_private.bootstrap_verified_administrator()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
begin
 if new.email_confirmed_at is not null and exists(
   select 1 from hdg_sync_private.initial_administrators a where a.email=lower(new.email)
 ) then
   insert into public.hdg_officer_access(user_id,division_code,app_role,active)
   values(new.id,'G','administrator',true) on conflict(user_id,division_code) do nothing;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.hdg_access_mode()
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.hdg_cast_ballot(p_token uuid, p_browser_id uuid, p_choices jsonb)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.hdg_manage_ballot(p_meeting_id text, p_action text, p_title text DEFAULT NULL::text, p_choices jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION hdg_sync_private.manage_officer(p_email text, p_active boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare target_id uuid; actor_id uuid:=auth.uid();
begin
 if actor_id is null or not exists(select 1 from public.hdg_officer_access where user_id=actor_id and division_code='G' and app_role='administrator' and active) then
  raise exception 'Administrator approval required' using errcode='42501';
 end if;
 if p_email is null or p_active is null then raise exception 'Email and approval state required' using errcode='22023'; end if;
 select id into target_id from auth.users where lower(email)=lower(btrim(p_email)) and email_confirmed_at is not null;
 if target_id is null then raise exception 'This officer must create and confirm their login first' using errcode='22023'; end if;
 if exists(select 1 from public.hdg_officer_access where user_id=target_id and division_code='G' and app_role='administrator') then
  raise exception 'Administrator access cannot be changed through officer approval' using errcode='42501';
 end if;
 insert into public.hdg_officer_access(user_id,division_code,app_role,active)
 values(target_id,'G','officer',p_active)
 on conflict(user_id,division_code) do update set active=excluded.active,approved_at=now();
 return jsonb_build_object('email',lower(btrim(p_email)),'active',p_active);
end $function$;

CREATE OR REPLACE FUNCTION public.hdg_manage_officer(p_email text, p_active boolean)
 RETURNS jsonb LANGUAGE sql SET search_path TO ''
AS $function$select hdg_sync_private.manage_officer(p_email,p_active);$function$;

CREATE OR REPLACE FUNCTION public.hdg_open_ballot(p_token uuid)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 select jsonb_build_object('title', b.title, 'choices', b.choices)
 from hdg_community_private.ballots b
 where b.id = p_token and not b.closed and b.expires_at > now()
   and exists (select 1 from public.hdg_officer_access a
     where a.user_id = b.owner_id and a.division_code = 'G' and a.active);
$function$;

CREATE OR REPLACE FUNCTION hdg_sync_private.save_web_state(p_expected_revision bigint, p_payload jsonb, p_request_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare
 current_row public.hdg_sync_state%rowtype;
 receipt hdg_sync_private.save_receipts%rowtype;
 actor_id uuid := auth.uid();
 content_hash text;
begin
 if actor_id is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select * into current_row from public.hdg_sync_state where division_code='G' for update;
 if not found then raise exception 'Shared database not initialized'; end if;
 if not exists(select 1 from public.hdg_officer_access where user_id=actor_id and division_code='G' and active) then
   raise exception 'Officer approval required' using errcode='42501';
 end if;
 if p_request_id is null or p_expected_revision is null or p_payload is null then raise exception 'Missing save parameters' using errcode='22023'; end if;
 if jsonb_typeof(p_payload) is distinct from 'object'
 or jsonb_typeof(p_payload->'database') is distinct from 'object'
 or jsonb_typeof(p_payload->'settings') is distinct from 'object'
 or p_payload ? 'ui'
 or p_payload #>> '{database,schemaVersion}' is distinct from '4' then
   raise exception 'Invalid shared payload' using errcode='22023';
 end if;
 if exists(select 1 from unnest(array['areas','clubs','memberships','exco','reports','tlis','contests','prospects','membershipImports','officerImports','tasks','taskDismissals','specialMeetings','meetingAgendaRecords','leadershipTeams']) k where jsonb_typeof(p_payload->'database'->k) is distinct from 'array') then
   raise exception 'Missing or invalid database collections' using errcode='22023';
 end if;
 if jsonb_array_length(p_payload #> '{database,clubs}')=0 or jsonb_array_length(p_payload #> '{database,memberships}')=0 then
   raise exception 'Empty database replacement blocked' using errcode='22023';
 end if;
 content_hash := encode(sha256(convert_to(p_payload::text,'UTF8')),'hex');
 select * into receipt from hdg_sync_private.save_receipts where request_id=p_request_id;
 if found then
   if receipt.actor<>actor_id or receipt.base_revision<>p_expected_revision or receipt.payload_hash<>content_hash then
     raise exception 'Save request reused with different content' using errcode='22023';
   end if;
   return jsonb_build_object('revision',receipt.result_revision,'duplicate',true);
 end if;
 if current_row.revision<>p_expected_revision then
   raise exception 'A newer web revision exists. Keep local edits and reload the shared version.' using errcode='40001';
 end if;
 if exists(select 1 from jsonb_object_keys(current_row.payload->'database') k where not ((p_payload->'database') ? k)) then
   raise exception 'Save would discard existing database fields' using errcode='22023';
 end if;
 insert into hdg_sync_private.revision_history(revision,payload,updated_at,updated_by)
 values(current_row.revision,current_row.payload,current_row.updated_at,current_row.updated_by);
 update public.hdg_sync_state set payload=p_payload,revision=revision+1,updated_at=now(),updated_by=actor_id where division_code='G' returning * into current_row;
 insert into hdg_sync_private.save_receipts(request_id,actor,base_revision,payload_hash,result_revision)
 values(p_request_id,actor_id,p_expected_revision,content_hash,current_row.revision);
 return jsonb_build_object('revision',current_row.revision,'duplicate',false);
end $function$;

CREATE OR REPLACE FUNCTION public.hdg_save_web_state(p_expected_revision bigint, p_payload jsonb, p_request_id uuid)
 RETURNS jsonb LANGUAGE sql SET search_path TO ''
AS $function$ select hdg_sync_private.save_web_state(p_expected_revision,p_payload,p_request_id); $function$;

-- hdg_member_community() is long; it lives in 001_member_community.sql.

-- Views
create view hdg_private.web_areas as SELECT c.import_id, r.ordinality AS source_position, (r.value ->> 'code'::text) AS area_code, r.value AS source_record
 FROM (hdg_private.import_collections c CROSS JOIN LATERAL jsonb_array_elements(c.value) WITH ORDINALITY r(value, ordinality)) WHERE (c.collection = 'areas'::text);
create view hdg_private.web_clubs as SELECT c.import_id, r.ordinality AS source_position, (r.value ->> 'number'::text) AS club_number, (r.value ->> 'area'::text) AS area_code, r.value AS source_record
 FROM (hdg_private.import_collections c CROSS JOIN LATERAL jsonb_array_elements(c.value) WITH ORDINALITY r(value, ordinality)) WHERE (c.collection = 'clubs'::text);
create view hdg_private.web_memberships as SELECT c.import_id, r.ordinality AS source_position, (r.value ->> 'memberId'::text) AS member_id, (r.value ->> 'clubNumber'::text) AS club_number, (r.value ->> 'key'::text) AS source_key, r.value AS source_record
 FROM (hdg_private.import_collections c CROSS JOIN LATERAL jsonb_array_elements(c.value) WITH ORDINALITY r(value, ordinality)) WHERE (c.collection = 'memberships'::text);
create view hdg_private.web_officer_assignments as SELECT c.import_id, r.ordinality AS source_position, (r.value ->> 'memberId'::text) AS member_id, (r.value ->> 'clubNumber'::text) AS club_number, (r.value ->> 'role'::text) AS officer_role, r.value AS source_record
 FROM (hdg_private.import_collections c CROSS JOIN LATERAL jsonb_array_elements(c.value) WITH ORDINALITY r(value, ordinality)) WHERE (c.collection = 'exco'::text);

-- Row-level security and policies
alter table hdg_community_private.ballots enable row level security;
alter table hdg_community_private.beta_members enable row level security;
alter table hdg_community_private.club_agenda_defaults enable row level security;
alter table hdg_community_private.votes enable row level security;
alter table public.hdg_officer_access enable row level security;
alter table hdg_private.import_chunks enable row level security;
alter table hdg_private.import_collections enable row level security;
alter table hdg_private.web_imports enable row level security;
alter table hdg_sync_private.initial_administrators enable row level security;
alter table hdg_sync_private.revision_history enable row level security;
alter table hdg_sync_private.save_receipts enable row level security;
alter table public.hdg_sync_state enable row level security;
create policy hdg_approved_read on public.hdg_sync_state as PERMISSIVE for SELECT to authenticated using ((EXISTS ( SELECT 1 FROM public.hdg_officer_access a WHERE ((a.user_id = ( SELECT auth.uid() AS uid)) AND (a.division_code = hdg_sync_state.division_code) AND a.active))));
create policy hdg_read_own_approval on public.hdg_officer_access as PERMISSIVE for SELECT to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) AND active));

-- Grants (match production: Supabase gives new public tables and functions broad defaults)
revoke all on public.hdg_sync_state, public.hdg_officer_access from anon, authenticated;
grant select on public.hdg_sync_state, public.hdg_officer_access to authenticated;
revoke all on all tables in schema hdg_private, hdg_sync_private, hdg_community_private from anon, authenticated;
revoke execute on all functions in schema public, hdg_private, hdg_sync_private, hdg_community_private from public, anon, authenticated;
grant execute on function public.hdg_access_mode(), public.hdg_manage_ballot(text,text,text,jsonb), public.hdg_manage_officer(text,boolean), public.hdg_save_web_state(bigint,jsonb,uuid) to authenticated;
grant execute on function public.hdg_cast_ballot(uuid,uuid,jsonb), public.hdg_open_ballot(uuid) to anon, authenticated;
grant execute on function hdg_sync_private.manage_officer(text,boolean), hdg_sync_private.save_web_state(bigint,jsonb,uuid) to authenticated;

-- Auth trigger
create trigger hdg_bootstrap_verified_admin after insert or update of email_confirmed_at on auth.users for each row execute function hdg_sync_private.bootstrap_verified_administrator();

-- Private app bucket (files are uploaded separately; per-file policies follow deployment/storage-policy-vNNN.sql)
insert into storage.buckets (id, name, public) values ('hdg-private-app', 'hdg-private-app', false) on conflict (id) do nothing;
