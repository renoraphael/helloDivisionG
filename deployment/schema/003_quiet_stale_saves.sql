-- 003: a save based on an older revision is set aside quietly instead of failing or hanging.
-- Found 20 November 2026 in the test project: hdg_sync_private.save_web_state raised SQLSTATE 40001
-- (serialization_failure) for "a newer web revision exists". PostgREST retries 40001 automatically, so the
-- refusal never reached the app: the request hung and the database kept re-running it.
-- Owner decision, 21 November 2026 (project/DISTRICT_PLAN.md rule 33): do not show an error. The newer
-- shared data is kept, the late save is stored in hdg_sync_private.superseded_saves so the maintainer can
-- recover it, and the function answers like a normal save with the revision the app already has.
-- docs/cloud-sync.js then sees on its next 30-second check that the shared revision is newer and loads it,
-- so the screen quietly shows the newer data. The live launcher needs no change.
create table if not exists hdg_sync_private.superseded_saves (
 request_id uuid primary key,
 at timestamptz not null default now(),
 actor uuid not null,
 base_revision bigint not null,
 current_revision bigint not null,
 payload jsonb not null,
 recovered_at timestamptz);
alter table hdg_sync_private.superseded_saves enable row level security;
revoke all on hdg_sync_private.superseded_saves from public, anon, authenticated;

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
   insert into hdg_sync_private.superseded_saves(request_id,actor,base_revision,current_revision,payload)
   values(p_request_id,actor_id,p_expected_revision,current_row.revision,p_payload) on conflict (request_id) do nothing;
   return jsonb_build_object('revision',p_expected_revision,'duplicate',false,'superseded',true,'latest_revision',current_row.revision);
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
