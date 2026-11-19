begin;
create or replace function hdg_sync_private.manage_officer(p_email text,p_active boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target_id uuid; actor_id uuid:=auth.uid();
begin
 if actor_id is null or not exists(select 1 from public.hdg_officer_access where user_id=actor_id and division_code='G' and app_role='administrator' and active) then
  raise exception 'Administrator approval required' using errcode='42501';
 end if;
 if p_email is null or p_active is null then raise exception 'Email and approval state required' using errcode='22023'; end if;
 select id into target_id from auth.users where lower(email)=lower(btrim(p_email)) and email_confirmed_at is not null;
 if target_id is null then raise exception 'This officer must create and confirm their login first' using errcode='22023'; end if;
 if exists(select 1 from public.hdg_officer_access where user_id=target_id and division_code='G' and app_role='administrator') then
  raise exception 'Administrator access cannot be changed through officer approval' using errcode='42501';
 end if;
 insert into public.hdg_officer_access(user_id,division_code,app_role,active)
 values(target_id,'G','officer',p_active)
 on conflict(user_id,division_code) do update set active=excluded.active,approved_at=now();
 return jsonb_build_object('email',lower(btrim(p_email)),'active',p_active);
end $$;
revoke all on function hdg_sync_private.manage_officer(text,boolean) from public,anon,authenticated;
grant execute on function hdg_sync_private.manage_officer(text,boolean) to authenticated;
create or replace function public.hdg_manage_officer(p_email text,p_active boolean)
returns jsonb language sql security invoker set search_path='' as $$select hdg_sync_private.manage_officer(p_email,p_active);$$;
revoke all on function public.hdg_manage_officer(text,boolean) from public,anon,authenticated;
grant execute on function public.hdg_manage_officer(text,boolean) to authenticated;
commit;
select 'Officer management is restricted to approved administrators' as result;
