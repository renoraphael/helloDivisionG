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
  {"email":" HDG-TEST-MEMBER@example.invalid ","active":true},
  {"email":"hdg-test-unknown@example.invalid","active":false,"pastMember":true},
  {"email":"hdg-test-unverified@example.invalid","active":true}
 ]'::jsonb) where division_code='G';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000006322',true);
do $$
declare c jsonb;
begin
 if public.hdg_access_mode() <> 'member' then raise exception 'Member was not matched'; end if;
 c := public.hdg_member_community();
 if jsonb_typeof(c->'clubs') <> 'array' or jsonb_typeof(c->'meetings') <> 'array'
   or (c - array['clubs','meetings','events','leaders','updated']) <> '{}'::jsonb
   or exists (select 1 from jsonb_array_elements(c->'clubs') x where (x - array['name','city','area','mode','number','schedule','timezone','inactive','award','island','shortName','fill','text','accent']) <> '{}'::jsonb)
   or exists (select 1 from jsonb_array_elements(c->'meetings') x where (x - array['club','date','time','timezone']) <> '{}'::jsonb)
   or exists (select 1 from jsonb_array_elements(c->'events') x where (x - array['kind','title','date','time','timezone']) <> '{}'::jsonb)
   or exists (select 1 from jsonb_array_elements(c->'leaders') x where (x - array['name','role','scope']) <> '{}'::jsonb) then
   raise exception 'Community projection includes unexpected fields';
 end if;
 if exists(select 1 from public.hdg_sync_state) then raise exception 'Member could read leadership data'; end if;
 if exists(select 1 from storage.objects where bucket_id='hdg-private-app') then
   raise exception 'Member could read the leadership application';
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
