-- Run in the synthetic project after setup_test_project.py. Everything rolls back.
begin;
do $$
declare
 fixture_admin uuid;
 fixture_officer uuid;
 original public.hdg_sync_state;
 hold jsonb;
 write_result jsonb;
 change jsonb;
 patch text[];
 attempts int := 0;
begin
 select id into strict fixture_admin from auth.users where email='hdg-admin@example.com';
 select id into strict fixture_officer from auth.users where email='hdg-officer@example.com';
 select * into strict original from public.hdg_sync_state where division_code='G';
 if has_function_privilege('anon','public.hdg_set_leader_save_pause(boolean)','EXECUTE')
    or has_table_privilege('authenticated','hdg_sync_private.leader_cutover','SELECT,UPDATE') then
  raise exception 'Unexpected routing permission';
 end if;
 perform set_config('request.jwt.claim.sub',fixture_officer::text,true);
 begin
  perform public.hdg_set_leader_save_pause(true);
  raise exception 'Officer could change routing';
 exception when insufficient_privilege then null;
 end;
 perform set_config('request.jwt.claim.sub',fixture_admin::text,true);
 hold := public.hdg_set_leader_save_pause(true);
 if (hold->>'revision')::bigint<>original.revision
    or (hold->>'pauseUntil')::timestamptz not between clock_timestamp()+interval '4 minutes 59 seconds'
                                                  and clock_timestamp()+interval '5 minutes' then
  raise exception 'Unsafe pause window';
 end if;
 if public.hdg_set_leader_save_pause(true) is distinct from hold then
  raise exception 'Retry extended the pause';
 end if;
 perform set_config('request.jwt.claim.sub',fixture_officer::text,true);
 foreach patch slice 1 in array array[
  ['database','tlis'],['database','contests'],['database','reports'],['database','tasks'],['database','taskDismissals']
 ] loop
  change := jsonb_set(original.payload,patch,coalesce(original.payload #> patch,'[]')||'{"id":"synthetic-cutover"}'::jsonb);
  begin
   perform public.hdg_save_web_state(original.revision,change,gen_random_uuid());
   raise exception 'A migrated legacy edit crossed the pause';
  exception when sqlstate 'PT503' then attempts := attempts+1;
  end;
 end loop;
 foreach patch slice 1 in array array[
  ['database','clubs','0','dcpGoals'],['database','exco','0','tli1']
 ] loop
  change := jsonb_set(original.payload,patch,'true'::jsonb);
  if change is not distinct from original.payload then raise exception 'Synthetic fixture did not change'; end if;
  begin
   perform public.hdg_save_web_state(original.revision,change,gen_random_uuid());
   raise exception 'A migrated field crossed the pause';
  exception when sqlstate 'PT503' then attempts := attempts+1;
  end;
 end loop;
 if attempts<>7 or (select revision from public.hdg_sync_state where division_code='G')<>original.revision then
  raise exception 'A paused save changed the shared revision';
 end if;
 change := jsonb_set(original.payload,'{database,clubs,0,city}','"Fictional scenario"');
 write_result := public.hdg_save_web_state(original.revision,change,gen_random_uuid());
 if (write_result->>'revision')::bigint<>original.revision+1 then raise exception 'Ordinary club save was paused'; end if;
 change := jsonb_set(change,'{database,meetingAgendaRecords}',
   coalesce(change #> '{database,meetingAgendaRecords}','[]')||'{"id":"synthetic-agenda"}'::jsonb);
 write_result := public.hdg_save_web_state(original.revision+1,change,gen_random_uuid());
 if (write_result->>'revision')::bigint<>original.revision+2 then raise exception 'Agenda save was paused'; end if;
 -- Simulate the deadline passing without relying on wall-clock timing.
 update hdg_sync_private.leader_cutover set pause_until=clock_timestamp()-interval '1 second';
 change := jsonb_set(change,'{database,tlis}',coalesce(change #> '{database,tlis}','[]')||'{"id":"synthetic-session"}');
 write_result := public.hdg_save_web_state(original.revision+2,change,gen_random_uuid());
 if (write_result->>'revision')::bigint<>original.revision+3 then raise exception 'Deadline did not restore leader saves'; end if;
 perform set_config('request.jwt.claim.sub',fixture_admin::text,true);
 perform public.hdg_set_leader_save_pause(true);
 if public.hdg_set_leader_save_pause(false)->>'pauseUntil' is not null then raise exception 'Resume did not clear pause'; end if;
end $$;
do $$
declare
 old_event public.hdg_leader_records;
 new_event public.hdg_leader_records;
 original jsonb := '{"id":"fixture","name":"First title","date":"2026-10-20","status":"Planned","notes":"Fictional original note"}';
 projected jsonb;
begin
 old_event.id := gen_random_uuid();
 old_event.kind := 'tli_session';
 old_event.year_start := 2026;
 old_event.division_code := 'G';
 old_event.area_codes := array['G1','G2'];
 old_event.title := 'First title';
 old_event.occurred_on := '2026-10-20';
 old_event.details := '{"status":"Planned"}';
 new_event := old_event;
 new_event.title := 'Second title';
 new_event.occurred_on := '2026-11-20';
 new_event.details := '{"status":"Completed","attendance":12}';
 projected := hdg_sync_private.leader_event_fallback(original,old_event,new_event);
 if projected is distinct from '{"id":"fixture","name":"Second title","date":"2026-11-20","attendance":12,"status":"Completed","notes":"Fictional original note"}'::jsonb
    or projected is distinct from hdg_sync_private.leader_event_fallback(projected,old_event,new_event) then
  raise exception 'Fallback projection did not preserve earlier fields or retry safely';
 end if;
 begin
  perform hdg_sync_private.leader_event_fallback(original||'{"status":"Changed elsewhere"}',old_event,new_event);
  raise exception 'Fallback overwrote an independent update';
 exception when serialization_failure then null;
 end;
 new_event.details := new_event.details||'{"notes":"Unknown field"}';
 begin
  perform hdg_sync_private.leader_event_fallback(original,old_event,new_event);
  raise exception 'Fallback projected unsupported notes';
 exception when invalid_parameter_value then null;
 end;
end $$;
do $$
declare
 fixture_admin uuid;
 state public.hdg_sync_state;
 event public.hdg_leader_records;
 source jsonb;
 answer jsonb;
 request_id uuid := gen_random_uuid();
 edits jsonb := '{"$title":{"before":"First title","after":"A late title"},"registered":{"before":null,"after":18}}';
begin
 select id into strict fixture_admin from auth.users where email='hdg-admin@example.com';
 perform set_config('request.jwt.claim.sub',fixture_admin::text,true);
 select * into strict state from public.hdg_sync_state where division_code='G';
 source := jsonb_set(state.payload,'{database,tlis}',coalesce(state.payload #> '{database,tlis}','[]')||
   '{"id":"fallback-fixture","name":"First title","date":"2026-10-20","notes":"Fictional private review field"}'::jsonb);
 perform public.hdg_save_web_state(state.revision,source,gen_random_uuid());
 insert into public.hdg_leader_records(kind,year_start,division_code,area_codes,title,occurred_on)
 values('tli_session',2026,'G',array['G1','G2'],'First title','2026-10-20') returning * into event;
 insert into hdg_sync_private.leader_event_links values(event.id,'tlis','fallback-fixture');
 update hdg_sync_private.leader_cutover set record_writes=true,private_tasks_enabled=true;
 if public.hdg_leader_cutover_status()->>'store' is distinct from 'records' then
  raise exception 'Active record route was not reported to the client';
 end if;
 answer:=public.hdg_save_leader_record('tli_session',event.id,2026,'G',null,null,
   'New title','2026-10-20','{"attendance":12}',event.updated_at);
 if not (answer->>'applied')::boolean or not exists(select 1 from public.hdg_leader_records where id=event.id and title='New title') then
  raise exception 'Per-record save was not acknowledged';
 end if;
 select * into strict state from public.hdg_sync_state where division_code='G';
 if not exists(select 1 from jsonb_array_elements(state.payload #> '{database,tlis}') row
  where row @> '{"id":"fallback-fixture","name":"New title","attendance":12,"notes":"Fictional private review field"}') then
  raise exception 'Acknowledged edit is absent from fallback';
 end if;
 begin
  perform public.hdg_save_web_state(state.revision,source,gen_random_uuid());
  raise exception 'Old client bypassed the per-record route';
 exception when sqlstate 'PT409' then null;
 end;
 answer := public.hdg_save_leader_record('tli_session',event.id,2026,'G',null,null,
   'Outdated duplicate','2026-10-20','{}',event.updated_at);
 if (answer->>'applied')::boolean then raise exception 'Stale edit replaced the new value'; end if;
 select * into strict event from public.hdg_leader_records where id=event.id;
 begin
  perform public.hdg_save_leader_record('tli_session',event.id,2026,'G',null,null,
   'Unsupported edit','2026-10-20','{"reviewBlob":"Fixture"}',event.updated_at);
  raise exception 'Unsupported change was acknowledged';
 exception when invalid_parameter_value then null;
 end;
 if (select revision from public.hdg_sync_state where division_code='G')<>state.revision
    or not exists(select 1 from public.hdg_leader_records where id=event.id and title='New title') then
  raise exception 'Failed mirror changed a record or fallback';
 end if;
 answer:=public.hdg_patch_leader_event(event.id,edits,request_id);
 if not (answer->>'applied')::boolean or answer #>> '{record,title}'<>'New title'
    or answer #>> '{record,details,registered}'<>'18' then
  raise exception 'Independent edits from a stale view did not merge';
 end if;
 select * into strict state from public.hdg_sync_state where division_code='G';
 answer:=public.hdg_patch_leader_event(event.id,edits,request_id);
 if not (answer->>'applied')::boolean or (select revision from public.hdg_sync_state where division_code='G')<>state.revision
    or (select count(*) from hdg_sync_private.superseded_edits where row_key=event.id::text)<>1 then
  raise exception 'Retry duplicated the mirror or the set-aside field';
 end if;
 if has_function_privilege('anon','public.hdg_patch_leader_event(uuid,jsonb,uuid)','EXECUTE')
    or has_table_privilege('authenticated','hdg_sync_private.leader_save_receipts','SELECT,UPDATE') then
  raise exception 'Unexpected event write permission';
 end if;
 answer:=public.hdg_return_leader_to_shared();
 if answer->>'store' is distinct from 'shared'
    or public.hdg_leader_cutover_status()->>'store' is distinct from 'shared' then
  raise exception 'One-step fallback did not restore the shared route';
 end if;
 if not exists(select 1 from public.hdg_sync_state s,
  lateral jsonb_array_elements(s.payload #> '{database,tlis}') row
  where s.division_code='G' and row @> '{"id":"fallback-fixture","name":"New title","attendance":12,"registered":18}') then
  raise exception 'Fallback lost an acknowledged edit';
 end if;
 select * into strict state from public.hdg_sync_state where division_code='G';
 begin
  perform public.hdg_save_web_state(state.revision,
    jsonb_set(state.payload,'{database,tasks}',(state.payload #> '{database,tasks}')||'{"id":"fictional-shared-task"}'),
    gen_random_uuid());
  raise exception 'Old client could export a private task into the shared record after fallback';
 exception when sqlstate 'PT409' then null;
 end;
 answer:=public.hdg_save_personal_task(null,'G',2026,null,'Fictional private task','',null,false,null);
 if not (answer->>'applied')::boolean or
    (select revision from public.hdg_sync_state where division_code='G')<>state.revision then
  raise exception 'Fallback disturbed owner-only task storage';
 end if;
end $$;
rollback;
select 'Synthetic pause, scope, resume, expiry, atomic mirror and fallback checks passed.';
