-- Division G cutover pause control. The shared record stays authoritative until the
-- per-record client and compatibility mirror have both passed the release rehearsal.
begin;

create table hdg_sync_private.leader_cutover (
 singleton boolean primary key default true check (singleton),
 pause_until timestamptz,
 record_writes boolean not null default false,
 private_tasks_enabled boolean not null default false,
 check (not record_writes or private_tasks_enabled)
);
insert into hdg_sync_private.leader_cutover default values;
alter table hdg_sync_private.leader_cutover enable row level security;
revoke all on hdg_sync_private.leader_cutover from public,anon,authenticated,service_role;

create table hdg_sync_private.leader_event_links (
 record_id uuid primary key references public.hdg_leader_records,
 collection text not null check(collection in ('tlis','contests','reports')),
 legacy_id text not null check(length(legacy_id) between 1 and 200),
 unique(collection,legacy_id)
);
create table hdg_sync_private.leader_mirror_writes (
 transaction_id xid8 primary key,
 payload_digest bytea not null
);
create table hdg_sync_private.leader_save_receipts (
 request_id uuid primary key,
 actor uuid not null references auth.users on delete cascade,
 request_digest bytea not null,
 applied boolean not null,
 at timestamptz not null default clock_timestamp()
);
alter table hdg_sync_private.leader_event_links enable row level security;
alter table hdg_sync_private.leader_mirror_writes enable row level security;
alter table hdg_sync_private.leader_save_receipts enable row level security;
revoke all on hdg_sync_private.leader_event_links,hdg_sync_private.leader_mirror_writes,
 hdg_sync_private.leader_save_receipts from public,anon,authenticated,service_role;

-- Compare only migrated values. Edits to posters, agendas, club directory details
-- and non-training officer data can still use the shared save path during the pause.
create function hdg_sync_private.leader_legacy_projection(p_db jsonb) returns jsonb
language sql immutable set search_path to '' as $$
 select jsonb_build_object(
  'tlis',p_db->'tlis','contests',p_db->'contests','reports',p_db->'reports',
  'tasks',p_db->'tasks','taskDismissals',p_db->'taskDismissals',
  'rounds',(select coalesce(jsonb_agg(entry order by entry),'[]') from (
   select jsonb_build_array(o->'id',o->'clubNumber',o->'memberId',o->'term',o->'tli1',o->'tli2') entry
   from jsonb_array_elements(coalesce(p_db->'exco','[]')) o
   where jsonb_typeof(o->'tli1')='boolean' or jsonb_typeof(o->'tli2')='boolean') rounds),
  'clubFigures',(select coalesce(jsonb_agg(entry order by entry),'[]') from (
   select jsonb_build_array(c->'number', f.figures) entry
   from jsonb_array_elements(coalesce(p_db->'clubs','[]')) c
   cross join lateral (select jsonb_object_agg(key,value) figures from jsonb_each(c) where key=any(array[
    'members','baseMembers','newMembers','lostMembers','renewedMembers','dcpGoals','educationAwards',
    'officersTrained','cspSubmitted','officerList','adVisitMay2027','adVisitNov2026',
    'adVisitRound1OfficialAsOf','adVisitRound1OfficialSource','guests','attendance','conversions',
    'meetings','duesPaid','renewalApr2027','renewalOct2026','renewalStatus','mar27Override','suspensionRisk'])) f
   where f.figures is not null) clubs))
$$;

create function hdg_sync_private.guard_shared_leader_pause() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if old.payload #> '{database,tasks}' is distinct from new.payload #> '{database,tasks}'
    and exists(select 1 from hdg_sync_private.leader_cutover where private_tasks_enabled) then
  raise sqlstate 'PT409' using message='Use the private task editor to save tasks';
 end if;
 if exists(select 1 from hdg_sync_private.leader_cutover where pause_until>clock_timestamp() or record_writes) then
  if hdg_sync_private.leader_legacy_projection(old.payload->'database') is distinct from
     hdg_sync_private.leader_legacy_projection(new.payload->'database') then
   if exists(select 1 from hdg_sync_private.leader_cutover where pause_until>clock_timestamp()) then
    raise sqlstate 'PT503' using message='Division G leader saves are temporarily paused';
   end if;
   if not exists(select 1 from hdg_sync_private.leader_mirror_writes
      where transaction_id=pg_current_xact_id() and payload_digest=sha256(convert_to(new.payload::text,'UTF8'))) then
    raise sqlstate 'PT409' using message='Reload the app to edit Division G leader records';
   end if;
  end if;
 end if;
 return new;
end $$;

-- The emulator of the old save path runs in the same transaction as the new
-- record update. A failure in either half rolls both halves back.
create function hdg_sync_private.mirror_leader_event() returns trigger
language plpgsql security definer set search_path to '' as $$
declare
 active boolean;
 deadline timestamptz;
 shared public.hdg_sync_state;
 link hdg_sync_private.leader_event_links;
 revised jsonb;
 matches int;
begin
 if new.division_code is distinct from 'G' and old.division_code is distinct from 'G' then
  return coalesce(new,old);
 end if;
 -- An authenticated edit always takes the shared lock before checking routing.
 -- A shadow refresh with no end-user identity can run before record writes begin.
 if auth.uid() is null and not exists(select 1 from hdg_sync_private.leader_cutover where record_writes) then
  return coalesce(new,old);
 end if;
 select * into strict shared from public.hdg_sync_state where division_code='G' for update;
 select record_writes,pause_until into strict active,deadline from hdg_sync_private.leader_cutover;
 if deadline>clock_timestamp() and auth.uid() is not null then
  raise sqlstate 'PT503' using message='Division G leader saves are temporarily paused';
 end if;
 if not active then return coalesce(new,old); end if;
 if tg_op <> 'UPDATE' then
  raise sqlstate 'PT409' using message='This change has no compatible fallback';
 end if;
 select * into link from hdg_sync_private.leader_event_links where record_id=old.id;
 if not found or link.collection is distinct from
   (case old.kind when 'tli_session' then 'tlis' when 'contest' then 'contests' when 'area_visit' then 'reports' end) then
  raise sqlstate 'PT409' using message='This record has no compatible fallback';
 end if;
 select count(*) filter(where item->>'id'=link.legacy_id),
  jsonb_agg(case when item->>'id'=link.legacy_id then hdg_sync_private.leader_event_fallback(item,old,new)
                else item end order by position)
  into matches,revised
  from jsonb_array_elements(shared.payload->'database'->link.collection) with ordinality as items(item,position);
 if matches<>1 then raise sqlstate 'PT409' using message='The fallback requires one matching event'; end if;
 revised := jsonb_set(shared.payload,array['database',link.collection],revised);
 if revised is distinct from shared.payload then
  insert into hdg_sync_private.leader_mirror_writes values (pg_current_xact_id(),sha256(convert_to(revised::text,'UTF8')));
  perform hdg_sync_private.save_web_state(shared.revision,revised,gen_random_uuid());
  delete from hdg_sync_private.leader_mirror_writes where transaction_id=pg_current_xact_id();
 end if;
 return new;
end $$;
create trigger hdg_mirror_leader_event before insert or update or delete on public.hdg_leader_records
 for each row execute function hdg_sync_private.mirror_leader_event();
create trigger hdg_guard_shared_leader_pause before update of payload on public.hdg_sync_state
 for each row when (old.division_code='G' and old.payload is distinct from new.payload)
 execute function hdg_sync_private.guard_shared_leader_pause();

-- Project a supported structured event change back into the existing fallback
-- row, without rewriting its ID, assignments, notes, or archived email.
create function hdg_sync_private.leader_fallback_fields(p_kind text) returns text[]
language sql immutable set search_path to '' as $$
 select case p_kind
  when 'tli_session' then array['attendance','officers','registered','clubs','start','end','timezone',
     'mode','city','island','venue','status','type']
  when 'contest' then array['attendance','categories','contestants','contestantsConfirmed','judgesConfirmed',
     'promoReady','venueConfirmed','start','end','mode','city','island','venue','status','type','targetWindow']
  when 'area_visit' then array['round','reportStartDate','status','summaryScore','meetingObservationScore',
     'clubExperienceScore','clubSupportScore','clubConcernsScore'] end
$$;

create function hdg_sync_private.leader_event_fallback(p_row jsonb,p_before public.hdg_leader_records,
 p_after public.hdg_leader_records) returns jsonb
language plpgsql immutable set search_path to '' as $$
declare
 allowed text[];
 field text;
 projected jsonb := p_row;
begin
 if jsonb_typeof(p_row) is distinct from 'object' or
    (p_before.id,p_before.kind,p_before.year_start,p_before.division_code,p_before.area_code,
     p_before.area_codes,p_before.club_number) is distinct from
    (p_after.id,p_after.kind,p_after.year_start,p_after.division_code,p_after.area_code,
     p_after.area_codes,p_after.club_number) then
  raise exception 'The fallback requires the same event and scope' using errcode='22023';
 end if;
 allowed := hdg_sync_private.leader_fallback_fields(p_after.kind);
 if allowed is null then raise exception 'Unsupported event type' using errcode='22023'; end if;
 if p_before.title is distinct from p_after.title then
  if p_after.kind='area_visit' then raise exception 'A visit uses its existing fallback title' using errcode='22023'; end if;
  field := case p_after.kind when 'tli_session' then 'name' else 'title' end;
  if projected->field is distinct from to_jsonb(p_before.title)
     and projected->field is distinct from to_jsonb(p_after.title) then
   raise exception 'Fallback title changed independently' using errcode='40001';
  end if;
  projected := jsonb_set(projected,array[field],to_jsonb(p_after.title));
 end if;
 if p_before.occurred_on is distinct from p_after.occurred_on then
  if p_after.occurred_on not between make_date(p_after.year_start,7,1) and make_date(p_after.year_start+1,6,30) then
   raise exception 'A date change must stay in the original program year' using errcode='22023';
  end if;
  if projected->'date' is distinct from to_jsonb(p_before.occurred_on)
     and projected->'date' is distinct from to_jsonb(p_after.occurred_on) then
   raise exception 'Fallback date changed independently' using errcode='40001';
  end if;
  projected := jsonb_set(projected,'{date}',to_jsonb(p_after.occurred_on));
 end if;
 for field in select key from jsonb_object_keys(p_before.details||p_after.details) key
              where p_before.details->key is distinct from p_after.details->key loop
  if not field=any(allowed) then raise exception 'A detail has no compatible fallback field' using errcode='22023'; end if;
  if projected->field is distinct from p_before.details->field
     and projected->field is distinct from p_after.details->field then
   raise exception 'Fallback detail changed independently' using errcode='40001';
  end if;
  projected := case when p_after.details ? field
               then jsonb_set(projected,array[field],p_after.details->field)
               else projected-field end;
 end loop;
 return projected;
end $$;

-- Field patches let two editors save independent changes from the same base.
create function public.hdg_patch_leader_event(p_event uuid,p_fields jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
 current_event public.hdg_leader_records;
 revised public.hdg_leader_records;
 receipt hdg_sync_private.leader_save_receipts;
 digest bytea;
 field text;
 patch jsonb;
 current_value jsonb;
 allowed text[];
 late jsonb := '{}';
 did_apply boolean := false;
begin
 if p_request_id is null or jsonb_typeof(p_fields) is distinct from 'object'
    or p_fields='{}' or octet_length(p_fields::text)>100000 then
  raise exception 'Expected a bounded event patch and request ID' using errcode='22023';
 end if;
 select * into current_event from public.hdg_leader_records where id=p_event for update;
 if not found or current_event.division_code<>'G' or not hdg_sync_private.leader_scope('G',current_event.area_code,true) then
  raise exception 'Outside your leader edit scope' using errcode='42501';
 end if;
 perform revision from public.hdg_sync_state where division_code='G' for update;
 if exists(select 1 from hdg_sync_private.leader_cutover where pause_until>clock_timestamp()) then
  raise sqlstate 'PT503' using message='Division G leader saves are temporarily paused';
 end if;
 if not exists(select 1 from hdg_sync_private.leader_cutover where record_writes) then
  raise sqlstate 'PT409' using message='The per-record editor is unavailable';
 end if;
 allowed := hdg_sync_private.leader_fallback_fields(current_event.kind);
 if allowed is null then raise exception 'Unsupported event type' using errcode='22023'; end if;
 allowed := allowed||'$date'::text;
 if current_event.kind in ('tli_session','contest') then allowed := allowed||'$title'::text; end if;
 digest := sha256(convert_to(jsonb_build_array(p_event,p_fields)::text,'UTF8'));
 -- Reserve the ID before writing, including when concurrent requests address different events.
 insert into hdg_sync_private.leader_save_receipts(request_id,actor,request_digest,applied)
  values(p_request_id,auth.uid(),digest,false) on conflict (request_id) do nothing;
 if not found then
  select * into strict receipt from hdg_sync_private.leader_save_receipts where request_id=p_request_id;
  if receipt.actor is distinct from auth.uid() or receipt.request_digest is distinct from digest then
   raise exception 'Event request reused with different content' using errcode='22023';
  end if;
  return jsonb_build_object('applied',receipt.applied,'record',to_jsonb(current_event));
 end if;
 revised := current_event;
 for field,patch in select entry.key,entry.value from jsonb_each(p_fields) entry loop
  if jsonb_typeof(patch) is distinct from 'object' or not patch ?& array['before','after']
     or patch-array['before','after']<>'{}'
     or not field=any(allowed) then
   raise exception 'Invalid event patch field' using errcode='22023';
  end if;
  if field in ('$title','$date') and jsonb_typeof(patch->'after')<>'string' then
   raise exception 'Event title and date require text values' using errcode='22023';
  end if;
  current_value := case field when '$title' then to_jsonb(current_event.title)
                      when '$date' then to_jsonb(current_event.occurred_on)
                      else coalesce(current_event.details->field,'null') end;
  if current_value is not distinct from patch->'after' then continue; end if;
  if current_value is distinct from patch->'before' then
   late := jsonb_set(late,array[field],patch->'after');
   continue;
  end if;
  case field
   when '$title' then revised.title := nullif(btrim(patch->>'after'),'');
   when '$date' then revised.occurred_on := (patch->>'after')::date;
   else revised.details := case when patch->'after'='null' then revised.details-field
                                 else jsonb_set(revised.details,array[field],patch->'after') end;
  end case;
 end loop;
 if (revised.title,revised.occurred_on,revised.details) is distinct from
    (current_event.title,current_event.occurred_on,current_event.details) then
  update public.hdg_leader_records set title=revised.title,occurred_on=revised.occurred_on,
    details=revised.details,updated_at=clock_timestamp(),updated_by=auth.uid()
   where id=p_event returning * into revised;
  did_apply := true;
 end if;
 if late<>'{}' then
  insert into hdg_sync_private.superseded_edits(actor,table_name,row_key,patch)
  values(auth.uid(),'hdg_leader_records',p_event::text,late);
 end if;
 update hdg_sync_private.leader_save_receipts set applied=did_apply where request_id=p_request_id;
 delete from hdg_sync_private.leader_save_receipts where at<clock_timestamp()-interval '7 days';
 return jsonb_build_object('applied',did_apply,'record',to_jsonb(revised));
end $$;

create function public.hdg_set_leader_save_pause(p_pause boolean) returns jsonb
language plpgsql security definer set search_path to '' set lock_timeout to '5s' as $$
declare
 source_revision bigint;
 deadline timestamptz;
begin
 if not hdg_sync_private.is_maintainer() then
  raise exception 'Maintainer only' using errcode='42501';
 end if;
 if p_pause is null then raise exception 'Choose pause or resume' using errcode='22023'; end if;
 -- Match the ordering of the shared save. The revision is stable when this returns,
 -- and any later attempt to edit a migrated field sees the new pause.
 select revision into strict source_revision from public.hdg_sync_state where division_code='G' for update;
 update hdg_sync_private.leader_cutover
  set pause_until=case when not p_pause then null
    when pause_until>clock_timestamp() then pause_until
    else clock_timestamp()+interval '5 minutes' end
  returning pause_until into deadline;
 return jsonb_build_object('revision',source_revision,'pauseUntil',deadline);
end $$;

create function public.hdg_leader_cutover_status() returns jsonb
language sql stable security definer set search_path to '' as $$
 select jsonb_build_object('store',case when record_writes then 'records' else 'shared' end,
   'pauseUntil',case when pause_until>statement_timestamp() then pause_until end)
 from hdg_sync_private.leader_cutover
 where auth.uid() is not null and (hdg_sync_private.leader_scope('G',null,false)
   or exists(select 1 from public.hdg_officer_access
     where user_id=auth.uid() and division_code='G' and active))
$$;

create function public.hdg_return_leader_to_shared() returns jsonb
language plpgsql security definer set search_path to '' set lock_timeout to '5s' as $$
begin
 if not hdg_sync_private.is_maintainer() then
  raise exception 'Maintainer only' using errcode='42501';
 end if;
 perform revision from public.hdg_sync_state where division_code='G' for update;
 update hdg_sync_private.leader_cutover set record_writes=false,pause_until=null;
 return jsonb_build_object('store','shared','pauseUntil',null);
end $$;

revoke all on function hdg_sync_private.leader_legacy_projection(jsonb),
 hdg_sync_private.guard_shared_leader_pause(),
 hdg_sync_private.mirror_leader_event(),
 hdg_sync_private.leader_fallback_fields(text),
 hdg_sync_private.leader_event_fallback(jsonb,public.hdg_leader_records,public.hdg_leader_records)
 from public,anon,authenticated,service_role;
revoke all on function public.hdg_set_leader_save_pause(boolean),public.hdg_patch_leader_event(uuid,jsonb,uuid),
 public.hdg_leader_cutover_status(),public.hdg_return_leader_to_shared() from public,anon,authenticated,service_role;
grant execute on function public.hdg_set_leader_save_pause(boolean),public.hdg_patch_leader_event(uuid,jsonb,uuid),
 public.hdg_leader_cutover_status(),public.hdg_return_leader_to_shared() to authenticated;
notify pgrst,'reload schema';
commit;
