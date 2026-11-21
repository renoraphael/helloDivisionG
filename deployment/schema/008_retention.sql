-- 008: automatic clean-up of full copies of the shared Division G record (owner decision, 21 November 2026).
-- Each copy is the whole record (about 2.6 MB, with member names and emails). Kept forever, the revision history
-- would reach the free plan's 500 MB limit after about 160 more saves, and keeping member data longer than
-- needed goes against rule 4 (PDPA retention).
--  * Late saves set aside by 003 (hdg_sync_private.superseded_saves): deleted after 7 days.
--  * Previous versions (hdg_sync_private.revision_history): only the last 10 saves are kept. The owner does not need
--    old data: a copy is only kept to recover from a mistaken save (a bad import or a deleted club), and after the
--    switch to the per-record tables full copies are no longer needed at all.
-- The clean-up runs inside each save, so no scheduled job is needed. Only these two deletes are new; the save
-- logic is identical to 003.
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
   delete from hdg_sync_private.superseded_saves where at < now() - interval '7 days';
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
 -- Retention (owner decision, 21 November 2026): late copies 7 days, previous versions: the last 10 saves.
 delete from hdg_sync_private.superseded_saves where at < now() - interval '7 days';
 delete from hdg_sync_private.revision_history where revision < (
   select min(k.revision) from (select h.revision from hdg_sync_private.revision_history h order by h.revision desc limit 10) k);
 return jsonb_build_object('revision',current_row.revision,'duplicate',false);
end $function$;
