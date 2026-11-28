-- Read-only preflight. Returns effective account counts and no identities.
-- Run as the database owner against the explicitly selected project.
begin read only;
do $$
declare
 account record;
 old_count int := 0;
 both_read int := 0;
 both_write int := 0;
 read_only int := 0;
 legacy_no_scope int := 0;
 scoped_only int := 0;
 can_read boolean;
 can_write boolean;
begin
 for account in select u.id,exists(select 1 from public.hdg_officer_access a
   where a.user_id=u.id and a.division_code='G' and a.active) legacy from auth.users u loop
  perform set_config('request.jwt.claim.sub',account.id::text,true);
  can_read := hdg_sync_private.leader_scope('G',null,false);
  can_write := hdg_sync_private.leader_scope('G',null,true) or exists (
   select 1 from public.hdg_areas a where a.division_code='G'
     and a.year_start=hdg_sync_private.year_of(hdg_sync_private.today())
     and hdg_sync_private.leader_scope('G',a.code,true));
  if account.legacy then
   old_count:=old_count+1;
   if can_read then both_read:=both_read+1; else legacy_no_scope:=legacy_no_scope+1; end if;
   if can_write then both_write:=both_write+1; elsif can_read then read_only:=read_only+1; end if;
  elsif can_read then scoped_only:=scoped_only+1;
  end if;
 end loop;
 perform set_config('hdg.readiness_counts',jsonb_build_object('legacy_accounts',old_count,
  'can_read_scoped',both_read,'can_write_scoped',both_write,'read_only_scoped',read_only,
  'no_scoped_access',legacy_no_scope,'scoped_only_accounts',scoped_only)::text,true);
end $$;
select current_setting('hdg.readiness_counts');
rollback;
