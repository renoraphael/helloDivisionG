begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-8000-00000000e001','hdg-storage-approved@example.invalid',now()),
('00000000-0000-4000-8000-00000000e002','hdg-storage-denied@example.invalid',now());
insert into public.hdg_officer_access(user_id,app_role) values('00000000-0000-4000-8000-00000000e001','officer');
do $$begin
 if (select public from storage.buckets where id='hdg-private-app') is distinct from false then raise exception 'App bucket is not private';end if;
 if (select count(*) from storage.objects where bucket_id='hdg-private-app' and name='v487.html')<>1 then raise exception 'Protected app missing';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000e002',true);
do $$begin
 if (select count(*) from storage.objects where bucket_id='hdg-private-app')<>0 then raise exception 'Unapproved app download allowed';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000e001',true);
do $$begin
 if (select count(*) from storage.objects where bucket_id='hdg-private-app' and name='v487.html')<>1 then raise exception 'Approved app download denied';end if;
end $$;
reset role;
update public.hdg_officer_access set active=false where user_id='00000000-0000-4000-8000-00000000e001';
set local role authenticated;
do $$begin
 if (select count(*) from storage.objects where bucket_id='hdg-private-app')<>0 then raise exception 'Revoked officer retained app download access';end if;
end $$;
reset role;
set local role anon;
do $$begin
 begin
  if (select count(*) from storage.objects where bucket_id='hdg-private-app')<>0 then raise exception 'Anonymous app download allowed';end if;
 exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS: private bucket, file present, approved download, unapproved/anonymous/revoked denial; test users rolled back' as result;
