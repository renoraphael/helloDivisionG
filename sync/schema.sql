begin;
create schema if not exists hdg_sync_private;
revoke all on schema hdg_sync_private from public,anon,authenticated;

create table if not exists public.hdg_sync_state (
 division_code text primary key check(division_code='G'),
 revision bigint not null default 1 check(revision > 0),
 payload jsonb not null check(jsonb_typeof(payload->'database')='object'),
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id)
);
alter table public.hdg_sync_state enable row level security;
revoke all on public.hdg_sync_state from public,anon,authenticated;
grant select on public.hdg_sync_state to authenticated;

create table if not exists hdg_sync_private.save_receipts (
 request_id uuid primary key,
 actor uuid not null references auth.users(id),
 base_revision bigint not null,
 payload_hash text not null,
 result_revision bigint not null,
 created_at timestamptz not null default now()
);
alter table hdg_sync_private.save_receipts enable row level security;
revoke all on hdg_sync_private.save_receipts from public,anon,authenticated;

create table if not exists hdg_sync_private.revision_history (
 revision bigint primary key,
 payload jsonb not null,
 updated_at timestamptz not null,
 updated_by uuid references auth.users(id)
);
alter table hdg_sync_private.revision_history enable row level security;
revoke all on hdg_sync_private.revision_history from public,anon,authenticated;

create table if not exists hdg_sync_private.initial_administrators (
 email text primary key check(email=lower(email)),
 created_at timestamptz not null default now()
);
alter table hdg_sync_private.initial_administrators enable row level security;
revoke all on hdg_sync_private.initial_administrators from public,anon,authenticated;

alter table public.hdg_officer_access enable row level security;
revoke all on public.hdg_officer_access from public,anon,authenticated;
grant select on public.hdg_officer_access to authenticated;
create policy hdg_read_own_approval on public.hdg_officer_access for select to authenticated
 using(user_id=(select auth.uid()) and active);
create policy hdg_approved_read on public.hdg_sync_state for select to authenticated
 using(exists(select 1 from public.hdg_officer_access a where a.user_id=(select auth.uid()) and a.division_code=hdg_sync_state.division_code and a.active));

-- Only verified, explicitly preapproved administrator emails can bootstrap access.
create or replace function hdg_sync_private.bootstrap_verified_administrator()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.email_confirmed_at is not null and exists(
   select 1 from hdg_sync_private.initial_administrators a where a.email=lower(new.email)
 ) then
   insert into public.hdg_officer_access(user_id,division_code,app_role,active)
   values(new.id,'G','administrator',true) on conflict(user_id,division_code) do nothing;
 end if;
 return new;
end $$;
revoke all on function hdg_sync_private.bootstrap_verified_administrator() from public,anon,authenticated;
create trigger hdg_bootstrap_verified_admin after insert or update of email_confirmed_at on auth.users
for each row execute function hdg_sync_private.bootstrap_verified_administrator();

create or replace function hdg_sync_private.save_web_state(p_expected_revision bigint,p_payload jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
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
end $$;
revoke all on function hdg_sync_private.save_web_state(bigint,jsonb,uuid) from public,anon,authenticated;
grant usage on schema hdg_sync_private to authenticated;
grant execute on function hdg_sync_private.save_web_state(bigint,jsonb,uuid) to authenticated;
create or replace function public.hdg_save_web_state(p_expected_revision bigint,p_payload jsonb,p_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select hdg_sync_private.save_web_state(p_expected_revision,p_payload,p_request_id);
$$;
revoke all on function public.hdg_save_web_state(bigint,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.hdg_save_web_state(bigint,jsonb,uuid) to authenticated;

-- The web backup is authoritative. Never initialize from a phone or client cache.
insert into public.hdg_sync_state(division_code,payload)
select 'G',(payload->'data')-'ui' from hdg_private.web_imports
where source_sha256='90bf35145f1765bdf6da9c9a431ff16574bb04fc574501507b7a5fc18a16d88c'
on conflict(division_code) do nothing;
commit;
select division_code,revision,jsonb_array_length(payload #> '{database,memberships}') as memberships from public.hdg_sync_state;
