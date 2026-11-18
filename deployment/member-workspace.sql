begin;

create or replace function public.hdg_member_community()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare snapshot jsonb;
declare division_director text;
begin
 if public.hdg_access_mode() not in ('member', 'leader') then
   raise exception 'Verified Toastmasters membership required' using errcode = '42501';
 end if;
 select payload->'database', payload #>> '{settings,divisionDirector}'
 into snapshot, division_director from public.hdg_sync_state where division_code = 'G';

 return jsonb_build_object(
   'clubs', coalesce((
     select jsonb_agg(jsonb_build_object(
       'name', c->>'name', 'area', c->>'area', 'city', c->>'city', 'mode', c->>'mode',
       'number', c->>'number', 'schedule', c #>> '{publicProfile,meetingSchedule}',
       'timezone', c #>> '{publicProfile,timezone}', 'inactive', c #>> '{publicProfile,inactive}',
       'award', case when award in ('Distinguished', 'Select Distinguished', 'President''s Distinguished', 'Smedley Distinguished') then award end
     ) order by c->>'name')
     from jsonb_array_elements(snapshot->'clubs') c
     cross join lateral (select coalesce(nullif(c->>'officialAward',''), nullif(c->>'officialRecognition',''),
       nullif(c->>'dashboardAward',''), c->>'clubAward') as award) a
     where nullif(c->>'name','') is not null
   ), '[]'::jsonb),
   'meetings', coalesce((
     select jsonb_agg(summary order by summary->>'date', summary->>'club')
     from (
       select jsonb_build_object('club', m->>'clubName', 'date', m->>'meetingDate',
         'time', m->>'startTime', 'timezone', m->>'timezone') as summary
       from jsonb_array_elements(snapshot->'meetingAgendaRecords') m
       where m->>'meetingDate' ~ '^\d{4}-\d{2}-\d{2}$'
         and m->>'meetingDate' >= (now() at time zone 'Asia/Makassar')::date::text
       order by m->>'meetingDate', m->>'clubName' limit 100
     ) upcoming
   ), '[]'::jsonb),
   'events', coalesce((
     select jsonb_agg(jsonb_build_object('kind', kind, 'title', title, 'date', day,
       'time', start_time, 'timezone', timezone) order by day, title)
     from (
       select 'TLI' as kind, x->>'name' as title, x->>'date' as day, x->>'start' as start_time, x->>'timezone' as timezone
       from jsonb_array_elements(snapshot->'tlis') x
       union all
       select 'Contest', x->>'title', x->>'date', x->>'start', x->>'timezone'
       from jsonb_array_elements(snapshot->'contests') x
       union all
       select 'Club meeting', x->>'title', x->>'date', x->>'start', x->>'timezone'
       from jsonb_array_elements(snapshot->'specialMeetings') x
     ) schedule
     where day ~ '^\d{4}-\d{2}-\d{2}$' and nullif(title,'') is not null
   ), '[]'::jsonb),
   'leaders', coalesce((
     select jsonb_agg(jsonb_build_object('name', name, 'role', title, 'scope', area) order by area, title)
     from (
       select division_director as name, 'Division Director' as title, 'Division G' as area
       union all
       select a->>'director', 'Area Director', a->>'code'
       from jsonb_array_elements(snapshot->'areas') a
     ) leadership
     where nullif(name,'') is not null
   ), '[]'::jsonb)
 );
end;
$$;

revoke all on function public.hdg_member_community() from public, anon, authenticated;
grant execute on function public.hdg_member_community() to authenticated;

commit;
