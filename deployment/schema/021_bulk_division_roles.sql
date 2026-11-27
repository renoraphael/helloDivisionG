-- Division role assignment by Toastmasters member ID. Preview is read-only and apply is atomic.
begin;

create function public.hdg_bulk_division_roles(p_division text, p_year int, p_rows jsonb, p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
 term public.hdg_program_years%rowtype;
 current_day date := hdg_sync_private.today();
 entry jsonb; item jsonb; results jsonb := '[]'; applied jsonb := '[]';
 matches uuid[]; person uuid; role_name text; scope text; council_title text; member_key text;
 existing uuid; issue text; row_num int := 0; role_id uuid;
begin
 if not hdg_sync_private.is_maintainer() then raise exception 'Maintainer only' using errcode='42501'; end if;
 if not exists(select 1 from public.hdg_divisions where code=p_division) then
  raise exception 'Unknown division' using errcode='22023';
 end if;
 select * into term from public.hdg_program_years where year_start=p_year;
 if not found or current_day not between term.transition_opens and term.ends_on then
  raise exception 'Program year is outside its role assignment window' using errcode='22023';
 end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then
  raise exception 'Expected a list of role assignments' using errcode='22023';
 end if;
 if jsonb_array_length(p_rows) not between 1 and 100 then
  raise exception 'Supply between 1 and 100 role assignments' using errcode='22023';
 end if;
 if p_apply then
  -- Do not let another role edit or roster import change validation during the batch.
  lock table public.hdg_people, public.hdg_memberships, public.hdg_roles in share row exclusive mode;
  if p_division <> 'G' and not exists(select 1 from public.hdg_divisions
      where code=p_division and config->>'memberImport'='open') then
   raise exception 'Complete privacy setup and open imports for this division first' using errcode='42501';
  end if;
 end if;

 for entry in select value from jsonb_array_elements(p_rows) loop
  row_num := row_num + 1;
  issue := null; person := null; existing := null;
  member_key := upper(ltrim(btrim(coalesce(entry->>'memberId','')),'0'));
  role_name := btrim(coalesce(entry->>'role',''));
  scope := case when role_name='area_director' then upper(btrim(coalesce(entry->>'area',''))) else p_division end;
  council_title := nullif(btrim(entry->>'title'),'');
  if jsonb_typeof(entry)<>'object' then
   issue := 'invalid_row';
  elsif entry-array['memberId','role','area','title'] <> '{}'::jsonb then
   issue := 'unknown_field';
  elsif member_key !~ '^[A-Z0-9]{1,20}$' then
   issue := 'invalid_member_id';
  elsif role_name not in ('division_director','area_director','division_council') then
   issue := 'invalid_role';
  elsif role_name='division_council' and (council_title is null or length(council_title)>80) then
   issue := 'invalid_council_title';
  elsif role_name<>'division_council' and council_title is not null then
   issue := 'title_only_for_council';
  elsif role_name='area_director' and not exists(select 1 from public.hdg_areas
        where year_start=p_year and code=scope and division_code=p_division) then
   issue := 'area_outside_division';
  elsif role_name<>'area_director' and nullif(btrim(entry->>'area'),'') is not null then
   issue := 'area_only_for_area_director';
  else
   select array_agg(id) into matches from public.hdg_people
   where upper(ltrim(ti_member_id,'0'))=member_key and not provisional;
   if coalesce(cardinality(matches),0)=0 then issue := 'member_not_imported';
   elsif cardinality(matches)>1 then issue := 'ambiguous_member_id';
   else
    person := matches[1];
    if not exists (
      select 1 from public.hdg_memberships m
      join public.hdg_club_alignment a on a.club_number=m.club_number
      where m.person_id=person and m.status='active' and a.status='approved'
       and a.year_start in (p_year, hdg_sync_private.year_of(current_day)) and left(a.area_code,1)=p_division
    ) then issue := 'no_active_membership_in_division';
    else
     select r.id into existing from public.hdg_roles r where r.role=role_name and r.scope_code=scope
       and r.person_id=person and r.year_start=p_year and r.ends_on>=greatest(term.starts_on,current_day)
       and r.title is not distinct from council_title order by r.starts_on limit 1;
     if exists (select 1 from public.hdg_roles r where r.role=role_name and r.scope_code=scope
       and r.person_id<>person and r.year_start=p_year and r.ends_on>=greatest(term.starts_on,current_day)
       and (role_name<>'division_council' or lower(r.title)=lower(council_title))) then
      issue := 'seat_already_filled';
     elsif exists(select 1 from jsonb_array_elements(results) prior
       where prior->>'role'=role_name and prior->>'scope'=scope
       and (role_name<>'division_council' or lower(prior->>'title')=lower(council_title))
       and prior->>'issue' is null) then
      issue := 'duplicate_seat_in_batch';
     end if;
    end if;
   end if;
  end if;
  results := results || jsonb_build_array(jsonb_build_object('row',row_num,'role',role_name,'scope',scope,
   'title',council_title,'person',person,'existingRole',existing,'issue',issue));
 end loop;
 if exists(select 1 from jsonb_array_elements(results) e where e->>'issue' is not null) then
  return jsonb_build_object('applied',false,'valid',false,'rows',results);
 end if;
 if not coalesce(p_apply,false) then
  return jsonb_build_object('applied',false,'valid',true,'rows',results);
 end if;

 for item in select value from jsonb_array_elements(results) loop
  role_id := (item->>'existingRole')::uuid;
  if role_id is null then
   insert into public.hdg_roles(person_id,role,scope_type,scope_code,year_start,starts_on,ends_on,entered_by,title)
   values ((item->>'person')::uuid,item->>'role',case when item->>'role'='area_director' then 'area' else 'division' end,
    item->>'scope',p_year,greatest(term.starts_on,current_day),term.ends_on,auth.uid(),item->>'title')
   returning id into role_id;
  end if;
  applied := applied || jsonb_build_array(item || jsonb_build_object('roleId',role_id));
 end loop;
 insert into hdg_sync_private.access_log(actor,action,detail)
 values(auth.uid(),'bulk_division_roles',jsonb_build_object('division',p_division,'year',p_year,'rows',row_num));
 return jsonb_build_object('applied',true,'valid',true,'rows',applied);
end $$;
revoke execute on function public.hdg_bulk_division_roles(text,int,jsonb,boolean) from public, anon;
grant execute on function public.hdg_bulk_division_roles(text,int,jsonb,boolean) to authenticated;
notify pgrst, 'reload schema';
commit;
