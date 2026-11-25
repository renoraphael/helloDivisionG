begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-8000-00000000c001','hdg-admin-test@example.invalid',now()),
('00000000-0000-4000-8000-00000000c002','hdg-officer-test@example.invalid',now());
insert into public.hdg_officer_access(user_id,app_role) values('00000000-0000-4000-8000-00000000c001','administrator');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000c002',true);
do $$begin
 begin
 perform public.hdg_manage_officer('hdg-officer-test@example.invalid',true);
 raise exception 'Self-approval allowed';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000c001',true);
select public.hdg_manage_officer('hdg-officer-test@example.invalid',true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000c002',true);
do $$begin
 if (select count(*) from public.hdg_sync_state)<>1 then raise exception 'Approval did not enable access';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000c001',true);
select public.hdg_manage_officer('hdg-officer-test@example.invalid',false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000c002',true);
do $$begin
 if (select count(*) from public.hdg_sync_state)<>0 then raise exception 'Revocation did not block access';end if;
end $$;
reset role;
rollback;
select 'PASS: self-approval blocked; administrator approval and revocation verified; test identities rolled back' as result;
