begin;

insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-4000-8000-000000006321', 'hdg-test-leader@example.invalid', now()),
 ('00000000-0000-4000-8000-000000006322', 'hdg-test-member@example.invalid', now()),
 ('00000000-0000-4000-8000-000000006323', 'hdg-test-unknown@example.invalid', now()),
 ('00000000-0000-4000-8000-000000006324', 'hdg-test-beta@example.invalid', now()),
 ('00000000-0000-4000-8000-000000006325', 'hdg-test-unverified@example.invalid', null),
 ('00000000-0000-4000-8000-000000006326', 'hdg-test-other-leader@example.invalid', now());

insert into public.hdg_officer_access (user_id, app_role) values
 ('00000000-0000-4000-8000-000000006321', 'officer'),
 ('00000000-0000-4000-8000-000000006326', 'officer');
insert into hdg_community_private.beta_members(user_id) values
 ('00000000-0000-4000-8000-000000006324');

update public.hdg_sync_state set payload = jsonb_set(payload,'{database,memberships}',
 (payload #> '{database,memberships}') || '[
  {"name":"Fixture Member","email":" HDG-TEST-MEMBER@example.invalid ","clubNumber":"00012345678","memberId":"99112233","active":true},
  {"name":"Fixture Visiting Member","clubNumber":"12345679","active":true},
  {"name":"Fixture Past Member","clubNumber":"12345679","pastMember":true,"active":true},
  {"name":"Fixture Inactive Member","clubNumber":"12345679","active":false},
  {"name":"Fixture Outside Member","clubNumber":"99912345678","active":true},
  {"email":"hdg-test-unknown@example.invalid","active":false,"pastMember":true},
  {"email":"hdg-test-unverified@example.invalid","active":true}
 ]'::jsonb) where division_code='G';

update public.hdg_sync_state set payload = jsonb_set(jsonb_set(payload,'{database,clubs}',
 (payload #> '{database,clubs}') || '[{"number":"00012345678","name":"Fixture Club","dcpGoals":"7","publicProfile":{"meetingMode":"Hybrid","locationTitle":"Fixture Venue","locationAddress":"Fixture Address","publicLocation":"Fixture Venue · Fixture Address","phone":"private"}},{"number":"00012345679","name":"Fixture Zero","dcpGoals":0},{"number":"00012345680","name":"Fixture Missing"}]'::jsonb),
 '{database,exco}', coalesce(payload #> '{database,exco}', '[]'::jsonb) || '[
  {"clubNumber":"12345678","role":"Club President","name":"Former Fixture","past":true},
  {"clubNumber":"00012345678","role":"Club President","name":"Fixture President","contact":"private@example.invalid"},
  {"clubNumber":"12345678","role":"Club VP Education","name":"Expired Fixture","term":"2000-07-01 – 2001-06-30"},
  {"clubNumber":"12345678","role":"Club VP Education","name":"Fixture Education","term":"2000-07-01 – 9999-06-30"},
  {"clubNumber":"12345678","role":"Club VP Membership","name":"Fixture Membership"},
  {"clubNumber":"12345678","role":"Club Secretary","name":"Fixture Secretary"},
  {"clubNumber":"12345678","role":"Club Liaison no proxy","name":"Other Officer"},
  {"clubNumber":"12345678901","role":"Club President","name":"Outside Division"}
 ]'::jsonb) where division_code='G';

insert into hdg_community_private.club_agenda_defaults(club_number, settings)
values ('12345678', '{"zoomId":"fixture-id","zoomPass":"fixture-pass","other":"omit","people":{"fixture president":{"ig":"@fixture","excoRole":"Club President","other":"omit"}}}');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006322',true);
do $$
declare c jsonb;
begin
 if public.hdg_access_mode() <> 'member' then raise exception 'Member was not matched'; end if;
 c := public.hdg_member_community();
 if c->>'memberName' is distinct from 'Fixture Member' then raise exception 'Member name did not resolve'; end if;
 if c #> '{clubAgendaDefaults,12345678}' is distinct from
   '{"zoomId":"fixture-id","zoomPass":"fixture-pass","people":{"fixture president":{"ig":"@fixture","email":"private@example.invalid"}}}'::jsonb then
   raise exception 'Signed-in member cannot read the club sidebar defaults';
 end if;
 begin
   perform 1 from hdg_community_private.club_agenda_defaults;
   raise exception 'Member can query private defaults table directly';
 exception when insufficient_privilege then null; end;
 if jsonb_typeof(c->'clubs') <> 'array' or jsonb_typeof(c->'meetings') <> 'array'
   or (c - array['clubs','meetings','events','leaders','clubOfficers','agendaMembers','clubAgendaDefaults','updated','memberName']) <> '{}'::jsonb
   or exists (select 1 from jsonb_array_elements(c->'clubs') x where (x - array['name','city','area','mode','number','schedule','timezone','inactive','award','island','meetingMode','locationTitle','locationAddress','publicLocation','shortName','fill','text','accent','dcpGoals']) <> '{}'::jsonb)
   or exists (select 1 from jsonb_array_elements(c->'meetings') x where (x - array['club','date','time','timezone']) <> '{}'::jsonb)
   or exists (select 1 from jsonb_array_elements(c->'events') x where (x - array['kind','title','date','time','timezone','clubNumber']) <> '{}'::jsonb)
   or exists (select 1 from jsonb_array_elements(c->'leaders') x where (x - array['name','role','scope']) <> '{}'::jsonb)
   or jsonb_typeof(c->'agendaMembers') is distinct from 'array'
   or exists (select 1 from jsonb_array_elements(c->'agendaMembers') x where (x - array['name','clubNumber']) <> '{}'::jsonb)
   or jsonb_typeof(c->'clubOfficers') is distinct from 'array'
   or exists (select 1 from jsonb_array_elements(c->'clubOfficers') x where (x - array['name','role','clubNumber']) <> '{}'::jsonb) then
   raise exception 'Community projection includes unexpected fields';
 end if;
 if (select jsonb_agg(x order by x->>'name') from jsonb_array_elements(c->'agendaMembers') x where x->>'name' like 'Fixture %')
   is distinct from '[{"name":"Fixture Member","clubNumber":"12345678"},{"name":"Fixture Visiting Member","clubNumber":"12345679"}]'::jsonb then
   raise exception 'Agenda names did not match the active cross-club roster';
 end if;
 if (select x->>'meetingMode' from jsonb_array_elements(c->'clubs') x where x->>'number'='00012345678')
   is distinct from 'Hybrid'
   or (select x->>'publicLocation' from jsonb_array_elements(c->'clubs') x where x->>'number'='00012345678')
   is distinct from 'Fixture Venue · Fixture Address' then
   raise exception 'Agenda location defaults did not match the shared club records';
 end if;
 if (select x->'dcpGoals' from jsonb_array_elements(c->'clubs') x where x->>'number'='00012345678')
   is distinct from '7'::jsonb
   or (select x->'dcpGoals' from jsonb_array_elements(c->'clubs') x where x->>'number'='00012345679')
   is distinct from '0'::jsonb
   or (select x->'dcpGoals' from jsonb_array_elements(c->'clubs') x where x->>'number'='00012345680')
   is distinct from 'null'::jsonb then
   raise exception 'Member DCP values did not match the shared club records';
 end if;
 if (select jsonb_agg(x order by x->>'role') from jsonb_array_elements(c->'clubOfficers') x where x->>'clubNumber'='12345678')
   is distinct from '[
    {"clubNumber":"12345678","role":"Club President","name":"Fixture President"},
    {"clubNumber":"12345678","role":"Club Secretary","name":"Fixture Secretary"},
    {"clubNumber":"12345678","role":"Club VP Education","name":"Fixture Education"},
    {"clubNumber":"12345678","role":"Club VP Membership","name":"Fixture Membership"}
   ]'::jsonb
   or exists (select 1 from jsonb_array_elements(c->'clubOfficers') x where x->>'clubNumber'='12345678901') then
   raise exception 'Club officers did not match the current Division G roster';
 end if;
 if exists(select 1 from public.hdg_sync_state) then raise exception 'Member could read leadership data'; end if;
 if exists(select 1 from storage.objects where bucket_id='hdg-private-app' and name not in ('v632-member.html','v632-member-profile.html','v632-member-directory.html','v632-member-leadership.html','v632-member-club-officers.html','v632-member-dcp.html','v632-member-agenda-roster.html','v632-member-agenda-sidebar.html','v632-member-agenda-attendance.html','v632-member-agenda-attendance-theme.html','v632-member-agenda-defaults.html','v632-member-club-attendance.html')) then
   raise exception 'Member could read the leadership application';
 end if;
 if not exists(select 1 from storage.objects where bucket_id='hdg-private-app' and name='v632-member-club-attendance.html') then
   raise exception 'Member could not read the original workspace build';
 end if;
 begin
   perform public.hdg_manage_ballot('test-meeting','status');
   raise exception 'Member can manage ballots';
 exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006323',true);
do $$begin
 if public.hdg_access_mode() <> 'none' then raise exception 'Inactive member granted access'; end if;
 begin
   perform public.hdg_member_community();
   raise exception 'Unmatched user can read Community';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006324',true);
do $$begin
 if public.hdg_access_mode() <> 'member' or exists(select 1 from public.hdg_sync_state) then
   raise exception 'Beta member role is incorrect';
 end if;
 if public.hdg_member_community() #>> '{clubAgendaDefaults,12345678,zoomPass}' is distinct from 'fixture-pass' then
   raise exception 'Visiting Member cannot read the club sidebar defaults';
 end if;
 if public.hdg_member_community()->>'memberName' is not null then
   raise exception 'Unmatched beta account received a roster name';
 end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006325',true);
do $$begin
 if public.hdg_access_mode() <> 'none' then raise exception 'Unverified address granted access'; end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006321',true);
do $$
declare item jsonb;
begin
 if public.hdg_access_mode() <> 'leader' then raise exception 'Approved leader lost access'; end if;
 if not exists(select 1 from storage.objects where bucket_id='hdg-private-app' and name='v632-community.html') then
   raise exception 'Approved leader cannot read the connected build';
 end if;
 item := public.hdg_manage_ballot('test-meeting','publish','Fixture ballot',
   '{"prepared":[{"name":"Fixture speaker","id":"speaker"}],"evaluation":[],"topics":[]}'::jsonb);
 perform set_config('hdg.fixture_token',item->>'token',true);
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006326',true);
do $$begin
 if public.hdg_manage_ballot('test-meeting','status') is not null then
   raise exception 'Another leader can see the host tally';
 end if;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$
declare token uuid := current_setting('hdg.fixture_token')::uuid;
declare view_data jsonb;
begin
 begin
   perform public.hdg_member_community();
   raise exception 'Anonymous request can read Community';
 exception when insufficient_privilege then null; end;
 view_data := public.hdg_open_ballot(token);
 if view_data is null or (view_data - array['title','choices']) <> '{}'::jsonb then
   raise exception 'Unexpected public ballot fields';
 end if;
 if public.hdg_open_ballot(gen_random_uuid()) is not null then raise exception 'Invalid token resolved'; end if;
 begin
   perform public.hdg_cast_ballot(token, gen_random_uuid(), '{"prepared":"ineligible","evaluation":"","topics":""}');
   raise exception 'Invalid candidate accepted';
 exception when invalid_parameter_value then null; end;
 perform public.hdg_cast_ballot(token, '00000000-0000-4000-8000-000000006321', '{"prepared":"speaker","evaluation":"","topics":""}');
 perform public.hdg_cast_ballot(token, '00000000-0000-4000-8000-000000006321', '{"prepared":"speaker","evaluation":"","topics":""}');
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006321',true);
do $$
declare item jsonb;
begin
 item := public.hdg_manage_ballot('test-meeting','close');
 if item->>'responses' <> '1' or item #>> '{counts,prepared,speaker}' <> '1'
   or item->>'open' <> 'false' then raise exception 'Private tally or duplicate handling failed'; end if;
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$
declare token uuid := current_setting('hdg.fixture_token')::uuid;
begin
 if public.hdg_open_ballot(token) is not null then raise exception 'Closed ballot is still visible'; end if;
 begin
   perform public.hdg_cast_ballot(token, gen_random_uuid(), '{"prepared":"speaker","evaluation":"","topics":""}');
   raise exception 'Closed ballot accepted a vote';
 exception when invalid_parameter_value then null; end;
end $$;

rollback;
select 'PASS: verified roster, beta access, leader isolation, anonymous vote, private tally, duplicate and closed-vote checks' as result;
