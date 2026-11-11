begin;
-- Everything in this test, including test identities and writes, rolls back.
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-8000-00000000a001','hdg-approved-test@example.invalid',now()),
('00000000-0000-4000-8000-00000000a002','hdg-unapproved-test@example.invalid',now());
insert into public.hdg_officer_access(user_id,app_role) values('00000000-0000-4000-8000-00000000a001','officer');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000a002',true);
do $$
begin
 if (select count(*) from public.hdg_sync_state)<>0 then raise exception 'Unapproved read leaked data'; end if;
 begin
   perform public.hdg_save_web_state(1,'{}'::jsonb,'00000000-0000-4000-8000-00000000b001');
   raise exception 'Unapproved write was allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000a001',true);
do $$
declare r bigint; p jsonb; a jsonb; b jsonb;
begin
 select revision,payload into r,p from public.hdg_sync_state where division_code='G';
 if r is null then raise exception 'Approved read failed'; end if;
 a:=public.hdg_save_web_state(r,p,'00000000-0000-4000-8000-00000000b001');
 if (a->>'revision')::bigint<>r+1 then raise exception 'Revision did not advance'; end if;
 b:=public.hdg_save_web_state(r,p,'00000000-0000-4000-8000-00000000b001');
 if b->>'duplicate'<>'true' or (b->>'revision')::bigint<>r+1 then raise exception 'Retry was not idempotent'; end if;
 begin
   perform public.hdg_save_web_state(r,p,'00000000-0000-4000-8000-00000000b002');
   raise exception 'Stale write was allowed';
 exception when serialization_failure then null;
 end;
 begin
   perform public.hdg_save_web_state(r+1,p||'{"ui":{}}'::jsonb,'00000000-0000-4000-8000-00000000b003');
   raise exception 'Device UI was allowed into shared data';
 exception when invalid_parameter_value then null;
 end;
 begin
   update public.hdg_sync_state set revision=999 where division_code='G';
   raise exception 'Direct write bypassed revision checks';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
update public.hdg_officer_access set active=false where user_id='00000000-0000-4000-8000-00000000a001';
set local role authenticated;
do $$
begin
 if (select count(*) from public.hdg_sync_state)<>0 then raise exception 'Revoked officer still has access'; end if;
 begin
  perform public.hdg_save_web_state(1,'{}'::jsonb,'00000000-0000-4000-8000-00000000b009');
  raise exception 'Revoked officer write allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
set local role anon;
do $$
begin
 begin
  perform count(*) from public.hdg_sync_state;
  raise exception 'Anonymous read allowed';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.hdg_save_web_state(1,'{}'::jsonb,'00000000-0000-4000-8000-00000000b010');
  raise exception 'Anonymous write allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
rollback;
select 'PASS: access, revocation, stale saves, retry idempotency, direct-write protection; all test data rolled back' as result;
