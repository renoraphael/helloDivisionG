begin;

create or replace function public.hdg_member_community()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare snapshot jsonb;
declare division_director text;
declare synced_at timestamptz;
declare member_name text;
begin
 if public.hdg_access_mode() not in ('member', 'leader') then
   raise exception 'Verified Toastmasters membership required' using errcode = '42501';
 end if;
 select payload->'database', payload #>> '{settings,divisionDirector}', updated_at
 into snapshot, division_director, synced_at from public.hdg_sync_state where division_code = 'G';

 select nullif(btrim(m->>'name'),'') into member_name
 from auth.users u
 cross join lateral jsonb_array_elements(snapshot->'memberships') m
 where u.id = auth.uid()
   and u.email_confirmed_at is not null
   and lower(btrim(m->>'email')) = lower(btrim(u.email))
   and m->>'active' = 'true'
   and coalesce(m->>'pastMember','false') <> 'true'
   and nullif(btrim(m->>'name'),'') is not null
 order by m->>'lastSeen' desc nulls last, btrim(m->>'name')
 limit 1;

 return jsonb_build_object(
   'memberName', member_name,
   'updated', synced_at,
   'clubs', coalesce((
     select jsonb_agg(jsonb_build_object(
       'name', c->>'name', 'area', c->>'area', 'city', c->>'city', 'mode', c->>'mode',
       'number', c->>'number', 'schedule', c #>> '{publicProfile,meetingSchedule}',
       'island', c->>'island',
       'shortName', coalesce(c #>> '{publicProfile,calendarBrand,shortName}', c #>> '{publicProfile,calendarShortName}'),
       'fill', c #>> '{publicProfile,calendarBrand,fill}', 'text', c #>> '{publicProfile,calendarBrand,text}',
       'accent', c #>> '{publicProfile,calendarBrand,accent}',
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
       'time', start_time, 'timezone', timezone, 'clubNumber', club_number) order by day, title)
     from (
       select 'TLI' as kind, x->>'name' as title, x->>'date' as day, x->>'start' as start_time, x->>'timezone' as timezone, null::text as club_number
       from jsonb_array_elements(snapshot->'tlis') x
       union all
       select 'Contest', x->>'title', x->>'date', x->>'start', x->>'timezone', null::text
       from jsonb_array_elements(snapshot->'contests') x
       union all
       select 'Club meeting', x->>'title', x->>'date', coalesce(x->>'start',x->>'startTime'), x->>'timezone', x->>'clubNumber'
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
